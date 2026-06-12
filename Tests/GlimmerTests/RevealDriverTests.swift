import XCTest
@testable import Glimmer

@MainActor
final class RevealDriverTests: XCTestCase {

    // MARK: - Progress store

    func testStoreReturnsZeroForUnknownOrNilID() {
        let store = RevealProgressStore()
        XCTAssertEqual(store.resume("never-seen"), 0)
        XCTAssertEqual(store.resume(nil), 0)
    }

    func testStoreRecordsAndResumes() {
        let store = RevealProgressStore()
        store.record(7, for: "turn-1")
        XCTAssertEqual(store.resume("turn-1"), 7)
    }

    func testStoreIsMonotonic() {
        let store = RevealProgressStore()
        store.record(5, for: "turn-1")
        store.record(3, for: "turn-1")
        XCTAssertEqual(store.resume("turn-1"), 5)
    }

    func testStoreClear() {
        let store = RevealProgressStore()
        store.record(5, for: "turn-1")
        store.clear("turn-1")
        XCTAssertEqual(store.resume("turn-1"), 0)
    }

    func testStoreIgnoresNilID() {
        let store = RevealProgressStore()
        store.record(5, for: nil) // must not crash, must not store
        XCTAssertEqual(store.resume(nil), 0)
    }

    // MARK: - Pacing math

    func testNominalIntervalInterpolatesJitterRange() {
        XCTAssertEqual(RevealPacing.nominalIntervalSeconds(style: .typewriter, jitter: 0), 0.018, accuracy: 1e-9)
        XCTAssertEqual(RevealPacing.nominalIntervalSeconds(style: .typewriter, jitter: 1), 0.042, accuracy: 1e-9)
        XCTAssertEqual(RevealPacing.nominalIntervalSeconds(style: .wordFade, jitter: 0.5), 0.075, accuracy: 1e-9)
    }

    func testStrictPolicyNeverAccelerates() {
        let base = RevealPacing.intervalSeconds(style: .wordFade, behind: 1000, catchUp: .strict, jitter: 0.5)
        XCTAssertEqual(base, 0.075, accuracy: 1e-9)
    }

    func testAdaptiveAcceleratesWhenFarBehindClampedAtQuarter() {
        // wordFade nominal 75ms, maxLag 1.5s -> targetLagUnits = 20
        let notBehind = RevealPacing.intervalSeconds(style: .wordFade, behind: 10, catchUp: .adaptive(maxLagSeconds: 1.5), jitter: 0.5)
        XCTAssertEqual(notBehind, 0.075, accuracy: 1e-9) // within target: full interval

        let slightlyBehind = RevealPacing.intervalSeconds(style: .wordFade, behind: 40, catchUp: .adaptive(maxLagSeconds: 1.5), jitter: 0.5)
        XCTAssertEqual(slightlyBehind, 0.075 * 0.5, accuracy: 1e-9) // 20/40

        let farBehind = RevealPacing.intervalSeconds(style: .wordFade, behind: 100_000, catchUp: .adaptive(maxLagSeconds: 1.5), jitter: 0.5)
        XCTAssertEqual(farBehind, 0.075 * 0.25, accuracy: 1e-9) // clamped at 0.25x
    }

    func testCappedSnapTriggersOnlyBeyondLagCap() {
        // wordFade nominal mid 75ms, cap 1.5s -> snap beyond 20 units behind
        XCTAssertFalse(RevealPacing.shouldSnap(style: .wordFade, behind: 20, catchUp: .cappedSnap(maxLagSeconds: 1.5)))
        XCTAssertTrue(RevealPacing.shouldSnap(style: .wordFade, behind: 21, catchUp: .cappedSnap(maxLagSeconds: 1.5)))
        XCTAssertFalse(RevealPacing.shouldSnap(style: .wordFade, behind: 1000, catchUp: .strict))
        XCTAssertFalse(RevealPacing.shouldSnap(style: .wordFade, behind: 1000, catchUp: .adaptive(maxLagSeconds: 1.5)))
    }

    func testStepRange() {
        XCTAssertEqual(RevealPacing.step(style: .wordFade, jitter: 0.9), 1)
        XCTAssertEqual(RevealPacing.step(style: .llmTokens, jitter: 0.0), 1)
        XCTAssertEqual(RevealPacing.step(style: .llmTokens, jitter: 0.99), 4)
        for jitter in stride(from: 0.0, through: 0.99, by: 0.01) {
            let s = RevealPacing.step(style: .llmTokens, jitter: jitter)
            XCTAssertTrue((1...4).contains(s), "step \(s) out of range at jitter \(jitter)")
        }
    }
}
