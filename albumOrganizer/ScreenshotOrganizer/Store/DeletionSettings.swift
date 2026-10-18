import Foundation
import Observation
import ScreenshotKit

/// The remembered delete choice, shared by the batch bar and the detail page and changed in 設定.
@MainActor
@Observable
final class DeletionSettings {
    var preference: DeletionPreference {
        didSet { defaults.set(preference.storedValue, forKey: Self.key) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private static let key = "deletionPreference"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preference = DeletionPreference(storedValue: defaults.string(forKey: Self.key))
    }
}
