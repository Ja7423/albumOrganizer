import ScreenshotKit
import SwiftUI

/// Sits above the tab bar while a large processing run is under way, one stage at a time, then shows the run's
/// summary briefly. Tapping it opens 處理中, or 未分類 while Apple Intelligence works through it.
struct ProcessingBar: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        let progress = store.processingProgress
        if progress.isVisible {
            Button {
                store.continueInBackground()
                ui.showInFolders(progress.phase == .refining ? .unsorted : .processing)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    switch progress.phase {
                    case let .finished(tally): FinishedContent(tally: tally)
                    case .refining: RunningContent(title: "正在分類截圖", progress: progress)
                    case .recognizing, .idle: RunningContent(title: "正在整理截圖", progress: progress)
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
            .accessibilityHint(progress.phase == .refining ? "查看未分類的截圖" : "查看處理中的截圖")
        }
    }
}

private struct RunningContent: View {
    let title: String
    let progress: ProcessingProgress

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(Palette.text)
            Text(title)
                .font(Typeface.body(14, .semibold))
            Spacer(minLength: 0)
            Text("\(progress.completed.formatted()) / \(progress.total.formatted())")
                .font(Typeface.body(14))
                .foregroundStyle(Palette.neutral700)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

private struct FinishedContent: View {
    let tally: ProcessingTally

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("整理完成").font(Typeface.body(14, .semibold))
                Text(tally.summary)
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.neutral700)
            }
            Spacer(minLength: 0)
        }
    }
}
