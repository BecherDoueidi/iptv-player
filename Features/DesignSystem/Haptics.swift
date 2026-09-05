import UIKit

/// Direct UIKit feedback generator calls rather than SwiftUI's `.sensoryFeedback`
/// modifier — simpler to reason about at the exact point of action, and doesn't need
/// an Equatable trigger value threaded through every call site.
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
