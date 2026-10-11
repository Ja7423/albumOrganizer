import ScreenshotKit
import XCTest

final class RecentSearchesTests: XCTestCase {
    func testRecordingPutsNewestFirst() {
        let recent = RecentSearches().recording("密碼").recording("地址")
        XCTAssertEqual(recent.queries, ["地址", "密碼"])
    }

    func testRecordingAgainMovesQueryToFront() {
        let recent = RecentSearches(["地址", "密碼", "發票"]).recording("發票")
        XCTAssertEqual(recent.queries, ["發票", "地址", "密碼"])
    }

    func testKeepsOnlyFiveMostRecent() {
        let recent = ["1", "2", "3", "4", "5", "6"].reduce(RecentSearches()) { $0.recording($1) }
        XCTAssertEqual(recent.queries, ["6", "5", "4", "3", "2"])
    }

    func testRecordingTrimsAndIgnoresBlank() {
        XCTAssertEqual(RecentSearches().recording("  密碼 ").queries, ["密碼"])
        XCTAssertEqual(RecentSearches(["密碼"]).recording("   ").queries, ["密碼"])
    }
}
