import Foundation
import Darwin
import Security

enum CaptureIdentity {
    static let team = "PV3W52NDZ3"
    static let sourceIdentifier = "com.amesvt.pingwarden"
    static let captureIdentifier = "com.amesvt.pingwarden.capture"
    static let group = "PV3W52NDZ3.com.amesvt.pingwarden"

    struct Observation: Codable, Equatable {
        let identifier: String
        let team: String
        let marketingVersion: String?
        let buildVersion: String?
        let codeDirectoryHash: String

        var source: MigrationSource? {
            guard let marketingVersion, let buildVersion else { return nil }
            return MigrationSource(bundleIdentifier: identifier, signingTeamIdentifier: team,
                appGroupIdentifier: CaptureIdentity.group,
                marketingVersion: marketingVersion, buildVersion: buildVersion)
        }
    }

    static func inspect(_ url: URL, identifier: String) throws -> Observation {
        guard url.pathExtension == "app" else { throw CaptureFailure.invalidSourceApplication }
        let directory = try CaptureFileIO.directory(url, label: "application")
        Darwin.close(directory)
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &code)
        guard created == errSecSuccess, let code else { throw CaptureFailure.signature(created) }
        // Developer ID Application, the expected identifier, and the former team.
        let requirementText = "anchor apple generic and identifier \"\(identifier)\" "
            + "and certificate leaf[subject.OU] = \"\(team)\" "
            + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var requirement: SecRequirement?
        let parsed = SecRequirementCreateWithString(requirementText as CFString,
            SecCSFlags(rawValue: 0), &requirement)
        guard parsed == errSecSuccess, let requirement else { throw CaptureFailure.signature(parsed) }
        if identifier == captureIdentifier {
            // Validate the actual running caller as well as its on-disk wrapper.
            var caller: SecCode?
            let obtained = SecCodeCopySelf(SecCSFlags(rawValue: 0), &caller)
            guard obtained == errSecSuccess, let caller else { throw CaptureFailure.signature(obtained) }
            let running = SecCodeCheckValidity(caller, SecCSFlags(rawValue: 0), requirement)
            guard running == errSecSuccess else { throw CaptureFailure.signature(running) }
        }
        // Deliberately omit kSecCSAllowNetworkAccess.
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let valid = SecStaticCodeCheckValidity(code, flags, requirement)
        guard valid == errSecSuccess else { throw CaptureFailure.signature(valid) }
        var information: CFDictionary?
        let copied = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard copied == errSecSuccess, let info = information as? [String: Any],
              info[kSecCodeInfoIdentifier as String] as? String == identifier,
              info[kSecCodeInfoTeamIdentifier as String] as? String == team,
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              entitlements["com.apple.security.application-groups"] as? [String] == [group],
              entitlements["com.apple.security.app-sandbox"] as? Bool != true,
              let plist = info[kSecCodeInfoPList as String] as? [String: Any],
              plist["CFBundleIdentifier"] as? String == identifier,
              let codeHash = info[kSecCodeInfoUnique as String] as? Data else {
            throw CaptureFailure.invalidSourceApplication
        }
        let marketing = plist["CFBundleShortVersionString"] as? String
        let build = plist["CFBundleVersion"] as? String
        if identifier == sourceIdentifier {
            guard let marketing, let build,
                  marketing.utf8.count <= 128, build.utf8.count <= 128,
                  let majorText = marketing.split(separator: ".").first,
                  let major = Int(majorText), major >= 4,
                  build.range(of: #"^[0-9]+(?:\.[0-9]+){0,2}$"#, options: .regularExpression) != nil else {
                throw CaptureFailure.invalidSourceApplication
            }
        }
        return Observation(identifier: identifier, team: team, marketingVersion: marketing,
            buildVersion: build, codeDirectoryHash: codeHash.map { String(format: "%02x", $0) }.joined())
    }
}
