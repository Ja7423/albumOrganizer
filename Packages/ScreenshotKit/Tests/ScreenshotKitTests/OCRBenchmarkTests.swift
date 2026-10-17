import ScreenshotKit
import XCTest

final class TextSimilarityTests: XCTestCase {
    func testIdenticalAndEmptyTextsAreFullyAlike() {
        XCTAssertEqual(TextSimilarity.ratio("轉帳成功", "轉帳成功"), 1)
        XCTAssertEqual(TextSimilarity.ratio("", ""), 1)
    }

    func testNothingInCommonIsZero() {
        XCTAssertEqual(TextSimilarity.ratio("abc", ""), 0)
        XCTAssertEqual(TextSimilarity.ratio("abc", "xyz"), 0)
    }

    func testRatioIsEditsOverTheLongerText() {
        // One substitution in four characters.
        XCTAssertEqual(TextSimilarity.ratio("轉帳成功", "轉賬成功"), 0.75, accuracy: 1e-9)
        // One insertion; the longer text has five characters.
        XCTAssertEqual(TextSimilarity.ratio("abcd", "abXcd"), 0.8, accuracy: 1e-9)
    }

    func testEditDistanceMatchesTheClassicExamples() {
        XCTAssertEqual(TextSimilarity.editDistance(Array("kitten"), Array("sitting")), 3)
        XCTAssertEqual(TextSimilarity.editDistance(Array("flaw"), Array("lawn")), 2)
        XCTAssertEqual(TextSimilarity.editDistance(Array("abc"), Array("abc")), 0)
        XCTAssertEqual(TextSimilarity.editDistance(Array(""), Array("abc")), 3)
    }

    func testSharedPrefixAndSuffixDoNotChangeTheDistance() {
        let prefix = String(repeating: "前", count: 50), suffix = String(repeating: "後", count: 50)
        XCTAssertEqual(TextSimilarity.editDistance(Array(prefix + "kitten" + suffix), Array(prefix + "sitting" + suffix)), 3)
    }

    func testIsSymmetric() {
        XCTAssertEqual(TextSimilarity.ratio("訂單編號 123", "訂單 12"), TextSimilarity.ratio("訂單 12", "訂單編號 123"))
    }
}

final class RecognitionOptionsTests: XCTestCase {
    func testStandardMatchesTheRecognizerAsShipped() {
        let standard = RecognitionOptions.standard
        XCTAssertEqual(standard.scale, 1)
        XCTAssertTrue(standard.usesLanguageCorrection)
        XCTAssertNil(standard.minimumTextHeight)
        XCTAssertNil(standard.regionOfInterest)
        XCTAssertTrue(standard.detectsBarcodes)
    }

    func testGridIsEveryCombinationWithFirstValuesFirst() {
        let grid = RecognitionOptions.grid(scales: [1, 0.5], languageCorrection: [true, false], barcodes: [true, false])
        XCTAssertEqual(grid.count, 8)
        XCTAssertEqual(grid.first, .standard)
        XCTAssertEqual(Set(grid).count, 8)
        XCTAssertEqual(grid.last, RecognitionOptions(scale: 0.5, usesLanguageCorrection: false, detectsBarcodes: false))
    }

    func testBenchmarkStartsWithTheBaselineAndHasNoDuplicates() {
        let variants = RecognitionOptions.benchmarkVariants
        XCTAssertEqual(variants.first, .standard)
        XCTAssertEqual(Set(variants).count, variants.count)
        XCTAssertEqual(variants.filter { $0 == .standard }.count, 1)
    }

    func testEveryBenchmarkVariantHasItsOwnLabel() {
        let labels = RecognitionOptions.benchmarkVariants.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertEqual(RecognitionOptions.standard.label, "scale=1.00 lc=on minH=default roi=full bc=on")
    }

    func testContentRegionLeavesOutTheStatusBarAndHomeIndicator() {
        let region = RecognitionOptions.contentRegion
        XCTAssertEqual(region.y, TextBlockFilter.statusBarHeight)
        XCTAssertLessThan(region.maxY, 1)
        XCTAssertEqual(RecognitionOptions(regionOfInterest: region).label, "scale=1.00 lc=on minH=default roi=content bc=on")
    }

    func testBoxInsideARegionMapsBackToTheWholeImage() {
        let region = NormalizedRect(x: 0, y: 0.1, width: 1, height: 0.8)
        let box = NormalizedRect(x: 0.5, y: 0.5, width: 0.2, height: 0.1).mapped(fromRegion: region)
        XCTAssertEqual(box.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(box.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(box.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(box.height, 0.08, accuracy: 1e-9)
    }
}

final class OCRBenchmarkTallyTests: XCTestCase {
    func testComparesEachScreenshotWithTheBaseline() {
        var tally = OCRBenchmarkTally()
        tally.record(milliseconds: 100, text: "abcd", target: .builtIn(.receipt), blocks: 2, baselineText: "abcd", baselineTarget: .builtIn(.receipt))
        tally.record(milliseconds: 300, text: "abXd", target: nil, blocks: 1, baselineText: "abcd", baselineTarget: .builtIn(.receipt))
        tally.record(milliseconds: 0, text: nil, target: nil, blocks: 0, baselineText: "abcd", baselineTarget: nil)

        XCTAssertEqual(tally.count, 3)
        XCTAssertEqual(tally.failures, 1)
        XCTAssertEqual(tally.averageMilliseconds, 200, accuracy: 1e-9)
        XCTAssertEqual(tally.averageSimilarity, 0.875, accuracy: 1e-9)
        XCTAssertEqual(tally.minimumSimilarity, 0.75, accuracy: 1e-9)
        XCTAssertEqual(tally.classificationDifferences, 1)
        XCTAssertEqual(tally.blockCount, 3)
    }

    func testPercentilesUseNearestRank() {
        var tally = OCRBenchmarkTally()
        for ms in [50.0, 10, 40, 20, 30, 60, 70, 80, 90, 100] {
            tally.record(milliseconds: ms, text: "", target: nil, blocks: 0, baselineText: "", baselineTarget: nil)
        }
        XCTAssertEqual(tally.percentileMilliseconds(0.5), 50)
        XCTAssertEqual(tally.percentileMilliseconds(0.9), 90)
        XCTAssertEqual(tally.percentileMilliseconds(0), 10)
        XCTAssertEqual(OCRBenchmarkTally().percentileMilliseconds(0.5), 0)
    }

    func testSummaryLineIsOneKeyValueLine() {
        var tally = OCRBenchmarkTally()
        tally.record(milliseconds: 120, text: "abc", target: nil, blocks: 4, baselineText: "abc", baselineTarget: nil)
        XCTAssertEqual(
            tally.summaryLine(index: 3, options: .standard),
            "OCRBench #03 n=1 avgMs=120.0 p50Ms=120.0 p90Ms=120.0 sim=1.0000 minSim=1.0000 classDiff=0 failed=0 blocks=4 | scale=1.00 lc=on minH=default roi=full bc=on"
        )
    }
}
