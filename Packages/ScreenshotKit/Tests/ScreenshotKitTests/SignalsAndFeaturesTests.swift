import XCTest
import ScreenshotKit

final class SignalsAndFeaturesTests: XCTestCase {
    private func block(_ text: String, x: Double = 0.1, width: Double = 0.8, y: Double = 0.3) -> TextBlock {
        TextBlock(id: 0, text: text, box: NormalizedRect(x: x, y: y, width: width, height: 0.02))
    }

    private func signals(_ lines: String...) -> ScreenshotSignals {
        SignalExtractor.extract(blocks: lines.map { block($0) }, barcodes: [])
    }

    func testDetectsLinksPhonesAddressesAndDates() {
        XCTAssertGreaterThan(signals("詳情見 https://example.com/a").links, 0)
        XCTAssertGreaterThan(signals("官網 shop.com.tw").links, 0)
        XCTAssertGreaterThan(signals("訂位專線 02-2345-6789").phones, 0)
        XCTAssertGreaterThan(signals("手機 0912-345-678").phones, 0)
        XCTAssertGreaterThan(signals("台北市信義區松高路 19 號 B2").addresses, 0)
        XCTAssertGreaterThan(signals("出發日期 2026/10/12").dates, 0)
        XCTAssertGreaterThan(signals("10 月 12 日 開演").dates, 0)
    }

    func testPlainTextHasNoSignals() {
        XCTAssertEqual(signals("今天天氣很好", "我們去散步吧"), ScreenshotSignals())
    }

    func testIDNumbersAreNotPhones() {
        XCTAssertEqual(signals("統一編號 12345678", "AB-12345678").phones, 0)
        XCTAssertGreaterThan(signals("客服 +886 2 2345 6789").phones, 0)
    }

    func testAlternatingBubblesLookLikeChat() {
        let left = { (t: String, y: Double) in self.block(t, x: 0.05, width: 0.4, y: y) }
        let right = { (t: String, y: Double) in self.block(t, x: 0.5, width: 0.45, y: y) }
        let chat = [left("晚餐吃什麼", 0.2), right("火鍋？", 0.3), left("好啊", 0.4), right("七點見", 0.5)]
        XCTAssertTrue(SignalExtractor.extract(blocks: chat, barcodes: []).hasAlternatingBubbles)

        let article = (0..<4).map { block("第 \($0) 段內文", y: 0.2 + Double($0) * 0.1) }
        XCTAssertFalse(SignalExtractor.extract(blocks: article, barcodes: []).hasAlternatingBubbles)
    }

    func testSymbolDensityRisesForCode() {
        XCTAssertGreaterThan(signals("if (x) { return f(y); }").symbolDensity, 0.15)
        XCTAssertEqual(signals("沒有符號的句子").symbolDensity, 0)
    }

    func testFeatureTagsFollowSignals() {
        let s = ScreenshotSignals(links: 1, phones: 0, dates: 2, addresses: 0, barcodes: 1)
        XCTAssertEqual(FeatureDetector.detect(s), [.link, .date, .qrCode])
        XCTAssertEqual(FeatureDetector.detect(ScreenshotSignals()), [])
    }
}
