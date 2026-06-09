import Foundation

enum AntiTouchGate {
    static let lockDelay: TimeInterval = 3.0

    static func allowsToggle(isExpanded: Bool, isAntiTouchMode: Bool) -> Bool {
        isExpanded || !isAntiTouchMode
    }
}
