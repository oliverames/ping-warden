#if canImport(CryptoKit) && canImport(SQLite3) && canImport(Darwin)
import Darwin
import Foundation
import SQLite3

enum MigrationSQLiteError: Error { case unsafeStorage, unavailable }

/// Explicit construction only. No production caller or default destination.
/// Reopen never creates missing paths or repairs permissions/schema.
final class MigrationSQLitePersistence: MigrationImportPersistence {
    private static let databaseName = "Staging.sqlite"
    private static let applicationID: Int64 = 0x50574D47
    private static var limit: Int { MigrationImportCoordinator<MigrationSQLitePersistence>.maximumRecordBytes }
    private static let revisionsSQL = "CREATE TABLE revisions (revision TEXT PRIMARY KEY NOT NULL CHECK(length(revision)=36))"
    private static var recordsSQL: String {
        "CREATE TABLE records (transaction_id TEXT PRIMARY KEY NOT NULL CHECK(length(transaction_id)=36), revision TEXT NOT NULL REFERENCES revisions(revision), payload BLOB NOT NULL CHECK(typeof(payload)='blob' AND length(payload)<=\(limit)))"
    }
    private let lock = NSLock()
    private let boundary: Boundary
    private var database: OpaquePointer?
    private var poisoned = false

    static func create(at directory: URL) throws -> MigrationSQLitePersistence {
        try MigrationSQLitePersistence(directory: directory, create: true)
    }

    static func reopen(at directory: URL) throws -> MigrationSQLitePersistence {
        try MigrationSQLitePersistence(directory: directory, create: false)
    }

    private init(directory: URL, create: Bool) throws {
        boundary = try Boundary(directory: directory, create: create)
        do {
            try boundary.validate()
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_PRIVATECACHE
            guard sqlite3_open_v2(boundary.databaseURL.path, &database, flags, nil) == SQLITE_OK,
                  let database else { throw MigrationSQLiteError.unavailable }
            sqlite3_extended_result_codes(database, 1)
            sqlite3_busy_timeout(database, 0)
            sqlite3_limit(database, SQLITE_LIMIT_LENGTH, Int32(Self.limit + 4096))
            try exec("PRAGMA trusted_schema=OFF")
            try exec("PRAGMA foreign_keys=ON")
            try exec("PRAGMA temp_store=MEMORY")
            try exec("PRAGMA mmap_size=0")
            try exec("PRAGMA synchronous=FULL")
            try exec("PRAGMA fullfsync=ON")
            guard try scalar("PRAGMA journal_mode=PERSIST") == "persist",
                  try scalar("PRAGMA trusted_schema") == "0",
                  try scalar("PRAGMA foreign_keys") == "1",
                  try scalar("PRAGMA temp_store") == "2",
                  try scalar("PRAGMA mmap_size") == "0",
                  try scalar("PRAGMA synchronous") == "2",
                  try scalar("PRAGMA fullfsync") == "1" else { throw MigrationSQLiteError.unavailable }
            try checkLocation()
            if create {
                try exec("BEGIN IMMEDIATE")
                try exec(Self.revisionsSQL)
                try exec(Self.recordsSQL)
                try exec("PRAGMA application_id=\(Self.applicationID)")
                try exec("PRAGMA user_version=1")
                try checkLocation()
                try exec("COMMIT")
            }
            try exec("BEGIN")
            try validateSchema()
            try exec("COMMIT")
            try checkLocation()
        } catch {
            closeAfterFailure()
            // A failed create leaves its private partial directory for review.
            // It is never silently reopened, initialized again or deleted.
            throw error
        }
    }

    deinit { if let database { sqlite3_close(database) } }

    func read(transactionID: UUID) -> MigrationRead<MigrationImportVersion> {
        lock.lock()
        defer { lock.unlock() }
        do {
            try checkLocation()
            try exec("BEGIN")
            try validateSchema()
            let value = try load(transactionID)
            try checkLocation()
            try exec("COMMIT")
            try checkLocation()
            return value.map { .available($0) } ?? .absent
        } catch {
            closeAfterFailure()
            return .unavailable
        }
    }

    func compareAndSwap(transactionID: UUID, expected: MigrationImportVersion?, replacement: Data) -> MigrationImportWriteResult {
        lock.lock()
        defer { lock.unlock() }
        guard !replacement.isEmpty, replacement.count <= Self.limit,
              expected.map({ $0.bytes.count <= Self.limit }) ?? true else { return .unavailable }
        var mutationAttempted = false
        do {
            try checkLocation()
            try exec("BEGIN IMMEDIATE")
            try validateSchema()
            guard try load(transactionID) == expected else {
                try exec("ROLLBACK")
                try checkLocation()
                return .conflict
            }
            // The write lock covers the complete comparison and both writes.
            // Retained revision rows prevent reuse of ANY committed revision.
            let revision = UUID()
            mutationAttempted = true
            try statement("INSERT INTO revisions(revision) VALUES(?)") { statement in
                try bind(revision.uuidString, to: statement, at: 1)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw MigrationSQLiteError.unavailable }
            }
            let sql = expected == nil
                ? "INSERT INTO records(revision,payload,transaction_id) VALUES(?,?,?)"
                : "UPDATE records SET revision=?,payload=? WHERE transaction_id=?"
            try statement(sql) { statement in
                try bind(revision.uuidString, to: statement, at: 1)
                let result = replacement.withUnsafeBytes {
                    sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), Self.transient)
                }
                guard result == SQLITE_OK else { throw MigrationSQLiteError.unavailable }
                try bind(transactionID.uuidString, to: statement, at: 3)
                guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(database) == 1 else {
                    throw MigrationSQLiteError.unavailable
                }
            }
            try checkLocation()
            try exec("COMMIT")
            guard let database, sqlite3_get_autocommit(database) != 0 else { throw MigrationSQLiteError.unavailable }
            try checkLocation()
            return .applied
        } catch {
            // After any attempted mutation, even a successful rollback does
            // not turn an uncertain commit into a claimed definite failure.
            closeAfterFailure()
            return mutationAttempted ? .outcomeUnknown : .unavailable
        }
    }

    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func exec(_ sql: String) throws {
        guard !poisoned, let database, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw MigrationSQLiteError.unavailable
        }
    }

    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        guard !poisoned, let database else { throw MigrationSQLiteError.unavailable }
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else {
            if let prepared { sqlite3_finalize(prepared) }
            throw MigrationSQLiteError.unavailable
        }
        defer { sqlite3_finalize(prepared) }
        return try body(prepared)
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        guard value.withCString({ sqlite3_bind_text(statement, index, $0, -1, Self.transient) }) == SQLITE_OK else {
            throw MigrationSQLiteError.unavailable
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32, maximum: Int = 2048) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT else { throw MigrationSQLiteError.unavailable }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count <= maximum, let pointer = sqlite3_column_text(statement, column),
              let value = String(bytes: UnsafeBufferPointer(start: pointer, count: count), encoding: .utf8) else {
            throw MigrationSQLiteError.unavailable
        }
        return value
    }

    private func scalar(_ sql: String) throws -> String {
        try statement(sql) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { throw MigrationSQLiteError.unavailable }
            let value: String
            switch sqlite3_column_type(statement, 0) {
            case SQLITE_INTEGER: value = String(sqlite3_column_int64(statement, 0))
            case SQLITE_TEXT: value = try text(statement, column: 0)
            default: throw MigrationSQLiteError.unavailable
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw MigrationSQLiteError.unavailable }
            return value
        }
    }

    private func validateSchema() throws {
        let expected = ["revisions": Self.revisionsSQL, "records": Self.recordsSQL]
        var observed: [String: String] = [:]
        try statement("SELECT type,name,sql FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*'") { statement in
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW, try text(statement, column: 0) == "table" else {
                    throw MigrationSQLiteError.unavailable
                }
                let name = try text(statement, column: 1)
                guard observed[name] == nil else { throw MigrationSQLiteError.unavailable }
                observed[name] = try text(statement, column: 2)
            }
        }
        guard observed == expected else { throw MigrationSQLiteError.unavailable }
        guard try scalar("PRAGMA application_id") == String(Self.applicationID),
              try scalar("PRAGMA user_version") == "1",
              try scalar("PRAGMA integrity_check(1)") == "ok",
              try scalar("SELECT count(*) FROM pragma_foreign_key_check") == "0" else {
            throw MigrationSQLiteError.unavailable
        }
    }

    private func load(_ id: UUID) throws -> MigrationImportVersion? {
        try statement("SELECT rowid,revision,length(payload),typeof(payload) FROM records WHERE transaction_id=?") { statement in
            try bind(id.uuidString, to: statement, at: 1)
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return nil }
            guard status == SQLITE_ROW,
                  sqlite3_column_type(statement, 0) == SQLITE_INTEGER,
                  sqlite3_column_type(statement, 2) == SQLITE_INTEGER,
                  try text(statement, column: 3) == "blob" else { throw MigrationSQLiteError.unavailable }
            let rowID = sqlite3_column_int64(statement, 0)
            let revisionText = try text(statement, column: 1, maximum: 36)
            guard let revision = UUID(uuidString: revisionText), revision.uuidString == revisionText else {
                throw MigrationSQLiteError.unavailable
            }
            let count = sqlite3_column_int64(statement, 2)
            guard count > 0, count <= Int64(Self.limit), let database else { throw MigrationSQLiteError.unavailable }
            // Incremental BLOB I/O checks the length before allocating Data.
            var blob: OpaquePointer?
            guard sqlite3_blob_open(database, "main", "records", "payload", rowID, 0, &blob) == SQLITE_OK,
                  let blob else { throw MigrationSQLiteError.unavailable }
            defer { sqlite3_blob_close(blob) }
            guard Int64(sqlite3_blob_bytes(blob)) == count else { throw MigrationSQLiteError.unavailable }
            var bytes = Data(count: Int(count))
            let result = bytes.withUnsafeMutableBytes { sqlite3_blob_read(blob, $0.baseAddress, Int32(count), 0) }
            guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
                throw MigrationSQLiteError.unavailable
            }
            return MigrationImportVersion(revision: revision, bytes: bytes)
        }
    }

    private func checkLocation() throws {
        guard !poisoned, let database else { throw MigrationSQLiteError.unavailable }
        try boundary.validate()
        var moved: Int32 = 1
        guard sqlite3_file_control(database, "main", SQLITE_FCNTL_HAS_MOVED, &moved) == SQLITE_OK,
              moved == 0 else { throw MigrationSQLiteError.unsafeStorage }
    }

    private func closeAfterFailure() {
        if let database {
            if sqlite3_get_autocommit(database) == 0 { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
            // Every statement/blob is finalized synchronously by its scope.
            // Do not use close_v2's deferred zombie-connection behavior.
            if sqlite3_close(database) == SQLITE_OK { self.database = nil }
        }
        poisoned = true
    }

    /// Small adapter-local path boundary, not a general filesystem framework.
    private final class Boundary {
        struct Identity: Equatable { let device: Int32; let inode: UInt64 }
        let directory: URL
        let descriptor: Int32
        let ancestors: [Identity]
        let databaseIdentity: Identity
        var databaseURL: URL { directory.appendingPathComponent(MigrationSQLitePersistence.databaseName) }

        init(directory: URL, create: Bool) throws {
            guard getuid() != 0, getuid() == geteuid(), getgid() == getegid(),
                  let account = getpwuid(getuid()), let home = account.pointee.pw_dir else {
                throw MigrationSQLiteError.unsafeStorage
            }
            // A new sibling of the production session directory, never a
            // production App Group, preferences root or source-app directory.
            let expected = URL(fileURLWithPath: String(cString: home), isDirectory: true)
                .appendingPathComponent("Library/Application Support/Ping Warden Migration Staging", isDirectory: true)
            guard directory.isFileURL, directory.path == expected.path,
                  directory.standardizedFileURL.path == directory.path else { throw MigrationSQLiteError.unsafeStorage }
            self.directory = directory
            if create {
                let parent = try Self.openDirectory(directory.deletingLastPathComponent())
                defer { Darwin.close(parent.0) }
                guard mkdirat(parent.0, directory.lastPathComponent, 0o700) == 0 else { throw MigrationSQLiteError.unsafeStorage }
                let created = openat(parent.0, directory.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard created >= 0 else { throw MigrationSQLiteError.unsafeStorage }
                defer { Darwin.close(created) }
                try Self.privatizeNew(created, mode: 0o700)
                let file = openat(created, MigrationSQLitePersistence.databaseName, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard file >= 0 else { throw MigrationSQLiteError.unsafeStorage }
                do {
                    try Self.privatizeNew(file, mode: 0o600)
                    guard fsync(file) == 0, fsync(created) == 0, fsync(parent.0) == 0 else {
                        throw MigrationSQLiteError.unavailable
                    }
                    Darwin.close(file)
                } catch { Darwin.close(file); throw error }
            }
            let opened = try Self.openDirectory(directory)
            let identity: Identity
            do {
                var filesystem = statfs()
                guard fstatfs(opened.0, &filesystem) == 0, filesystem.f_flags & UInt32(MNT_LOCAL) != 0 else {
                    throw MigrationSQLiteError.unsafeStorage
                }
                try Self.requirePrivateDirectory(opened.0)
                identity = try Self.fileIdentity(at: opened.0, name: MigrationSQLitePersistence.databaseName,
                    url: expected.appendingPathComponent(MigrationSQLitePersistence.databaseName))
            } catch { Darwin.close(opened.0); throw error }
            descriptor = opened.0
            ancestors = opened.1
            databaseIdentity = identity
        }

        deinit { Darwin.close(descriptor) }

        func validate() throws {
            let current = try Self.openDirectory(directory)
            defer { Darwin.close(current.0) }
            guard current.1 == ancestors else { throw MigrationSQLiteError.unsafeStorage }
            try Self.requirePrivateDirectory(current.0)
            guard try Self.fileIdentity(at: current.0, name: MigrationSQLitePersistence.databaseName, url: databaseURL) == databaseIdentity else {
                throw MigrationSQLiteError.unsafeStorage
            }
            // Journals may be created/removed by normal SQLite recovery. Never
            // open and close an extra DB file descriptor during SQLite locking.
            let journal = MigrationSQLitePersistence.databaseName + "-journal"
            var info = stat()
            if fstatat(current.0, journal, &info, AT_SYMLINK_NOFOLLOW) == 0 {
                _ = try Self.fileIdentity(at: current.0, name: journal, url: directory.appendingPathComponent(journal))
            } else if errno != ENOENT { throw MigrationSQLiteError.unsafeStorage }
            for suffix in ["-wal", "-shm"] {
                guard fstatat(current.0, MigrationSQLitePersistence.databaseName + suffix, &info, AT_SYMLINK_NOFOLLOW) != 0,
                      errno == ENOENT else { throw MigrationSQLiteError.unsafeStorage }
            }
        }

        private static func openDirectory(_ url: URL) throws -> (Int32, [Identity]) {
            guard url.isFileURL, url.path.hasPrefix("/"), url.standardizedFileURL.path == url.path else {
                throw MigrationSQLiteError.unsafeStorage
            }
            var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw MigrationSQLiteError.unsafeStorage }
            var chain: [Identity] = []
            do {
                for component in url.pathComponents.dropFirst() {
                    let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard next >= 0 else { throw MigrationSQLiteError.unsafeStorage }
                    Darwin.close(fd)
                    fd = next
                    var info = stat()
                    guard fstat(fd, &info) == 0 else { throw MigrationSQLiteError.unsafeStorage }
                    chain.append(Identity(device: info.st_dev, inode: info.st_ino))
                }
                return (fd, chain)
            } catch { Darwin.close(fd); throw error }
        }

        private static func emptyACL(_ acl: acl_t) throws {
            guard let empty = acl_init(0) else { throw MigrationSQLiteError.unsafeStorage }
            defer { acl_free(UnsafeMutableRawPointer(empty)) }
            guard acl_size(empty) > 0, acl_size(acl) == acl_size(empty) else { throw MigrationSQLiteError.unsafeStorage }
        }

        private static func requirePrivateDirectory(_ fd: Int32) throws {
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700,
                  let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else { throw MigrationSQLiteError.unsafeStorage }
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            try emptyACL(acl)
        }

        private static func fileIdentity(at fd: Int32, name: String, url: URL) throws -> Identity {
            var info = stat()
            guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_uid == getuid(),
                  info.st_mode & 0o7777 == 0o600, info.st_nlink == 1,
                  let acl = acl_get_link_np(url.path, ACL_TYPE_EXTENDED) else { throw MigrationSQLiteError.unsafeStorage }
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            try emptyACL(acl)
            var after = stat()
            guard fstatat(fd, name, &after, AT_SYMLINK_NOFOLLOW) == 0,
                  after.st_dev == info.st_dev, after.st_ino == info.st_ino,
                  after.st_mode == info.st_mode, after.st_uid == info.st_uid, after.st_nlink == 1 else {
                throw MigrationSQLiteError.unsafeStorage
            }
            return Identity(device: info.st_dev, inode: info.st_ino)
        }

        private static func privatizeNew(_ fd: Int32, mode: mode_t) throws {
            guard let empty = acl_init(0) else { throw MigrationSQLiteError.unsafeStorage }
            defer { acl_free(UnsafeMutableRawPointer(empty)) }
            guard acl_set_fd_np(fd, empty, ACL_TYPE_EXTENDED) == 0, fchmod(fd, mode) == 0 else {
                throw MigrationSQLiteError.unsafeStorage
            }
        }
    }
}
#endif
