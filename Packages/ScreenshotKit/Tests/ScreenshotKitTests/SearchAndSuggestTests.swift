import XCTest
import ScreenshotKit

final class SearchAndSuggestTests: XCTestCase {
    private func library() -> Library {
        var lib = Library()
        lib.sync(with: [
            AssetInfo(id: "wifi", createdAt: Date(timeIntervalSince1970: 3), pixelWidth: 1, pixelHeight: 2),
            AssetInfo(id: "map", createdAt: Date(timeIntervalSince1970: 2), pixelWidth: 1, pixelHeight: 2),
            AssetInfo(id: "code", createdAt: Date(timeIntervalSince1970: 1), pixelWidth: 1, pixelHeight: 2)
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

    func testSuggesterCategories() {
        XCTAssertEqual(TagSuggester.suggest(for: "台北市信義區松高路 19 號 B2"), ["地址"])
        XCTAssertEqual(TagSuggester.suggest(for: "雙 11 限時優惠\nSAVE20\n全館 8 折"), ["優惠碼"])
        XCTAssertEqual(TagSuggester.suggest(for: "第 3 章 · 第 27 頁"), ["書摘"])
        XCTAssertEqual(TagSuggester.suggest(for: "func retry() async throws {\n  try await x\n}"), ["程式碼"])
        XCTAssertEqual(TagSuggester.suggest(for: "台北 TPE → 東京 NRT\n航班 BR 198\n座位 32K"), ["票券"])
    }

    func testSuggesterSkipsExistingTagsAndCapsCount() {
        XCTAssertEqual(TagSuggester.suggest(for: "密碼 1234", excluding: ["密碼"]), [])
        let noisy = "發票 合計 航班 密碼 會議 待辦 餐廳"
        XCTAssertEqual(TagSuggester.suggest(for: noisy).count, TagSuggester.maxSuggestions)
        XCTAssertEqual(TagSuggester.suggest(for: "   "), [])
    }
}
