import Foundation

/// Pure, provider-agnostic watch-tracking rules — kept separate from the persistence
/// model so it's trivially unit-testable and reusable wherever completion needs
/// deciding (player callbacks, continue-watching filtering, future settings toggle).
public enum WatchProgressPolicy {
    public static let completionThreshold: Double = 0.92

    /// Below this many remaining seconds, treat as "credits are rolling" too, even if
    /// the ratio hasn't technically crossed the threshold (protects short intros/outros).
    public static let minimumDurationForRatio: Double = 1

    public static func isCompleted(positionSeconds: Double, durationSeconds: Double) -> Bool {
        guard durationSeconds >= minimumDurationForRatio else { return false }
        return positionSeconds / durationSeconds >= completionThreshold
    }
}
