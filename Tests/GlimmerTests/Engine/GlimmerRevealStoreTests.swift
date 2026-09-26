import XCTest
@testable import Glimmer

@MainActor
final class GlimmerRevealStoreTests: XCTestCase {
    private let text = "An answer long enough to reveal in several phrases." as NSString

    func testStoreIsMonotonicAndBounded() {
        let store = GlimmerRevealStore(capacity: 2)
        store.record(10, text: text, for: "a")
        store.record(5, text: text, for: "a")
        XCTAssertEqual(store.revealedLength(for: "a", text: text), 10)
        store.record(1, text: text, for: "b")
        store.record(1, text: text, for: "c")
        XCTAssertNil(store.revealedLength(for: "a", text: text), "least recently used is evicted")
    }

    func testRegeneratedAnswerUnderTheSameIDStartsOver() {
        let store = GlimmerRevealStore(capacity: 4)
        let first = "The first generation of this answer." as NSString
        store.record(20, text: first, for: "m")
        store.record(30, text: first, for: "m")
        XCTAssertEqual(store.revealedLength(for: "m", text: first), 30, "the same answer keeps growing")
        let regenerated = "A regenerated answer that says otherwise." as NSString
        XCTAssertNil(store.revealedLength(for: "m", text: regenerated))
        store.record(5, text: regenerated, for: "m")
        XCTAssertEqual(store.revealedLength(for: "m", text: regenerated), 5, "a new generation restarts at its own length")
    }
}
