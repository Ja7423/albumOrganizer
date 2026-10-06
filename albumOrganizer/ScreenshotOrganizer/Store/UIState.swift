import SwiftUI
import UIKit
import Observation
import ScreenshotKit

/// Navigation and transient UI state shared across screens.
@MainActor
@Observable
final class UIState {
    enum Tab: CaseIterable { case all, folders, tags, search }

    /// Pushed grids from the 資料夾 and 標籤 tabs.
    enum Route: Hashable {
        case folder(UUID)
        case unsorted
        case tag(String)
    }

    enum Sheet: Equatable { case move, tags }
    /// Whether a sheet acts on the batch selection or on the open detail.
    enum SheetContext: Equatable { case batch, detail }

    enum Dialog: Equatable {
        case newFolder(moveAfter: Bool)
        case newTag
    }

    var tab: Tab = .all
    /// Filter chip on the root 截圖 grid.
    var chip: Scope = .all
    var folderPath: [Route] = []
    var tagPath: [Route] = []

    var selecting = false
    var selection: Set<String> = []

    private(set) var detailID: String?

    var sheet: Sheet?
    var sheetContext: SheetContext = .detail
    var dialog: Dialog?

    private(set) var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    static let pushAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.34)
    static let sheetAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)

    func selectTab(_ tab: Tab) {
        self.tab = tab
        folderPath = []
        tagPath = []
        endSelecting()
    }

    func endSelecting() {
        selecting = false
        selection = []
    }

    func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func openDetail(_ id: String) {
        withAnimation(Self.pushAnimation) { detailID = id }
    }

    func closeDetail() {
        withAnimation(Self.pushAnimation) { detailID = nil }
    }

    func present(_ sheet: Sheet, for context: SheetContext) {
        sheetContext = context
        withAnimation(Self.sheetAnimation) { self.sheet = sheet }
    }

    func dismissSheet() {
        withAnimation(Self.sheetAnimation) { sheet = nil }
    }

    /// Screenshot IDs the open sheet acts on.
    var sheetTargets: [String] {
        switch sheetContext {
        case .batch: return Array(selection)
        case .detail: return detailID.map { [$0] } ?? []
        }
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
    }

    func copy(_ text: String, toast message: String) {
        UIPasteboard.general.string = text
        showToast(message)
    }
}
