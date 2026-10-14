import XCTest
@testable import PingWardenCore

final class HelperRepairOfferTests: XCTestCase {
    private typealias Offer = HelperRepairOffer
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func state(
        _ problem: Offer.Problem? = .notResponding,
        licensed: Bool = true,
        needed: Bool = true,
        busy: Bool = false
    ) -> Offer.State {
        Offer.State(problem: problem, licenseAllowsProtection: licensed, protectionNeeded: needed, busy: busy)
    }

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testAProblemIsOfferedOnlyAfterTheDebounce() {
        var tracker = Offer.Tracker()
        XCTAssertEqual(tracker.evaluate(state(), now: at(0)), .wait(Offer.debounce))
        XCTAssertEqual(tracker.evaluate(state(), now: at(4)), .wait(Offer.debounce - 4))
        XCTAssertEqual(tracker.evaluate(state(), now: at(Offer.debounce)), .offer(.notResponding))
    }

    func testTheDebounceIsLongEnoughForLaunchAndWakeBlips() {
        XCTAssertGreaterThanOrEqual(Offer.debounce, 5)
        XCTAssertLessThanOrEqual(Offer.debounce, 30)
    }

    func testABlipThatRecoversIsNeverOffered() {
        var tracker = Offer.Tracker()
        _ = tracker.evaluate(state(), now: at(0))
        XCTAssertEqual(tracker.evaluate(state(nil), now: at(2)), .none)
        XCTAssertNil(tracker.episode)
        // The next failure starts its own debounce.
        XCTAssertEqual(tracker.evaluate(state(), now: at(11)), .wait(Offer.debounce))
    }

    func testOncePerEpisode() {
        var tracker = Offer.Tracker()
        _ = tracker.evaluate(state(), now: at(0))
        XCTAssertEqual(tracker.evaluate(state(), now: at(10)), .offer(.notResponding))
        tracker.markOffered(problem: .notResponding, now: at(10))
        XCTAssertEqual(tracker.evaluate(state(), now: at(20)), .none)
        XCTAssertEqual(tracker.evaluate(state(), now: at(3_600)), .none, "no loop, however long it lasts")
        // A change of problem within the episode is not a second offer.
        XCTAssertEqual(tracker.evaluate(state(.notApproved), now: at(3_700)), .none)
        // Recovery ends the episode; a new failure is offered again.
        _ = tracker.evaluate(state(nil), now: at(3_800))
        _ = tracker.evaluate(state(), now: at(3_900))
        XCTAssertEqual(tracker.evaluate(state(), now: at(3_910)), .offer(.notResponding))
    }

    func testAnOfferNotShownStaysDue() {
        var tracker = Offer.Tracker()
        _ = tracker.evaluate(state(), now: at(0))
        XCTAssertEqual(tracker.evaluate(state(), now: at(10)), .offer(.notResponding))
        // The app could not show it (a game in front): not marked offered.
        XCTAssertEqual(tracker.evaluate(state(), now: at(60)), .offer(.notResponding))
    }

    func testUnlicensedPeopleAreNeverAskedAboutTheHelper() {
        var tracker = Offer.Tracker()
        for seconds in [0.0, 10, 100] {
            XCTAssertEqual(tracker.evaluate(state(licensed: false), now: at(seconds)), .none)
            XCTAssertEqual(tracker.evaluate(state(.notApproved, licensed: false), now: at(seconds)), .none)
        }
    }

    func testNoOfferWhileProtectionDoesNotNeedTheHelper() {
        var tracker = Offer.Tracker()
        XCTAssertEqual(tracker.evaluate(state(needed: false), now: at(0)), .none)
        XCTAssertEqual(tracker.evaluate(state(needed: false), now: at(100)), .none)
        // Once protection is needed again (for example the toggle is
        // turned on), a problem that has lasted is offered at once.
        XCTAssertEqual(tracker.evaluate(state(), now: at(101)), .offer(.notResponding))
    }

    func testBusyWaitsInsteadOfOffering() {
        var tracker = Offer.Tracker()
        _ = tracker.evaluate(state(), now: at(0))
        XCTAssertEqual(tracker.evaluate(state(busy: true), now: at(30)), .wait(Offer.debounce))
        XCTAssertEqual(tracker.evaluate(state(), now: at(31)), .offer(.notResponding))
    }

    func testAPersonsOwnRepairCountsAsTheOffer() {
        var tracker = Offer.Tracker()
        // Repair ran and the helper is still silent: the episode opens as
        // already offered.
        tracker.markOffered(problem: .notResponding, now: at(0))
        XCTAssertEqual(tracker.evaluate(state(), now: at(60)), .none)
        // Repair that fixed it ends the episode.
        tracker.markOffered(problem: nil, now: at(61))
        XCTAssertNil(tracker.episode)
    }

    func testAnUnapprovedHelperIsOffered() {
        var tracker = Offer.Tracker()
        _ = tracker.evaluate(state(.notApproved), now: at(0))
        XCTAssertEqual(tracker.evaluate(state(.notApproved), now: at(10)), .offer(.notApproved))
    }

    func testCustomDebounce() {
        var tracker = Offer.Tracker()
        XCTAssertEqual(tracker.evaluate(state(), now: at(0), debounce: 2), .wait(2))
        XCTAssertEqual(tracker.evaluate(state(), now: at(2), debounce: 2), .offer(.notResponding))
    }

    func testCopyNamesTheProblemAndPromisesNothingBeforeAClick() {
        XCTAssertNotEqual(Offer.Copy.title(for: .notResponding), Offer.Copy.title(for: .notApproved))
        for problem in [Offer.Problem.notResponding, .notApproved] {
            let message = Offer.Copy.message(for: problem)
            XCTAssertFalse(message.contains("—"), "no em dashes")
            XCTAssertTrue(message.contains("Repair"))
        }
        XCTAssertEqual(Offer.Copy.repairButton, "Repair…")
    }
}
