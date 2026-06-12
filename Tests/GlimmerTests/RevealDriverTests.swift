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
}
