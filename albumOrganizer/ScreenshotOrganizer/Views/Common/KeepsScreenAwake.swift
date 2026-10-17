import SwiftUI
import UIKit

extension View {
    /// Keeps the screen from auto-locking while this view is on screen, e.g. while the user watches an import.
    func keepsScreenAwake() -> some View {
        onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
