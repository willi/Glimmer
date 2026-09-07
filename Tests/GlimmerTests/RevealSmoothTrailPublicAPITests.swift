import Foundation
import Glimmer
import Observation
import XCTest

// Deliberately omit @testable: these tests use the same API as a native renderer
// that owns one driver for the countable atoms across several Markdown blocks.
@MainActor
final class RevealSmoothTrailPublicAPITests: XCTestCase {
    func testPublicEnvelopeUsesElapsedSeconds() {
        XCTAssertGreaterThan(RevealSmoothTrail.duration, 0)
        XCTAssertEqual(RevealSmoothTrail.opacity(age: -1), 0)
        XCTAssertEqual(RevealSmoothTrail.opacity(age: 0), 0)
        XCTAssertEqual(RevealSmoothTrail.opacity(age: RevealSmoothTrail.duration / 2), 0.875)
        XCTAssertEqual(RevealSmoothTrail.opacity(age: RevealSmoothTrail.duration), 1)
        XCTAssertEqual(RevealSmoothTrail.opacity(age: RevealSmoothTrail.duration * 2), 1)
    }

    func testPublicSnapshotSettlesDuringProducerPauseWithoutAnotherUpdate() async throws {
        try await withRunningDriver(isStreaming: true) { driver in
            let startedAt = ProcessInfo.processInfo.systemUptime
            driver.update(totalCountable: 1, isStreaming: true)
            try await waitUntil("The first atom should begin fading") {
                driver.smoothTrail.starts[1] != nil
            }

            let active = driver.smoothTrail
            let start = try XCTUnwrap(active.starts[1])
            XCTAssertEqual(Set(active.starts.keys), [1])
            XCTAssertEqual(active.settledCount, 0)
            XCTAssertFalse(active.isSettled)
            XCTAssertFalse(driver.isComplete)
            XCTAssertGreaterThanOrEqual(start, startedAt)
            XCTAssertLessThanOrEqual(start, ProcessInfo.processInfo.systemUptime)
            XCTAssertEqual(try XCTUnwrap(active.nextSettlement), start + RevealSmoothTrail.duration)
            XCTAssertFalse(blockIsSettled(1...1, driver: driver))

            // Only settlement can change smoothTrail now: the only atom is
            // already revealed and no more producer updates are sent.
            let invalidations = ObservationCounter()
            let observed = withObservationTracking {
                driver.smoothTrail
            } onChange: {
                // Observation invokes this synchronously on the mutation's
                // actor, and RevealDriver is isolated to the main actor.
                MainActor.assumeIsolated { invalidations.count += 1 }
            }
            XCTAssertEqual(observed, active)
            XCTAssertEqual(invalidations.count, 0)

            // A Sendable value snapshot can leave the UI actor and keeps its
            // original contents after the driver's observable state changes.
            let copied = await Task.detached { sendableCopy(active) }.value
            XCTAssertEqual(copied, active)

            try await waitUntil("A paused producer's tail should settle on the driver's clock") {
                driver.smoothTrail.settledCount == 1 && driver.smoothTrail.isSettled
            }

            XCTAssertEqual(driver.revealedCount, 1)
            XCTAssertFalse(driver.isComplete)
            XCTAssertTrue(driver.smoothTrail.starts.isEmpty)
            XCTAssertNil(driver.smoothTrail.nextSettlement)
            XCTAssertEqual(invalidations.count, 1, "Tail settlement must invalidate a native consumer's observation")
            XCTAssertTrue(blockIsSettled(1...1, driver: driver))
            // An absent start timestamp does not make unrevealed content settled.
            XCTAssertFalse(blockIsSettled(2...2, driver: driver))
            XCTAssertFalse(active.isSettled)
            XCTAssertEqual(active.starts[1], start)
            XCTAssertNotEqual(active, driver.smoothTrail)

            // An earlier block remains settled while a new block uses the
            // same driver's next global reveal index and begins its fade.
            driver.update(totalCountable: 2, isStreaming: true)
            try await waitUntil("The appended block should start fading on the existing driver") {
                driver.smoothTrail.starts[2] != nil
            }
            XCTAssertEqual(driver.revealedCount, 2)
            XCTAssertEqual(driver.smoothTrail.settledCount, 1)
            XCTAssertEqual(Set(driver.smoothTrail.starts.keys), [2])
            XCTAssertTrue(blockIsSettled(1...1, driver: driver))
            XCTAssertFalse(blockIsSettled(2...2, driver: driver))
            XCTAssertFalse(driver.isComplete)
        }
    }

    func testPublicSnapshotKeepsCompletedProducerTailActiveUntilFadeFinishes() async throws {
        try await withRunningDriver(isStreaming: false) { driver in
            driver.update(totalCountable: 2, isStreaming: false)
            try await waitUntil("The final block should be revealed while its tail is still fading") {
                driver.revealedCount == 2 && driver.smoothTrail.starts[2] != nil
            }

            let active = driver.smoothTrail
            let lastStart = try XCTUnwrap(active.starts[2])
            XCTAssertFalse(active.isSettled)
            XCTAssertFalse(driver.isComplete)
            XCTAssertFalse(blockIsSettled(2...2, driver: driver))
            XCTAssertEqual(
                try XCTUnwrap(active.nextSettlement),
                try XCTUnwrap(active.starts.values.min()) + RevealSmoothTrail.duration
            )

            try await waitUntil("Completion should follow the final atom's settlement") {
                driver.isComplete
            }

            XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime, lastStart + RevealSmoothTrail.duration)
            XCTAssertEqual(driver.revealedCount, 2)
            XCTAssertEqual(driver.smoothTrail.settledCount, 2)
            XCTAssertTrue(driver.smoothTrail.isSettled)
            XCTAssertTrue(driver.smoothTrail.starts.isEmpty)
            XCTAssertNil(driver.smoothTrail.nextSettlement)
            XCTAssertTrue(blockIsSettled(1...1, driver: driver))
            XCTAssertTrue(blockIsSettled(2...2, driver: driver))
        }
    }

    /// A native block uses global, one-based reveal indices. All of its atoms
    /// must be revealed, and none may still have a timestamp in the active tail.
    private func blockIsSettled(_ indices: ClosedRange<Int>, driver: RevealDriver) -> Bool {
        driver.revealedCount >= indices.upperBound
            && !indices.contains { driver.smoothTrail.starts[$0] != nil }
    }

    private func withRunningDriver(
        isStreaming: Bool,
        body: @MainActor (RevealDriver) async throws -> Void
    ) async throws {
        let driver = RevealDriver(configuration: .init(
            style: .smoothTrail,
            catchUp: .strict,
            isStreaming: isStreaming
        ))
        let runner = Task { await driver.run() }
        do {
            try await body(driver)
        } catch {
            runner.cancel()
            await runner.value
            throw error
        }
        runner.cancel()
        await runner.value
    }

    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                XCTFail(message, file: file, line: line)
                throw ObservationTimeout()
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private struct ObservationTimeout: Error {}

    @MainActor
    private final class ObservationCounter {
        var count = 0
    }
}

private func sendableCopy<Value: Sendable>(_ value: Value) -> Value { value }
