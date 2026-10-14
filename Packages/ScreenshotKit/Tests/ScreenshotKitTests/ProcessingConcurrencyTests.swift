import ScreenshotKit
import XCTest

final class ProcessingConcurrencyTests: XCTestCase {
    func testCoolDeviceUsesFullWidth() {
        XCTAssertEqual(ProcessingConcurrency.width(thermalState: .nominal, isLowPowerModeEnabled: false), ProcessingConcurrency.normalWidth)
        XCTAssertEqual(ProcessingConcurrency.width(thermalState: .fair, isLowPowerModeEnabled: false), ProcessingConcurrency.normalWidth)
    }

    func testHotDeviceDropsToOne() {
        XCTAssertEqual(ProcessingConcurrency.width(thermalState: .serious, isLowPowerModeEnabled: false), 1)
        XCTAssertEqual(ProcessingConcurrency.width(thermalState: .critical, isLowPowerModeEnabled: false), 1)
    }

    func testLowPowerModeDropsToOne() {
        XCTAssertEqual(ProcessingConcurrency.width(thermalState: .nominal, isLowPowerModeEnabled: true), 1)
    }
}
