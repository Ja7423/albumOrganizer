import Foundation

/// How alike two recognized texts are: 1 − (character edit distance ÷ the longer text's length).
/// 1 means identical, 0 means nothing in common; two empty texts count as identical.
public enum TextSimilarity {
    public static func ratio(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs), b = Array(rhs)
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(editDistance(a, b)) / Double(longest)
    }

    /// Levenshtein distance over characters. The shared prefix and suffix are skipped first, which keeps
    /// near-identical OCR results (the usual case) cheap.
    public static func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        var start = 0
        while start < lhs.count, start < rhs.count, lhs[start] == rhs[start] {
            start += 1
        }
        var endA = lhs.count, endB = rhs.count
        while endA > start, endB > start, lhs[endA - 1] == rhs[endB - 1] {
            endA -= 1
            endB -= 1
        }
        let a = lhs[start ..< endA], b = rhs[start ..< endB]
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var previous = Array(0 ... b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for (i, charA) in a.enumerated() {
            current[0] = i + 1
            for (j, charB) in b.enumerated() {
                let substitution = previous[j] + (charA == charB ? 0 : 1)
                current[j + 1] = min(substitution, previous[j + 1] + 1, current[j] + 1)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

/// One variant's results over the benchmark set, compared with the baseline run on the same screenshots.
public struct OCRBenchmarkTally: Equatable, Sendable {
    public private(set) var count = 0
    public private(set) var failures = 0
    public private(set) var durations: [Double] = []
    public private(set) var similaritySum = 0.0
    public private(set) var minimumSimilarity = 1.0
    public private(set) var classificationDifferences = 0
    public private(set) var blockCount = 0

    public init() {}

    /// Adds one screenshot. `nil` text means this variant's recognition failed.
    public mutating func record(
        milliseconds: Double,
        text: String?,
        target: ClassificationTarget?,
        blocks: Int,
        baselineText: String,
        baselineTarget: ClassificationTarget?
    ) {
        count += 1
        guard let text else {
            failures += 1
            return
        }
        durations.append(milliseconds)
        let similarity = TextSimilarity.ratio(baselineText, text)
        similaritySum += similarity
        minimumSimilarity = min(minimumSimilarity, similarity)
        blockCount += blocks
        if target != baselineTarget { classificationDifferences += 1 }
    }

    public var averageMilliseconds: Double {
        durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
    }

    /// The `p`th percentile (0…1) of the per-screenshot times, nearest rank.
    public func percentileMilliseconds(_ p: Double) -> Double {
        guard !durations.isEmpty else { return 0 }
        let sorted = durations.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    public var averageSimilarity: Double {
        durations.isEmpty ? 0 : similaritySum / Double(durations.count)
    }

    /// One tab-free, `key=value` line per variant, so runs can be pasted side by side and diffed.
    public func summaryLine(index: Int, options: RecognitionOptions) -> String {
        String(
            format: "OCRBench #%02d n=%d avgMs=%.1f p50Ms=%.1f p90Ms=%.1f sim=%.4f minSim=%.4f classDiff=%d failed=%d blocks=%d",
            index, count, averageMilliseconds, percentileMilliseconds(0.5), percentileMilliseconds(0.9),
            averageSimilarity, minimumSimilarity, classificationDifferences, failures, blockCount
        ) + " | " + options.label
    }
}
