import XCTest
import ScreenshotKit

final class LibraryTests: XCTestCase {
    private func asset(_ id: String, _ minutesAgo: Double) -> AssetInfo {
        AssetInfo(id: id, createdAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60), pixelWidth: 1179, pixelHeight: 2556)
    }

    private func block(_ text: String, y: Double = 0.3) -> TextBlock {
        TextBlock(id: 0, text: text, box: NormalizedRect(x: 0.1, y: y, width: 0.5, height: 0.02))
    }

    func testSyncAddsNewestFirstAndDropsDeleted() {
        var lib = Library()
        lib.sync(with: [asset("a", 10), asset("b", 1)])
        XCTAssertEqual(lib.shots.map(\.id), ["b", "a"])
        XCTAssertEqual(lib.pendingRecognitionIDs, ["b", "a"])

        let result = lib.sync(with: [asset("b", 1), asset("c", 0)])
        XCTAssertEqual(result, Library.SyncResult(added: ["c"], removed: 1))
        XCTAssertEqual(lib.shots.map(\.id), ["c", "b"])
    }

    func testHiddenShotsStayHiddenAcrossSync() {
        var lib = Library()
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        lib.hide(["a"])
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        XCTAssertEqual(lib.shots.map(\.id), ["b"])
    }

    func testRecognitionProducesSuggestions() {
        var lib = Library()
        lib.sync(with: [asset("a", 1)])
        lib.setRecognition("a", blocks: [block("家裡 Wi-Fi 密碼是多少？"), block("密碼 sunflower2026")])
        let shot = lib.shot("a")!
        XCTAssertEqual(shot.recognition, .done)
        XCTAssertEqual(shot.suggestions, ["密碼"])
        XCTAssertEqual(lib.count(in: .suggested), 1)
    }

    func testFailedRecognitionIsMarked() {
        var lib = Library()
        lib.sync(with: [asset("a", 1)])
        lib.setRecognition("a", blocks: nil)
        XCTAssertEqual(lib.shot("a")?.recognition, .failed)
    }

    func testOneFolderPerShot() {
        var lib = Library()
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        let work = lib.createFolder(named: " 工作 ")!
        let travel = lib.createFolder(named: "旅行")!
        XCTAssertEqual(work.name, "工作")
        XCTAssertEqual(lib.createFolder(named: "工作")?.id, work.id)

        lib.move(["a", "b"], to: work.id)
        lib.move(["a"], to: travel.id)
        XCTAssertEqual(lib.count(in: .folder(work.id)), 1)
        XCTAssertEqual(lib.count(in: .folder(travel.id)), 1)
        XCTAssertEqual(lib.count(in: .unsorted), 0)

        lib.deleteFolder(travel.id)
        XCTAssertNil(lib.shot("a")?.folderID)
        XCTAssertEqual(lib.folderName(nil), "未分類")
    }

    func testToggleTagAddsToAllUnlessAllHaveIt() {
        var lib = Library()
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        lib.addTag("#收據", to: ["a"])
        XCTAssertEqual(lib.tags, ["收據"])

        lib.toggleTag("收據", on: ["a", "b"])
        XCTAssertEqual(lib.count(in: .tag("收據")), 2)

        lib.toggleTag("收據", on: ["a", "b"])
        XCTAssertEqual(lib.count(in: .tag("收據")), 0)
        XCTAssertEqual(lib.tags, ["收據"], "removing a tag from shots keeps the tag itself")
    }

    func testAcceptingAndApplyingSuggestions() {
        var lib = Library()
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        lib.setRecognition("a", blocks: [block("週四 demo 改到下午 3:00"), block("會議室在 12F-B")])
        lib.setRecognition("b", blocks: [block("電子發票證明聯"), block("金額 $185")])
        XCTAssertEqual(lib.suggestedTagNames, ["會議", "收據"])

        lib.acceptSuggestion("會議", for: "a")
        XCTAssertEqual(lib.shot("a")?.tags, ["會議"])
        XCTAssertEqual(lib.shot("a")?.suggestions, [])

        XCTAssertEqual(lib.applyAllSuggestions(), 1)
        XCTAssertEqual(lib.shot("b")?.tags, ["收據"])
        XCTAssertEqual(Set(lib.tags), ["會議", "收據"])
        XCTAssertEqual(lib.count(in: .suggested), 0)
    }

    func testDeleteTagRemovesItEverywhere() {
        var lib = Library()
        lib.sync(with: [asset("a", 1)])
        lib.addTag("靈感", to: ["a"])
        lib.deleteTag("靈感")
        XCTAssertEqual(lib.tags, [])
        XCTAssertEqual(lib.shot("a")?.tags, [])
    }

    func testTitleSkipsClockAndShortLines() {
        let shot = Shot(id: "x", createdAt: Date(), pixelWidth: 1, pixelHeight: 2,
                        blocks: [block("9:41"), block("<"), block("訂單已成立")])
        XCTAssertEqual(shot.title, "訂單已成立")
        XCTAssertEqual(Shot(id: "y", createdAt: Date(), pixelWidth: 1, pixelHeight: 2).title, "螢幕截圖")
    }

    func testStatusBarLinesAreDropped() {
        let blocks = [block("9:41", y: 0.01), block("5G", y: 0.012), block("訂單明細", y: 0.08)]
        let kept = TextBlockFilter.droppingStatusBar(blocks)
        XCTAssertEqual(kept.map(\.text), ["訂單明細"])
        XCTAssertEqual(kept.map(\.id), [0])
    }

    func testLanguageSummary() {
        let shot = Shot(id: "x", createdAt: Date(), pixelWidth: 1, pixelHeight: 2, blocks: [block("航班 BR 198")])
        XCTAssertEqual(shot.languageSummary, "繁體中文 / 英文")
    }
}
