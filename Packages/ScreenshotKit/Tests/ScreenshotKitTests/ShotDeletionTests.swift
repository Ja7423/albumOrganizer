import ScreenshotKit
import XCTest

final class ShotDeletionTests: XCTestCase {
    func testPreferenceRoundTripsThroughStoredValue() {
        for preference in [DeletionPreference.ask, .always(.deleteFromPhotos), .always(.removeFromApp)] {
            XCTAssertEqual(DeletionPreference(storedValue: preference.storedValue), preference)
        }
    }

    func testMissingOrUnknownStoredValueAsks() {
        XCTAssertEqual(DeletionPreference(storedValue: nil), .ask)
        XCTAssertEqual(DeletionPreference(storedValue: "album"), .ask)
        XCTAssertNil(DeletionPreference.ask.storedValue)
        XCTAssertNil(DeletionPreference.ask.method)
    }

    func testTitleNamesTheSubject() {
        XCTAssertEqual(DeletionCopy.title(for: .selection(count: 3)), "刪除 3 張截圖")
        XCTAssertEqual(DeletionCopy.title(for: .current), "刪除這張截圖")
    }

    func testSummaryForSelection() {
        XCTAssertEqual(DeletionCopy.summary(.deleteFromPhotos, subject: .selection(count: 2), isRemembered: false), "已刪除 2 張（含相簿原檔）")
        XCTAssertEqual(DeletionCopy.summary(.removeFromApp, subject: .selection(count: 2), isRemembered: false), "已從 App 移除 2 張（相簿原檔保留）")
    }

    func testSummaryForCurrentShot() {
        XCTAssertEqual(DeletionCopy.summary(.deleteFromPhotos, subject: .current, isRemembered: false), "已刪除這張（含相簿原檔）")
        XCTAssertEqual(DeletionCopy.summary(.removeFromApp, subject: .current, isRemembered: false), "已從 App 移除這張（相簿原檔保留）")
    }

    func testSummaryMentionsRememberedChoice() {
        XCTAssertEqual(DeletionCopy.summary(.removeFromApp, subject: .selection(count: 1), isRemembered: true), "已從 App 移除 1 張（相簿原檔保留）・已記住此選擇")
    }
}
