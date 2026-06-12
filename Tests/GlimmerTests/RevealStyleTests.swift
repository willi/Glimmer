import XCTest
@testable import Glimmer

final class RevealStyleTests: XCTestCase {

    func testGranularityMapping() {
        XCTAssertEqual(RevealStyle.typewriter.granularity, .character)
        XCTAssertEqual(RevealStyle.llmTokens.granularity, .character)
        XCTAssertEqual(RevealStyle.charCascade.granularity, .character)
        XCTAssertEqual(RevealStyle.diffusion.granularity, .character)
        XCTAssertEqual(RevealStyle.lineSlide.granularity, .line)
        XCTAssertEqual(RevealStyle.wordFade.granularity, .word)
        XCTAssertEqual(RevealStyle.blurIn.granularity, .word)
        XCTAssertEqual(RevealStyle.shimmer.granularity, .word)
        XCTAssertEqual(RevealStyle.tracking.granularity, .word)
        XCTAssertEqual(RevealStyle.waveGlow.granularity, .word)
        XCTAssertEqual(RevealStyle.none.granularity, .word)
    }

    func testTreatmentMapping() {
        XCTAssertEqual(RevealStyle.typewriter.treatment, .caret)
        XCTAssertEqual(RevealStyle.llmTokens.treatment, .plain)
        XCTAssertEqual(RevealStyle.wordFade.treatment, .fade)
        XCTAssertEqual(RevealStyle.blurIn.treatment, .blur)
        XCTAssertEqual(RevealStyle.lineSlide.treatment, .slide)
        XCTAssertEqual(RevealStyle.charCascade.treatment, .dropIn)
        XCTAssertEqual(RevealStyle.shimmer.treatment, .shimmer)
        XCTAssertEqual(RevealStyle.tracking.treatment, .tracking)
        XCTAssertEqual(RevealStyle.diffusion.treatment, .scramble)
        XCTAssertEqual(RevealStyle.waveGlow.treatment, .glow)
    }

    func testCadencesMatchSpecAppendix() {
        XCTAssertEqual(RevealStyle.typewriter.nominalUnitIntervalMs, 18...42)
        XCTAssertEqual(RevealStyle.llmTokens.nominalUnitIntervalMs, 60...140)
        XCTAssertEqual(RevealStyle.wordFade.nominalUnitIntervalMs, 75...75)
        XCTAssertEqual(RevealStyle.blurIn.nominalUnitIntervalMs, 100...100)
        XCTAssertEqual(RevealStyle.lineSlide.nominalUnitIntervalMs, 320...320)
        XCTAssertEqual(RevealStyle.charCascade.nominalUnitIntervalMs, 22...22)
        XCTAssertEqual(RevealStyle.shimmer.nominalUnitIntervalMs, 85...85)
        XCTAssertEqual(RevealStyle.tracking.nominalUnitIntervalMs, 100...100)
        XCTAssertEqual(RevealStyle.diffusion.nominalUnitIntervalMs, 22...40)
        XCTAssertEqual(RevealStyle.waveGlow.nominalUnitIntervalMs, 105...105)
    }

    func testUnitsPerStep() {
        XCTAssertEqual(RevealStyle.llmTokens.unitsPerStep, 1...4)
        for style in RevealStyle.allCases where style != .llmTokens {
            XCTAssertEqual(style.unitsPerStep, 1...1, "\(style) should unlock one unit per step")
        }
    }

    func testRevealConfigurationDefaults() {
        let config = RevealConfiguration()
        XCTAssertEqual(config.style, .wordFade)
        XCTAssertEqual(config.catchUp, .adaptive(maxLagSeconds: 1.5))
        XCTAssertFalse(config.isStreaming)
        XCTAssertNil(config.revealID)
        XCTAssertNil(config.demoDurationCap)
    }
}
