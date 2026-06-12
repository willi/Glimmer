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

    // MARK: - Driver

    private func makeDriver(
        _ config: RevealConfiguration,
        store: RevealProgressStore? = nil,
        sleep: @escaping @MainActor (Double) async throws -> Void = { _ in }
    ) -> RevealDriver {
        RevealDriver(configuration: config, store: store ?? RevealProgressStore(), sleep: sleep)
    }

    // MARK: - Trail fade

    func testTrailOpacityNewestWordIsAtFloor() {
        let newest = RevealTrail.opacity(revealIndex: 10, revealedCount: 10, isComplete: false)
        XCTAssertEqual(newest, RevealTrail.floor, accuracy: 1e-9)
    }

    func testTrailOpacityRampsToFullWithDistance() {
        let halfway = RevealTrail.opacity(revealIndex: 4, revealedCount: 10, isComplete: false)
        XCTAssertEqual(halfway, RevealTrail.floor + (1 - RevealTrail.floor) * (6 / RevealTrail.length), accuracy: 1e-9)
        XCTAssertEqual(RevealTrail.opacity(revealIndex: 1, revealedCount: 100, isComplete: false), 1.0)
    }

    func testTrailOpacityMonotonicAndCapped() {
        var last = -1.0
        for distance in 0...20 {
            let o = RevealTrail.opacity(revealIndex: 50 - distance, revealedCount: 50, isComplete: false)
            XCTAssertGreaterThanOrEqual(o, last, "opacity must not decrease with distance")
            XCTAssertLessThanOrEqual(o, 1.0)
            last = o
        }
    }

    func testTrailOpacityFullWhenComplete() {
        XCTAssertEqual(RevealTrail.opacity(revealIndex: 10, revealedCount: 10, isComplete: true), 1.0)
    }

    func testDrainsToTotalAndCompletes() async {
        let driver = makeDriver(RevealConfiguration(style: .wordFade, isStreaming: false))
        driver.update(totalCountable: 10, isStreaming: false)
        await driver.run()
        XCTAssertEqual(driver.revealedCount, 10)
        XCTAssertTrue(driver.isComplete)
    }

    func testRevealedCountIsMonotonicAndBounded() async {
        var counts: [Int] = []
        let store = RevealProgressStore()
        var driver: RevealDriver!
        driver = makeDriver(RevealConfiguration(style: .llmTokens, isStreaming: false), store: store) { _ in
            counts.append(driver.revealedCount)
        }
        driver.update(totalCountable: 9, isStreaming: false)
        await driver.run()
        XCTAssertEqual(driver.revealedCount, 9)
        XCTAssertEqual(counts, counts.sorted(), "revealedCount must be monotonic")
        XCTAssertTrue(counts.allSatisfy { $0 <= 9 })
    }

    func testIdlesWhileStreamingThenCompletesWhenStreamEnds() async {
        var idleTicks = 0
        var driver: RevealDriver!
        driver = makeDriver(RevealConfiguration(style: .wordFade, isStreaming: true)) { seconds in
            if seconds < 0.02 { // the 16ms idle wait
                idleTicks += 1
                if idleTicks >= 3 {
                    driver.update(totalCountable: 5, isStreaming: false)
                }
            }
        }
        driver.update(totalCountable: 5, isStreaming: true)
        await driver.run()
        XCTAssertTrue(driver.isComplete)
        XCTAssertEqual(driver.revealedCount, 5)
        XCTAssertGreaterThanOrEqual(idleTicks, 3, "driver must idle-wait while streaming with drained buffer")
    }

    func testBufferGrowthMidRunExtendsReveal() async {
        var sleeps = 0
        var driver: RevealDriver!
        driver = makeDriver(RevealConfiguration(style: .wordFade, isStreaming: true)) { _ in
            sleeps += 1
            if sleeps == 3 {
                driver.update(totalCountable: 8, isStreaming: false)
            }
        }
        driver.update(totalCountable: 4, isStreaming: true)
        await driver.run()
        XCTAssertEqual(driver.revealedCount, 8)
        XCTAssertTrue(driver.isComplete)
    }

    func testResumeSeedsRevealedCountAndAnimateFrom() {
        let store = RevealProgressStore()
        store.record(7, for: "turn-1")
        let driver = makeDriver(
            RevealConfiguration(style: .wordFade, isStreaming: true, revealID: "turn-1"),
            store: store
        )
        XCTAssertEqual(driver.revealedCount, 7)
        XCTAssertEqual(driver.animateFrom, 7)
    }

    func testDriverRecordsProgressToStore() async {
        let store = RevealProgressStore()
        let driver = makeDriver(
            RevealConfiguration(style: .wordFade, isStreaming: false, revealID: "turn-2"),
            store: store
        )
        driver.update(totalCountable: 6, isStreaming: false)
        await driver.run()
        XCTAssertEqual(store.resume("turn-2"), 6)
    }

    func testCappedSnapRevealsAllAtOnceWhenFarBehind() async {
        var sleeps = 0
        let driver = makeDriver(
            RevealConfiguration(style: .wordFade, catchUp: .cappedSnap(maxLagSeconds: 1.5), isStreaming: false)
        ) { _ in sleeps += 1 }
        driver.update(totalCountable: 500, isStreaming: false) // far beyond 20-unit cap
        await driver.run()
        XCTAssertEqual(driver.revealedCount, 500)
        XCTAssertEqual(sleeps, 0, "snap must not pace through the backlog")
    }

    func testUpdateClampsWhenBufferShrinks() {
        let store = RevealProgressStore()
        store.record(10, for: "t")
        let resumed = makeDriver(RevealConfiguration(style: .wordFade, isStreaming: true, revealID: "t"), store: store)
        resumed.update(totalCountable: 4, isStreaming: true) // buffer replaced with shorter content
        XCTAssertEqual(resumed.revealedCount, 4)
    }
}
