import ScreenshotKit
import XCTest

final class SearchTests: XCTestCase {
    private func library() -> Library {
        var lib = Library()
        lib.sync(with: [
            AssetInfo(id: "wifi", createdAt: Date(timeIntervalSince1970: 3), pixelWidth: 1, pixelHeight: 2),
            AssetInfo(id: "map", createdAt: Date(timeIntervalSince1970: 2), pixelWidth: 1, pixelHeight: 2),
            AssetInfo(id: "code", createdAt: Date(timeIntervalSince1970: 1), pixelWidth: 1, pixelHeight: 2),
        ])
        let box = NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.02)
        lib.setRecognition("wifi", blocks: [TextBlock(id: 0, text: "網路名稱 TPE-Home-5G", box: box),
                                            TextBlock(id: 1, text: "密碼 sunflower2026", box: box)])
        lib.setRecognition("map", blocks: [TextBlock(id: 0, text: "鼎泰豐 信義店", box: box),
                                           TextBlock(id: 1, text: "台北市信義區松高路 19 號 B2", box: box)])
        lib.setRecognition("code", blocks: [TextBlock(id: 0, text: "func retry(times: Int) async throws {", box: box)])
        lib.addTag("程式碼", to: ["code"])
        return lib
    }

    func testSearchHighlightsMatchInText() {
        let hits = library().search("松高路")
        XCTAssertEqual(hits.map(\.shotID), ["map"])
        XCTAssertEqual(hits[0].prefix, "台北市信義區")
        XCTAssertEqual(hits[0].match, "松高路")
        XCTAssertEqual(hits[0].suffix, " 19 號 B2")
    }

    func testSearchIsCaseAndWidthInsensitive() {
        XCTAssertEqual(library().search("SUNFLOWER").first?.match, "sunflower")
        XCTAssertEqual(library().search("ＴＰＥ").first?.shotID, "wifi")
    }

    func testSearchFallsBackToTags() {
        let hit = library().search("程式").first
        XCTAssertEqual(hit?.shotID, "code")
        XCTAssertEqual(hit?.match, "")
    }

    func testSearchTrimsLongPrefix() {
        var lib = Library()
        lib.sync(with: [AssetInfo(id: "a", createdAt: Date(), pixelWidth: 1, pixelHeight: 2)])
        lib.setRecognition("a", blocks: [TextBlock(id: 0, text: "一二三四五六七八九十甲乙丙丁戊己 目標", box: NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.1))])
        XCTAssertEqual(lib.search("目標").first?.prefix, "…六七八九十甲乙丙丁戊己 ")
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertTrue(library().search("  ").isEmpty)
    }

    func testSearchMatchesFeatureTags() throws {
        var lib = library()
        let input = try XCTUnwrap(lib.classifierInput(for: "map"))
        lib.applyClassification("map", verdict: nil, features: FeatureDetector.detect(input.signals), version: 1)
        XCTAssertEqual(lib.search("含地址").map(\.shotID), ["map"])
    }
}
