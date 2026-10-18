import ScreenshotKit

/// Deleting the batch selection or the open screenshot: asks with the delete dialog unless a choice
/// is remembered, then reports the result in a toast.
@MainActor
struct ShotDeletion {
    let store: LibraryStore
    let ui: UIState
    let settings: DeletionSettings

    /// The trash button: runs the remembered method, or opens the dialog.
    func request(for context: UIState.SheetContext) {
        guard let method = settings.preference.method else {
            ui.dialog = .deleteShots(context)
            return
        }
        Task { await perform(method, for: context, remembering: false) }
    }

    /// Deletes the targets of `context`. A cancelled or failed delete changes nothing, including the
    /// remembered choice, and keeps the selection so the user can try again.
    func perform(_ method: DeletionMethod, for context: UIState.SheetContext, remembering: Bool) async {
        let ids = ui.targets(for: context)
        guard !ids.isEmpty else { return }
        let subject: DeletionSubject = context == .batch ? .selection(count: ids.count) : .current

        switch await store.delete(ids, method: method) {
        case .cancelled:
            ui.showToast(DeletionCopy.cancelled)
        case .failed:
            ui.showToast(DeletionCopy.failed)
        case .deleted:
            if remembering { settings.preference = .always(method) }
            if context == .batch { ui.endSelecting() }
            ui.showToast(DeletionCopy.summary(method, subject: subject, isRemembered: remembering))
        }
    }
}
