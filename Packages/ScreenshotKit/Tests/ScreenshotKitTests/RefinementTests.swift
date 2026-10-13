import ScreenshotKit
import XCTest

final class RefinementTests: XCTestCase {
    private func asset(_ id: String, _ minutesAgo: Double) -> AssetInfo {
        AssetInfo(id: id, createdAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60), pixelWidth: 1179, pixelHeight: 2556)
    }

    private func block(_ text: String) -> TextBlock {
        TextBlock(id: 0, text: text, box: NormalizedRect(x: 0.1, y: 0.3, width: 0.5, height: 0.02))
    }

    private func llmVerdict(_ category: BuiltInCategory) -> ClassifierVerdict {
        ClassifierVerdict(target: .builtIn(category), confidence: 0.9, source: .llm)
    }

    private func builtInFolder(_ lib: Library, _ category: BuiltInCategory) -> Folder? {
        lib.folders.first { $0.builtIn == category }
    }

    /// `ids` recognized with text and placed by the rule layer: in 未分類 unless `ruled` names a category.
    private func library(_ ids: [String], ruled: [String: BuiltInCategory] = [:]) -> Library {
        var lib = Library()
        lib.sync(with: ids.enumerated().map { asset($1, Double($0)) })
        for id in ids {
            lib.setRecognition(id, blocks: [block("一些文字")])
            let verdict = ruled[id].map { ClassifierVerdict(target: .builtIn($0), confidence: 0.9, source: .rule) }
            lib.applyClassification(id, verdict: verdict, features: [], version: 3)
        }
        return lib
    }

    func testOnlyUnsortedAutomaticShotsWithTextAwaitRefinement() {
        var lib = library(["unsorted", "ruled", "mine", "done", "textless"], ruled: ["ruled": .code])
        lib.move(["mine"], to: nil)
        lib.applyRefinement("done", verdict: nil)
        lib.requeueOutdated(version: 4)
        lib.setRecognition("textless", blocks: [block("  ")])
        for id in ["unsorted", "done", "textless"] {
            lib.applyClassification(id, verdict: nil, features: [], version: 4)
        }
        lib.applyRefinement("done", verdict: nil)

        XCTAssertEqual(lib.pendingRefinementIDs, ["unsorted"], "ruled is still processing; mine is the user's")
    }

    func testRefinementPlacesIntoBuiltInFolder() throws {
        var lib = library(["a"])
        lib.applyRefinement("a", verdict: llmVerdict(.recipe))

        let recipes = try XCTUnwrap(builtInFolder(lib, .recipe))
        XCTAssertEqual(lib.shot("a")?.folderID, recipes.id)
        XCTAssertEqual(lib.shot("a")?.placement, .auto(AutoPlacement(source: .llm, classifierVersion: 3, isRefined: true)))
        XCTAssertEqual(lib.pendingRefinementIDs, [])
    }

    func testNoAnswerOnlyMarksTheShot() {
        var lib = library(["a"])
        lib.applyRefinement("a", verdict: nil)

        XCTAssertNil(lib.shot("a")?.folderID)
        XCTAssertEqual(lib.shot("a")?.placement, .auto(AutoPlacement(source: nil, classifierVersion: 3, isRefined: true)))
        XCTAssertEqual(lib.pendingRefinementIDs, [])
    }

    func testManualMoveWinsOverRunningRefinement() throws {
        var lib = library(["a"])
        let notes = try XCTUnwrap(builtInFolder(lib, .note))
        lib.move(["a"], to: notes.id)
        lib.applyRefinement("a", verdict: llmVerdict(.recipe))

        XCTAssertEqual(lib.shot("a")?.folderID, notes.id)
        XCTAssertEqual(lib.shot("a")?.placement, .user)
    }

    func testShotsAlreadyInAFolderAreLeftAlone() {
        var lib = library(["a"], ruled: ["a": .code])
        let before = lib.shot("a")
        lib.applyRefinement("a", verdict: llmVerdict(.recipe))

        XCTAssertEqual(lib.shot("a"), before)
    }

    func testDeletedBuiltInCountsAsNoAnswer() throws {
        var lib = library(["a"])
        try lib.deleteFolder(XCTUnwrap(builtInFolder(lib, .recipe)?.id))
        lib.applyRefinement("a", verdict: llmVerdict(.recipe))

        XCTAssertNil(lib.shot("a")?.folderID)
        XCTAssertEqual(lib.shot("a")?.autoPlacement?.source, nil)
        XCTAssertEqual(lib.shot("a")?.autoPlacement?.isRefined, true)
    }

    func testReclassifyingAfterAVersionBumpRefinesAgain() {
        var lib = library(["a"])
        lib.applyRefinement("a", verdict: llmVerdict(.recipe))
        lib.requeueOutdated(version: 4)
        lib.applyClassification("a", verdict: nil, features: [], version: 4)

        XCTAssertEqual(lib.pendingRefinementIDs, ["a"])
    }
}
