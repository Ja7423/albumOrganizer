import ScreenshotKit
import XCTest

final class TrainingSetTests: XCTestCase {
    private func library(texts: [String: String]) -> Library {
        var lib = Library()
        lib.sync(with: texts.keys.sorted().map { AssetInfo(id: $0, createdAt: Date(timeIntervalSince1970: 0), pixelWidth: 1, pixelHeight: 2) })
        for (id, text) in texts {
            let blocks = text.isEmpty ? [] : [TextBlock(id: 0, text: text, box: NormalizedRect(x: 0.1, y: 0.3, width: 0.5, height: 0.02))]
            lib.setRecognition(id, blocks: blocks, barcodes: [])
        }
        return lib
    }

    private func folder(_ lib: Library, _ category: BuiltInCategory) throws -> UUID {
        try XCTUnwrap(lib.folders.first { $0.builtIn == category }?.id)
    }

    func testOnlyUserPlacementsWithTextInBuiltInFoldersOrUnsorted() throws {
        var lib = library(texts: ["receipt": "發票 合計", "unsorted": "天氣 晴", "auto": "航班", "custom": "筆記", "blank": ""])
        let custom = try XCTUnwrap(lib.createFolder(named: "旅行")).id
        try lib.move(["receipt"], to: folder(lib, .receipt))
        lib.move(["unsorted"], to: nil)
        lib.move(["custom"], to: custom)
        lib.move(["blank"], to: nil)
        lib.applyClassification("auto", verdict: ClassifierVerdict(target: .builtIn(.ticket), confidence: 0.9, source: .rule), features: [], version: 1)

        let samples = lib.trainingSet.samples.sorted { ($0.id ?? "") < ($1.id ?? "") }
        XCTAssertEqual(samples, [
            LabeledSample(id: "receipt", expected: .receipt, text: "發票 合計"),
            LabeledSample(id: "unsorted", expected: nil, text: "天氣 晴"),
        ])
    }

    func testDeletedBuiltInsAreNeverTaught() throws {
        var lib = library(texts: ["a": "已讀 晚餐"])
        try lib.move(["a"], to: folder(lib, .note))
        try lib.deleteFolder(folder(lib, .recipe))

        let set = lib.trainingSet
        XCTAssertEqual(set.excluded, [.recipe])
        let texts = set.labeledTexts(seed: [
            LabeledSample(expected: .recipe, text: "食譜\n材料"),
            LabeledSample(expected: .ticket, text: "航班\n座位"),
            LabeledSample(expected: nil, text: "天氣"),
        ])
        XCTAssertEqual(texts, ["note": ["已讀 晚餐"], "ticket": ["航班 座位"], TrainingSet.noneLabel: ["天氣"]])
    }

    func testFingerprintFollowsAnswersAndDeletions() {
        let a = LabeledSample(id: "a", expected: .receipt, text: "x")
        let b = LabeledSample(id: "b", expected: nil, text: "y")
        let base = TrainingSet(samples: [a, b])

        XCTAssertEqual(base.fingerprint, TrainingSet(samples: [b, a]).fingerprint, "order does not matter")
        XCTAssertNotEqual(base.fingerprint, TrainingSet(samples: [a]).fingerprint)
        XCTAssertNotEqual(base.fingerprint, TrainingSet(samples: [a, LabeledSample(id: "b", expected: .note, text: "y")]).fingerprint)
        XCTAssertNotEqual(base.fingerprint, TrainingSet(samples: [a, b], excluded: [.code]).fingerprint)
    }

    func testRequeueUnsortedAutomaticLeavesPlacedAndUserShots() throws {
        var lib = library(texts: ["placed": "發票", "unsorted": "天氣", "mine": "隨手", "blank": ""])
        lib.applyClassification("placed", verdict: ClassifierVerdict(target: .builtIn(.receipt), confidence: 0.9, source: .rule), features: [], version: 1)
        lib.applyClassification("unsorted", verdict: nil, features: [], version: 1)
        lib.applyClassification("blank", verdict: nil, features: [], version: 1)
        lib.move(["mine"], to: nil)

        lib.requeueUnsortedAutomatic()
        XCTAssertEqual(lib.shots(in: .processing).map(\.id), ["unsorted"])
        XCTAssertEqual(lib.shot("mine")?.placement, .user)
    }

    func testSeedSamplesCoverEveryCategory() {
        XCTAssertEqual(Set(LabeledSample.seedSamples.compactMap(\.expected)), Set(BuiltInCategory.allCases))
    }
}
