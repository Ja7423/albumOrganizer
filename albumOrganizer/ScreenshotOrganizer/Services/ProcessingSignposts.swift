import Foundation
import os
import ScreenshotKit

/// Times each processing stage for Instruments (os_signpost, category "processing") and logs one line per run,
/// so the speed of a large import can be measured on a real device.
nonisolated enum ProcessingSignposts {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "albumOrganizer"
    private static let signposter = OSSignposter(subsystem: subsystem, category: "processing")
    private static let log = Logger(subsystem: subsystem, category: "processing")

    /// Wraps one stage of one screenshot, e.g. "loadImage" or "recognize".
    static func measure<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        try signposter.withIntervalSignpost(name, id: signposter.makeSignpostID(), around: body)
    }

    static func logRun(_ tally: ProcessingTally, duration: Duration, width: Int) {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let perMinute = seconds > 0 ? Double(tally.processed) / seconds * 60 : 0
        log.notice("""
        Processed \(tally.processed, privacy: .public) in \(seconds, format: .fixed(precision: 1), privacy: .public)s \
        (\(perMinute, format: .fixed(precision: 0), privacy: .public)/min, width \(width, privacy: .public)): \
        \(tally.classified, privacy: .public) classified, \(tally.unsorted, privacy: .public) unsorted, \
        \(tally.failed, privacy: .public) to retry
        """)
    }
}
