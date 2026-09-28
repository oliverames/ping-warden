import Foundation
import XCTest
@testable import PingWardenCore

final class ProtectionExperiencePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testExpiredLicenseBlocksEveryReconciliationPhase() {
        for phase in ProtectionSessionPhase.allCases {
            var state = makeState(persistentProtectionEnabled: true, sessionPhase: phase)
            state.licenseAllowsProtection = false
            XCTAssertFalse(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))
            state.pauseUntil = now.addingTimeInterval(-1)
            XCTAssertFalse(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))
            state.persistentProtectionEnabled = false
            XCTAssertFalse(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))
        }
    }

    func testSessionStartingOrActiveRequiresTemporaryProtection() {
        var state = makeState(sessionPhase: .starting, sessionTrigger: .manual)
        XCTAssertTrue(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))

        state.sessionPhase = .active
        XCTAssertTrue(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))

        state.sessionPhase = .stopping
        XCTAssertTrue(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))

        state.sessionPhase = .idle
        state.sessionTrigger = nil
        XCTAssertFalse(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))
    }

    func testPersistentIntentKeepsProtectionOnAfterSessionEnds() {
        let state = makeState(
            persistentProtectionEnabled: true,
            sessionPhase: .idle
        )

        XCTAssertTrue(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))
    }

    func testCurrentPersistentIntentWinsInsteadOfAStaleSessionSnapshot() {
        var state = makeState(sessionPhase: .active, sessionTrigger: .manual)
        state.persistentProtectionEnabled = true
        state.sessionPhase = .idle
        state.sessionTrigger = nil

        XCTAssertTrue(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))

        state.persistentProtectionEnabled = false
        XCTAssertFalse(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))
    }

    func testActivePauseOverridesPersistentAndSessionReasons() {
        let pauseUntil = now.addingTimeInterval(600)
        let state = makeState(
            persistentProtectionEnabled: true,
            sessionPhase: .active,
            sessionTrigger: .manual,
            pauseUntil: pauseUntil
        )

        XCTAssertEqual(
            ProtectionExperiencePolicy.activePauseUntil(in: state, now: now),
            pauseUntil
        )
        XCTAssertTrue(ProtectionExperiencePolicy.isPaused(state, now: now))
        XCTAssertFalse(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))
    }

    func testExpiredPauseNoLongerOverridesProtectionReasons() {
        let state = makeState(
            persistentProtectionEnabled: true,
            pauseUntil: now.addingTimeInterval(-1)
        )

        XCTAssertNil(ProtectionExperiencePolicy.activePauseUntil(in: state, now: now))
        XCTAssertFalse(ProtectionExperiencePolicy.isPaused(state, now: now))
        XCTAssertTrue(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))
    }

    func testHelperUnavailableAlwaysPreventsProtection() {
        let state = makeState(
            helperAvailable: false,
            persistentProtectionEnabled: true,
            sessionPhase: .active,
            sessionTrigger: .manual
        )

        XCTAssertFalse(ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now))
    }

    func testOffMenuPresentation() {
        let presentation = ProtectionExperiencePolicy.presentation(
            for: makeState(),
            now: now
        )

        XCTAssertEqual(presentation.protectionTitle, "Turn On Ping Protection")
        XCTAssertNil(presentation.pauseTitle)
        XCTAssertEqual(presentation.statusTitle, "Status: Not Protected")
    }

    func testOnMenuPresentationUsesOnePauseAction() {
        let presentation = ProtectionExperiencePolicy.presentation(
            for: makeState(
                persistentProtectionEnabled: true,
                effectiveProtectionEnabled: true
            ),
            now: now
        )

        XCTAssertEqual(presentation.protectionTitle, "Turn Off Ping Protection")
        XCTAssertEqual(presentation.pauseTitle, "Pause for 10 Minutes")
        XCTAssertTrue(presentation.pauseActionEnabled)
        XCTAssertEqual(presentation.statusTitle, "Status: Protected")
    }

    func testPausedMenuPresentationReplacesPauseWithResume() {
        let presentation = ProtectionExperiencePolicy.presentation(
            for: makeState(
                persistentProtectionEnabled: true,
                pauseUntil: now.addingTimeInterval(600)
            ),
            now: now
        )

        XCTAssertEqual(presentation.protectionTitle, "Turn On Ping Protection")
        XCTAssertEqual(presentation.pauseTitle, "Resume Ping Protection")
        XCTAssertTrue(presentation.pauseActionEnabled)
        XCTAssertEqual(presentation.statusTitle, "Status: Paused")
    }

    func testActiveSessionStatusExplainsWhyProtectionIsActive() {
        let presentation = ProtectionExperiencePolicy.presentation(
            for: makeState(
                effectiveProtectionEnabled: true,
                sessionPhase: .active,
                sessionTrigger: .manual
            ),
            now: now
        )

        XCTAssertEqual(presentation.protectionTitle, "Turn Off Ping Protection")
        XCTAssertEqual(presentation.pauseTitle, "Pause for 10 Minutes")
        XCTAssertEqual(presentation.statusTitle, "Status: Protected, Latency Session Active")
    }

    func testGameModeSessionStatusNamesItsOwner() {
        let presentation = ProtectionExperiencePolicy.presentation(
            for: makeState(
                effectiveProtectionEnabled: true,
                sessionPhase: .active,
                sessionTrigger: .gameMode
            ),
            now: now
        )

        XCTAssertEqual(presentation.statusTitle, "Status: Protected, Game Mode Session Active")
    }

    func testStartingAndStoppingDescribeTheSessionTransition() {
        var state = makeState(sessionPhase: .starting, sessionTrigger: .manual)
        var presentation = ProtectionExperiencePolicy.presentation(for: state, now: now)
        XCTAssertEqual(presentation.statusTitle, "Status: Starting Latency Session")

        state.effectiveProtectionEnabled = true
        state.sessionPhase = .stopping
        presentation = ProtectionExperiencePolicy.presentation(for: state, now: now)
        XCTAssertEqual(presentation.statusTitle, "Status: Ending Latency Session")
    }

    func testNotSetUpMenuPresentationOffersSetup() {
        let presentation = ProtectionExperiencePolicy.presentation(
            for: makeState(helperAvailable: false),
            now: now
        )

        XCTAssertEqual(presentation.statusTitle, "Status: Not Set Up")
        XCTAssertEqual(presentation.protectionTitle, "Finish Setup...")
        XCTAssertTrue(presentation.protectionActionEnabled)
        XCTAssertNil(presentation.pauseTitle)
    }

    func testDesiredAndEffectiveMismatchHasHonestStatus() {
        var state = makeState(persistentProtectionEnabled: true)
        state.commandInFlight = true
        var presentation = ProtectionExperiencePolicy.presentation(for: state, now: now)
        XCTAssertEqual(presentation.statusTitle, "Status: Turning On Protection")

        state.persistentProtectionEnabled = false
        state.effectiveProtectionEnabled = true
        presentation = ProtectionExperiencePolicy.presentation(for: state, now: now)
        XCTAssertEqual(presentation.statusTitle, "Status: Turning Off Protection")
    }

    func testMismatchWithoutACommandDoesNotPromiseProgress() {
        var state = makeState(persistentProtectionEnabled: true)
        XCTAssertEqual(
            ProtectionExperiencePolicy.presentation(for: state, now: now).statusTitle,
            "Status: Not Protected"
        )
        state.helperResponding = false
        XCTAssertEqual(
            ProtectionExperiencePolicy.presentation(for: state, now: now).statusTitle,
            "Status: Not Protected, Helper Not Responding"
        )
        state.protectionRequested = true
        XCTAssertEqual(
            ProtectionExperiencePolicy.presentation(for: state, now: now).statusTitle,
            "Status: Reconnecting to Helper"
        )
    }

    func testSilentHelperWithSavedIntentOffersTurnOffAndDoesWhatItSays() {
        // The reviewed defect: the title said Turn Off while the click turned
        // protection on, and the status said Turning On indefinitely.
        var state = makeState(persistentProtectionEnabled: true)
        state.helperResponding = false
        let presentation = ProtectionExperiencePolicy.presentation(for: state, now: now)
        let action = ProtectionExperiencePolicy.toggleAction(for: state, now: now)
        XCTAssertEqual(action, .turnOff)
        XCTAssertEqual(presentation.protectionTitle, action.menuTitle)
        XCTAssertNotEqual(presentation.statusTitle, "Status: Turning On Protection")
    }

    func testToggleTitleAndActionAgreeInEveryState() {
        let bools = [false, true]
        let pauses: [Date?] = [nil, now.addingTimeInterval(600), now.addingTimeInterval(-1)]
        var combinations = 0
        for helperAvailable in bools {
            for persistent in bools {
                for effective in bools {
                    for requested in bools {
                        for inFlight in bools {
                            for responding in bools {
                                for licensed in bools {
                                    for pause in pauses {
                                        for phase in ProtectionSessionPhase.allCases {
                                            let state = ProtectionExperiencePolicy.State(
                                                helperAvailable: helperAvailable,
                                                persistentProtectionEnabled: persistent,
                                                effectiveProtectionEnabled: effective,
                                                sessionPhase: phase,
                                                sessionTrigger: phase == .idle ? nil : .manual,
                                                pauseUntil: pause,
                                                licenseAllowsProtection: licensed,
                                                protectionRequested: requested,
                                                commandInFlight: inFlight,
                                                helperResponding: responding
                                            )
                                            combinations += 1
                                            assertToggleInvariants(state)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(combinations, 2 * 2 * 2 * 2 * 2 * 2 * 2 * 3 * 4)
    }

    private func assertToggleInvariants(
        _ state: ProtectionExperiencePolicy.State,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let presentation = ProtectionExperiencePolicy.presentation(for: state, now: now)
        let action = ProtectionExperiencePolicy.toggleAction(for: state, now: now)
        XCTAssertEqual(presentation.protectionTitle, action.menuTitle, "\(state)", file: file, line: line)

        let wanted = ProtectionExperiencePolicy.shouldEnableProtection(for: state, now: now)
        let expected: ProtectionExperiencePolicy.ToggleAction
        if !state.helperAvailable {
            expected = .finishSetup
        } else if state.effectiveProtectionEnabled || state.protectionRequested || wanted {
            expected = .turnOff
        } else {
            expected = .turnOn
        }
        XCTAssertEqual(action, expected, "\(state)", file: file, line: line)

        // "Turning On" and "Turning Off" only ever describe a pending command.
        if !state.commandInFlight {
            XCTAssertNotEqual(presentation.statusTitle, "Status: Turning On Protection", "\(state)", file: file, line: line)
            XCTAssertNotEqual(presentation.statusTitle, "Status: Turning Off Protection", "\(state)", file: file, line: line)
        }
    }

    func testLaunchNeverEnablesForAnUnapprovedHelper() {
        XCTAssertEqual(
            ProtectionExperiencePolicy.launchIntentAction(
                persistentProtectionEnabled: true, licenseAllowsProtection: true, helperRegistered: false
            ),
            .waitForSetup
        )
        XCTAssertEqual(
            ProtectionExperiencePolicy.launchIntentAction(
                persistentProtectionEnabled: true, licenseAllowsProtection: false, helperRegistered: false
            ),
            .clearIntentForLicense
        )
        XCTAssertEqual(
            ProtectionExperiencePolicy.launchIntentAction(
                persistentProtectionEnabled: true, licenseAllowsProtection: false, helperRegistered: true
            ),
            .clearIntentForLicense
        )
        XCTAssertEqual(
            ProtectionExperiencePolicy.launchIntentAction(
                persistentProtectionEnabled: true, licenseAllowsProtection: true, helperRegistered: true
            ),
            .none
        )
        for licensed in [false, true] {
            for registered in [false, true] {
                XCTAssertEqual(
                    ProtectionExperiencePolicy.launchIntentAction(
                        persistentProtectionEnabled: false,
                        licenseAllowsProtection: licensed,
                        helperRegistered: registered
                    ),
                    .none
                )
            }
        }
    }

    private func makeState(
        helperAvailable: Bool = true,
        persistentProtectionEnabled: Bool = false,
        effectiveProtectionEnabled: Bool = false,
        sessionPhase: ProtectionSessionPhase = .idle,
        sessionTrigger: ProtectedSessionTrigger? = nil,
        pauseUntil: Date? = nil
    ) -> ProtectionExperiencePolicy.State {
        .init(
            helperAvailable: helperAvailable,
            persistentProtectionEnabled: persistentProtectionEnabled,
            effectiveProtectionEnabled: effectiveProtectionEnabled,
            sessionPhase: sessionPhase,
            sessionTrigger: sessionTrigger,
            pauseUntil: pauseUntil
        )
    }
}
