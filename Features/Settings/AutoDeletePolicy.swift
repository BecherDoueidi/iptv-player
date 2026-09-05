import Foundation

enum AutoDeletePolicy: String, CaseIterable, Identifiable {
    case never, afterOneDay, afterThreeDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never"
        case .afterOneDay: return "After 1 Day"
        case .afterThreeDays: return "After 3 Days"
        }
    }

    /// nil means "don't auto-delete."
    var thresholdDays: Int? {
        switch self {
        case .never: return nil
        case .afterOneDay: return 1
        case .afterThreeDays: return 3
        }
    }
}
