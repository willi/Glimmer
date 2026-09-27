import XCTest

final class FrameHitchCounterTests: XCTestCase {
    func testASteadySixtyHertzRunHasNoHitches() {
        var counter = FrameHitchCounter()
        for frame in 0..<120 { counter.record(timestamp: Double(frame) / 60, frameDuration: 1.0 / 60) }
        XCTAssertEqual(counter.frames, 120)
        XCTAssertEqual(counter.hitches, 0)
    }

    func testALateFrameAtOneHundredTwentyHertzIsAHitch() {
        var counter = FrameHitchCounter()
        let frame = 1.0 / 120
        var time = 0.0
        for _ in 0..<10 { counter.record(timestamp: time, frameDuration: frame); time += frame }
        time += 0.050 - frame
        counter.record(timestamp: time, frameDuration: frame)
        XCTAssertEqual(counter.hitches, 1)
        XCTAssertEqual(counter.worstInterval, 0.050, accuracy: 0.0001)
    }
}
