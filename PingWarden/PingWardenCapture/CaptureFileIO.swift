import CryptoKit
import Darwin
import Foundation

struct CaptureFileToken: Codable, Equatable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ value: stat) {
        device = value.st_dev
        inode = value.st_ino
        size = value.st_size
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = Int64(value.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
    }
}

struct CapturedFile: Equatable {
    let bytes: Data?
    let token: CaptureFileToken?
    let location: CaptureLocation

    var migrationRead: MigrationRead<Data> {
        bytes.map { .available($0) } ?? .absent
    }

    var digest: String? { bytes.map(CaptureFileIO.digest) }
}

struct CaptureDirectoryIdentity: Equatable, Hashable {
    let device: Int32
    let inode: UInt64

    init(_ info: stat) {
        device = info.st_dev
        inode = info.st_ino
    }
}

struct CaptureLocation: Equatable {
    let directories: [CaptureDirectoryIdentity]
    let file: CaptureFileToken?
    let missingComponent: Int?
}

struct CaptureStorePath {
    let label: String
    let root: URL
    let components: [String]

    var url: URL { components.reduce(root) { $0.appendingPathComponent($1) } }
}

enum CaptureFileIO {
    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Every directory component is opened without following symlinks.
    static func directory(_ url: URL, label: String) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/"),
              url.standardizedFileURL.path == url.path else { throw CaptureFailure.invalidArguments }
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CaptureFailure.unavailable(label, errno) }
        do {
            for component in url.pathComponents.dropFirst() {
                let next = component.withCString {
                    openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw CaptureFailure.unavailable(label, errno) }
                Darwin.close(descriptor)
                descriptor = next
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    /// The caller owns the returned descriptor, including absence observations.
    private static func locate(_ path: CaptureStorePath) throws -> (parent: Int32, location: CaptureLocation) {
        var parent = try directory(path.root, label: path.label)
        do {
            var rootInfo = stat()
            guard fstat(parent, &rootInfo) == 0, rootInfo.st_uid == getuid() else {
                throw CaptureFailure.unavailable(path.label, EACCES)
            }
            var directories = [CaptureDirectoryIdentity(rootInfo)]
            for (index, component) in path.components.dropLast().enumerated() {
                let next = component.withCString {
                    openat(parent, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                if next < 0 {
                    let code = errno
                    if code == ENOENT {
                        return (parent, CaptureLocation(directories: directories, file: nil, missingComponent: index))
                    }
                    throw CaptureFailure.unavailable(path.label, code)
                }
                Darwin.close(parent)
                parent = next
                var info = stat()
                guard fstat(parent, &info) == 0 else { throw CaptureFailure.unavailable(path.label, errno) }
                directories.append(CaptureDirectoryIdentity(info))
            }
            guard let name = path.components.last else { throw CaptureFailure.invalidArguments }
            var info = stat()
            if name.withCString({ fstatat(parent, $0, &info, AT_SYMLINK_NOFOLLOW) }) != 0 {
                let code = errno
                if code == ENOENT {
                    return (parent, CaptureLocation(directories: directories, file: nil, missingComponent: path.components.count - 1))
                }
                throw CaptureFailure.unavailable(path.label, code)
            }
            guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_uid == getuid() else {
                throw CaptureFailure.unsupportedStore(path.label)
            }
            return (parent, CaptureLocation(directories: directories, file: CaptureFileToken(info), missingComponent: nil))
        } catch {
            Darwin.close(parent)
            throw error
        }
    }

    static func read(_ path: CaptureStorePath) throws -> CapturedFile {
        let limit = MigrationSnapshotBuilder.maximumPayloadBytes
        let initial = try locate(path)
        defer { Darwin.close(initial.parent) }
        func confirmPath() throws {
            let current = try locate(path)
            defer { Darwin.close(current.parent) }
            guard current.location == initial.location else { throw CaptureFailure.sourceChanged }
        }
        guard let token = initial.location.file else {
            try confirmPath()
            return CapturedFile(bytes: nil, token: nil, location: initial.location)
        }
        guard let name = path.components.last else { throw CaptureFailure.invalidArguments }
        let descriptor = name.withCString { openat(initial.parent, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        guard descriptor >= 0 else { throw CaptureFailure.unavailable(path.label, errno) }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw CaptureFailure.unavailable(path.label, errno) }
        guard before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), before.st_uid == getuid() else {
            throw CaptureFailure.unsupportedStore(path.label)
        }
        guard token == CaptureFileToken(before) else { throw CaptureFailure.sourceChanged }
        guard before.st_size >= 0, before.st_size <= Int64(limit) else { throw CaptureFailure.sizeLimit(path.label) }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw CaptureFailure.unavailable(path.label, errno)
            }
            if count == 0 { break }
            guard bytes.count + count <= limit else { throw CaptureFailure.sizeLimit(path.label) }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0 else {
            throw CaptureFailure.sourceChanged
        }
        guard token == CaptureFileToken(after),
              Int64(bytes.count) == before.st_size else { throw CaptureFailure.sourceChanged }
        try confirmPath()
        return CapturedFile(bytes: bytes, token: token, location: initial.location)
    }

    private static func identity(_ descriptor: Int32) throws -> CaptureDirectoryIdentity {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw CaptureFailure.unavailable("output", errno) }
        return CaptureDirectoryIdentity(info)
    }

    private static func requireOutside(_ descriptor: Int32, roots: [URL]) throws {
        var excluded: Set<CaptureDirectoryIdentity> = []
        for root in roots {
            let source = try directory(root, label: "outputBoundary")
            defer { Darwin.close(source) }
            excluded.insert(try identity(source))
        }
        var ancestor = dup(descriptor)
        guard ancestor >= 0 else { throw CaptureFailure.unavailable("output", errno) }
        defer { Darwin.close(ancestor) }
        // Filesystem identities also cover case aliases on insensitive volumes.
        for _ in 0..<1024 {
            let current = try identity(ancestor)
            guard !excluded.contains(current) else { throw CaptureFailure.invalidArguments }
            let next = openat(ancestor, "..", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw CaptureFailure.unavailable("output", errno) }
            let parentIdentity: CaptureDirectoryIdentity
            do { parentIdentity = try identity(next) }
            catch { Darwin.close(next); throw error }
            Darwin.close(ancestor)
            ancestor = next
            if parentIdentity == current { return }
        }
        throw CaptureFailure.invalidArguments
    }

    /// Clear inherited ACLs only on this invocation's new output objects.
    private static func ownerOnly(_ descriptor: Int32, mode: mode_t) throws {
        guard let empty = acl_init(0) else { throw CaptureFailure.unavailable("output", errno) }
        defer { acl_free(UnsafeMutableRawPointer(empty)) }
        guard acl_set_fd_np(descriptor, empty, ACL_TYPE_EXTENDED) == 0,
              fchmod(descriptor, mode) == 0,
              let actual = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            throw CaptureFailure.unavailable("output", errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(actual)) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
              info.st_mode & 0o777 == mode,
              acl_size(empty) > 0, acl_size(actual) == acl_size(empty) else {
            throw CaptureFailure.unavailable("output", EACCES)
        }
    }

    /// Creates only a new owner-only output directory and two new files.
    /// Failure leaves partial output for deliberate review, never unlinks paths.
    static func write(snapshot: Data, report: Data, to output: URL, excluding roots: [URL]) throws {
        let parent = try directory(output.deletingLastPathComponent(), label: "output")
        defer { Darwin.close(parent) }
        try requireOutside(parent, roots: roots)
        let name = output.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/" else {
            throw CaptureFailure.invalidArguments
        }
        let created = name.withCString { mkdirat(parent, $0, 0o700) }
        guard created == 0 else { throw CaptureFailure.unavailable("output", errno) }
        let folder = name.withCString { openat(parent, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard folder >= 0 else { throw CaptureFailure.unavailable("output", errno) }
        defer { Darwin.close(folder) }
        try requireOutside(folder, roots: roots)
        try ownerOnly(folder, mode: 0o700)
        for (filename, data) in [("Snapshot.json", snapshot), ("Capture Report.json", report)] {
            let file = filename.withCString { openat(folder, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
            guard file >= 0 else { throw CaptureFailure.unavailable("output", errno) }
            do {
                try ownerOnly(file, mode: 0o600)
                try data.withUnsafeBytes { raw in
                    var offset = 0
                    while offset < raw.count {
                        let written = Darwin.write(file, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                        if written < 0 && errno == EINTR { continue }
                        guard written > 0 else { throw CaptureFailure.unavailable("output", errno) }
                        offset += written
                    }
                }
                guard fsync(file) == 0 else { throw CaptureFailure.unavailable("output", errno) }
                Darwin.close(file)
            } catch {
                Darwin.close(file)
                throw error
            }
        }
        guard fsync(folder) == 0 else { throw CaptureFailure.unavailable("output", errno) }
    }
}
