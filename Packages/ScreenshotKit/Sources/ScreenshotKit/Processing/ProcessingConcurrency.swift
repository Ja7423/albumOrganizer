import Foundation

/// How many screenshots to process at once. A hot or power-saving device gets one, since a throttled
/// CPU makes parallel work slower, not faster.
public enum ProcessingConcurrency {
    /// Vision runs text recognition one image at a time, so a second worker only overlaps image loading
    /// with recognition; more add heat and memory without speed (measured on device, 2026-10-15).
    public static let normalWidth = 2

    public static func width(thermalState: ProcessInfo.ThermalState, isLowPowerModeEnabled: Bool) -> Int {
        guard !isLowPowerModeEnabled else { return 1 }
        switch thermalState {
        case .serious, .critical: return 1
        default: return normalWidth
        }
    }
}
