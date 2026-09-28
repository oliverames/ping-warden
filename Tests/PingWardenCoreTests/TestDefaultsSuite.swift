import Foundation

/// Names throwaway preference suites for tests. A plain suite name keeps
/// its plist in ~/Library/Preferences, and removing the domain afterward
/// still leaves an empty file there, so every test run added hundreds of
/// files. A suite named by an absolute path keeps its plist at that path,
/// which confines test preferences to a temporary folder.
enum TestDefaultsSuite {
    static func name(_ prefix: String) -> String {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PingWardenTestDefaults", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(prefix).\(UUID().uuidString)").path
    }
}
