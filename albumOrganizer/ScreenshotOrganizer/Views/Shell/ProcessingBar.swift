import ScreenshotKit
import SwiftUI

/// Sits above the tab bar while a large processing run is under way, then shows the run's summary briefly.
/// Tapping it opens 處理中.
struct ProcessingBar: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        let progress = store.processingProgress
        if progress.isVisible {
            Button { ui.showProcessing() } label: {
                VStack(alignment: .leading, spacing: 8) {
                    switch progress.phase {
                    case let .finished(tally): FinishedContent(tally: tally)
                    case .running, .idle: RunningContent(progress: progress)
                    }
                    ProgressLine(fraction: progress.fraction, height: 3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.neutral100).shadowMD())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityHint("查看處理中的截圖")
        }
    }
}

private struct RunningContent: View {
    let progress: ProcessingProgress

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(Palette.text)
            Text("正在整理截圖")
                .font(Typeface.body(14, .semibold))
            Spacer(minLength: 0)
            Text("\(progress.processed.formatted()) / \(progress.total.formatted())")
                .font(Typeface.body(14))
                .foregroundStyle(Palette.neutral700)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

private struct FinishedContent: View {
    let tally: ProcessingTally

    private var summary: String {
        let placed = "已分類 \(tally.classified.formatted()) 張，未分類 \(tally.unsorted.formatted()) 張"
        return tally.failed > 0 ? "\(placed)（\(tally.failed.formatted()) 張稍後重試）" : placed
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("整理完成").font(Typeface.body(14, .semibold))
                Text(summary)
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.neutral700)
            }
            Spacer(minLength: 0)
        }
    }
}
