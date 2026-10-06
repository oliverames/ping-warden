import Foundation

@MainActor
final class LicenseTestSuite {
    private(set) var failures = 0
    private(set) var cases = 0

    private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: " + message) }
    }

    private func run(_ name: String, _ body: @MainActor () async -> Void) async {
        cases += 1
        let before = failures
        await body()
        print((failures == before ? "PASS: " : "FAILED: ") + name)
    }

    func runAll() async {
        await run("injected construction has no storage or credential effects") {
            let f = LicenseFixture(["CrashReportingEnabled": false])
            check(f.store.writes.isEmpty && f.credentials.events.isEmpty && f.verifier.calls == 0,
                  "Constructing the real manager must only retain dependencies")
            check(!f.manager.canEnableProtection && f.store.writes.isEmpty,
                  "An entitlement read must not write defaults")
        }

        await run("known blocker: paid offline 4.0.0 cache is rejected without a seal") {
            let f = LicenseFixture([
                "LicenseCachedValid": true,
                "LicenseLastVerifiedAt": 1_799_999_400.0,
                "LicenseGrandfatherChecked": true,
                "AWDLMonitoringEnabled": true,
                "CrashReportingEnabled": false,
            ])
            f.credentials.items["gumroad-key"] = Data("FIXTURE-LICENSE".utf8)
            let oldAllowed = Legacy400LicensePolicy.canEnableProtection(
                cachedLicenseValid: f.store.bool(forKey: "LicenseCachedValid"),
                lastVerifiedAt: Date(timeIntervalSince1970: f.store.double(forKey: "LicenseLastVerifiedAt")),
                now: f.clock.now, grandfatherDeadline: nil
            )
            check(oldAllowed, "The actual tagged 4.0.0 policy must admit this offline fixture")
            check(!f.manager.canEnableProtection, "Current manager must characterize the missing-seal rejection")
            f.manager.establishGrandfatheringIfNeeded(helperEnabled: true)
            f.manager.recordClockObservation()
            await f.manager.reverify()
            check(!f.manager.canEnableProtection && f.manager.lastVerificationResult == .unreachable,
                  "Offline verification does not repair an unsealed paid cache")
            check(f.store.object(forKey: "LicenseStateSeal") == nil && f.store.object(forKey: "LicenseGrandfatherDeadline") == nil,
                  "The manager must not create paid proof or a replacement transition deadline")
            check(f.store.bool(forKey: "LicenseCachedValid") && f.store.double(forKey: "LicenseLastVerifiedAt") == 1_799_999_400,
                  "The original paid-cache values remain present despite the denied gate")
            check(f.store.bool(forKey: "AWDLMonitoringEnabled") && !f.store.bool(forKey: "CrashReportingEnabled"),
                  "Licensing alone does not clear protection intent or change privacy")
            check(f.store.object(forKey: "LicenseGrandfatherChecked") == nil,
                  "Characterize current launch migration removing the legacy decision flag")
            check(f.credentials.items["grandfather-checked"] != nil && f.credentials.items["legacy-transition-migrated"] != nil,
                  "Characterize current one-shot marker writes")
            // AppDelegate's subsequent intent clearing is outside this harness.
        }

        await run("sealed 4.x remains paid offline without timestamp renewal") {
            let f = LicenseFixture(["AWDLMonitoringEnabled": true, "CrashReportingEnabled": false])
            f.installSyntheticKeyAndMarkers()
            f.seedSealed()
            let before = f.store.values
            check(f.manager.canEnableProtection && f.manager.hasValidPaidLicense, "Valid sealed cache must be paid")
            f.manager.establishGrandfatheringIfNeeded(helperEnabled: true)
            f.manager.recordClockObservation()
            await f.manager.reverify()
            check(f.manager.canEnableProtection && f.manager.hasValidPaidLicense, "Offline failure must preserve sealed access")
            check(NSDictionary(dictionary: before).isEqual(to: f.store.values), "Offline startup must not renew this recent cache")
            check(f.store.writes.isEmpty, "Recent last-seen state must avoid a write")
            check(f.credentials.events.allSatisfy { $0.hasPrefix("read:") }, "Offline verification must not change credentials")
        }

        await run("seal rejects another device and altered payload") {
            let f = LicenseFixture()
            f.seedSealed()
            check(f.manager.canEnableProtection, "Initial fixture seal must match")
            f.seal.device = "SYNTHETIC-DEVICE-B"
            check(!f.manager.canEnableProtection, "Copied state must fail the device-bound seal")
            f.seal.device = "SYNTHETIC-DEVICE-A"
            f.store.values["LicenseLastVerifiedAt"] = 1_799_999_999.0
            check(!f.manager.canEnableProtection, "Altered payload must fail the original seal")
            check(f.store.writes.isEmpty, "Read rejection must not repair or rewrite a seal")
        }

        await run("offline grace and clock boundaries keep current policy") {
            let grace = LicensePolicy.offlineGraceInterval
            for (age, expected) in [(grace, true), (grace + 1, false)] {
                let f = LicenseFixture()
                f.seedSealed(verified: f.clock.now.timeIntervalSince1970 - age)
                check(f.manager.canEnableProtection == expected, "Fourteen-day grace boundary changed")
            }
            let futureVerified = LicenseFixture()
            futureVerified.seedSealed(verified: futureVerified.clock.now.timeIntervalSince1970 + 3601)
            check(!futureVerified.manager.canEnableProtection, "Future verification beyond one hour must fail")
            let futureSeen = LicenseFixture()
            futureSeen.seedSealed(seen: futureSeen.clock.now.timeIntervalSince1970 + 86401)
            check(!futureSeen.manager.canEnableProtection, "Future observation beyond one day must fail")
        }

        await run("legacy transition keeps its original deadline, including expiry") {
            for remaining in [86400.0, -1.0] {
                let deadline = 1_800_000_000.0 + remaining
                let f = LicenseFixture([
                    "LicenseGrandfatherChecked": true,
                    "LicenseGrandfatherDeadline": deadline,
                    "AWDLMonitoringEnabled": true,
                ])
                f.manager.establishGrandfatheringIfNeeded(helperEnabled: true)
                check(f.store.double(forKey: "LicenseGrandfatherDeadline") == deadline, "Migration must preserve the original deadline")
                check(f.manager.canEnableProtection == (remaining > 0), "An expired legacy transition must stay expired")
                check(!f.manager.hasValidPaidLicense, "A transition deadline must never become a paid license")
                check(f.manager.grandfatherWindowExpired == (remaining < 0), "Expired-transition classification changed")
            }
            let badSeal = LicenseFixture([
                "LicenseGrandfatherChecked": true,
                "LicenseGrandfatherDeadline": 1_800_086_400.0,
                "LicenseStateSeal": "invalid-fixture-seal",
                "AWDLMonitoringEnabled": true,
            ])
            badSeal.manager.establishGrandfatheringIfNeeded(helperEnabled: true)
            check(badSeal.store.string(forKey: "LicenseStateSeal") == "invalid-fixture-seal", "Existing invalid seal must not be repaired as absent")
            check(!badSeal.manager.canEnableProtection, "Invalid sealed state must remain denied")
        }

        await run("authoritative verification seals state at injected whole-second time") {
            let f = LicenseFixture(["CrashReportingEnabled": false])
            f.clock.now = Date(timeIntervalSince1970: 1_800_000_000.75)
            f.verifier.result = .success(Data(#"{"success":true,"purchase":{}}"#.utf8))
            var callbacks = 0
            f.manager.onReverificationSettled = { callbacks += 1 }
            let result = await f.manager.verify(key: " fixture-license\n")
            check(result && f.manager.canEnableProtection && f.manager.hasValidPaidLicense, "Verified fixture must become paid")
            check(f.verifier.calls == 1 && f.verifier.receivedNormalizedKey && callbacks == 1, "Verify must normalize once and settle once")
            check(f.store.double(forKey: "LicenseLastVerifiedAt") == 1_800_000_000 && f.store.double(forKey: "LicenseLastSeenAt") == 1_800_000_000,
                  "Stored seal timestamps must retain whole-second normalization")
            check(f.credentials.events == ["update:gumroad-key", "add:gumroad-key"], "A missing key must follow the existing update/add sequence")
            check(!f.store.bool(forKey: "CrashReportingEnabled"), "Verification must preserve privacy choice")
        }

        await run("revocation keeps the credential while malformed responses preserve cache") {
            let revoked = LicenseFixture()
            revoked.installSyntheticKeyAndMarkers()
            revoked.seedSealed()
            revoked.verifier.result = .success(Data(#"{"success":false}"#.utf8))
            await revoked.manager.reverify()
            check(!revoked.manager.canEnableProtection && revoked.manager.lastVerificationResult == .revoked, "Authoritative denial must revoke")
            check(revoked.credentials.items["gumroad-key"] != nil, "Revocation must keep the stored credential")
            check(revoked.store.double(forKey: "LicenseLastVerifiedAt") == 1_799_999_400, "Revocation must keep the last verification timestamp")
            let malformed = LicenseFixture()
            malformed.installSyntheticKeyAndMarkers()
            malformed.seedSealed()
            malformed.verifier.result = .success(Data("not-json".utf8))
            let before = malformed.store.values
            await malformed.manager.reverify()
            check(malformed.manager.canEnableProtection && malformed.manager.lastVerificationResult == .unreachable,
                  "Unparsable response must preserve paid offline cache")
            check(NSDictionary(dictionary: before).isEqual(to: malformed.store.values), "Malformed response must not modify state")
        }

        await run("known behavior: credential failures collapse to missing at manager boundary") {
            let reads: [LicenseCredentialRead] = [
                .notFound, .blocked(.interactionNotAllowed), .blocked(.userCanceled),
                .blocked(.authenticationFailed), .blocked(.unavailable(-9999)),
                .blocked(.malformedValue), .found(Data([0xff])),
            ]
            for read in reads {
                let f = LicenseFixture()
                f.credentials.readOverrides["gumroad-key"] = read
                check(f.manager.storedLicenseKey == nil, "The seam-only refactor must preserve current nil mapping")
                await f.manager.reverify()
                check(f.manager.lastVerificationResult == .invalidKey && f.verifier.calls == 0,
                      "Characterize denied reads becoming invalidKey without verification")
                check(f.store.writes.isEmpty, "A failed credential read must not mutate cached state")
            }
        }

        await run("known blocker: marker failure can still create a transition grant") {
            let f = LicenseFixture(["AWDLMonitoringEnabled": true])
            f.credentials.readOverrides["grandfather-checked"] = .blocked(.interactionNotAllowed)
            f.credentials.readOverrides["legacy-transition-migrated"] = .blocked(.interactionNotAllowed)
            f.credentials.updateStatus = errSecAuthFailed
            f.credentials.addStatus = errSecAuthFailed
            f.manager.establishGrandfatheringIfNeeded(helperEnabled: true)
            check(f.manager.isGrandfathered, "Characterize current failure-to-false granting behavior before fixing it")
            check(f.store.double(forKey: "LicenseGrandfatherDeadline") == 1_800_000_000 + LicensePolicy.grandfatherInterval,
                  "Characterize existing ninety-day grant despite failed marker storage")
            check(f.credentials.events.contains("add:grandfather-checked"), "Current update error must still attempt add")
            check(f.credentials.items.isEmpty, "Failed fixture writes must not claim stored markers")
        }

        await run("known behavior: failed credential storage does not change verified result") {
            let f = LicenseFixture()
            f.credentials.updateStatus = errSecAuthFailed
            f.credentials.addStatus = errSecAuthFailed
            f.verifier.result = .success(Data(#"{"success":true}"#.utf8))
            let accepted = await f.manager.verify(key: "FIXTURE-LICENSE")
            check(accepted && f.manager.hasValidPaidLicense, "Characterize current server-valid result despite storage failure")
            check(f.credentials.events == ["update:gumroad-key", "add:gumroad-key"] && f.credentials.items.isEmpty,
                  "Both failed operations must remain visible without fixture persistence")
        }

        await run("in-flight duplicate is bounded and removal rejects the late reply") {
            let f = LicenseFixture(["AWDLMonitoringEnabled": true, "CrashReportingEnabled": false])
            f.installSyntheticKeyAndMarkers()
            f.seedSealed()
            f.verifier.holdReply = true
            f.verifier.result = .success(Data(#"{"success":true}"#.utf8))
            var callbacks = 0
            f.manager.onReverificationSettled = { callbacks += 1 }
            let first = Task { @MainActor in await f.manager.verify(key: "FIXTURE-LICENSE") }
            await f.verifier.waitForCall()
            let duplicate = await f.manager.verify(key: "FIXTURE-LICENSE")
            check(!duplicate && f.verifier.calls == 1 && f.manager.isVerifying, "Duplicate must not create a second request")
            // The duplicate currently settles its public callback. Capture that
            // baseline so only a forbidden callback after removal would fail.
            let beforeRemoval = callbacks
            f.manager.resetForRemoval()
            f.verifier.finish()
            let firstResult = await first.value
            check(!firstResult && !f.manager.isVerifying && callbacks == beforeRemoval, "A late reply after removal must not settle or revive state")
            check(f.credentials.items.isEmpty && f.store.object(forKey: "LicenseStateSeal") == nil,
                  "Late verification must not recreate removed credentials or license state")
            check(f.credentials.events.filter { $0.hasPrefix("delete:") }.count == 3,
                  "Removal must delete exactly the three licensing accounts")
            check(f.store.bool(forKey: "AWDLMonitoringEnabled") && !f.store.bool(forKey: "CrashReportingEnabled"),
                  "License reset must leave unrelated fixture preferences alone")
        }
    }
}

@main
struct LicenseHarnessMain {
    @MainActor
    static func main() async {
        let suite = LicenseTestSuite()
        await suite.runAll()
        print("License manager characterization: \(suite.cases) cases, \(suite.failures) failures")
        if suite.cases != 12 { print("FAIL: Expected all twelve characterization cases") }
        if suite.cases != 12 || suite.failures != 0 { exit(1) }
    }
}
