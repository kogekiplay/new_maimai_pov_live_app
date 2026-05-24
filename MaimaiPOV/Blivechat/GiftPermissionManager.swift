import Foundation
import Combine

enum PermissionSource: String, Codable {
    case gift
    case superChat
    case guard
}

struct GiftPermission: Identifiable {
    let id = UUID()
    let uid: String
    let username: String
    let expiresAt: Date
    let source: PermissionSource

    var isExpired: Bool {
        Date() > expiresAt
    }

    var remainingSeconds: TimeInterval {
        max(0, expiresAt.timeIntervalSinceNow)
    }
}

class GiftPermissionManager: ObservableObject {
    @Published var permissions: [String: GiftPermission] = [:]

    var giftDurationMinutes: Int = 30
    var superChatDurationMinutes: Int = 60
    var guardDurationMinutes: Int = 1440

    private var cleanupTimer: Timer?

    init() {
        startCleanupTimer()
    }

    func handleGift(_ gift: GiftMessage) {
        guard gift.isPaidGift else { return }

        let duration = TimeInterval(giftDurationMinutes * 60)
        let expiresAt = Date().addingTimeInterval(duration)

        updatePermission(
            uid: gift.authorName,
            username: gift.authorName,
            expiresAt: expiresAt,
            source: .gift
        )
    }

    func handleSuperChat(_ sc: SuperChatMessage) {
        let duration = TimeInterval(superChatDurationMinutes * 60)
        let expiresAt = Date().addingTimeInterval(duration)

        updatePermission(
            uid: sc.authorName,
            username: sc.authorName,
            expiresAt: expiresAt,
            source: .superChat
        )
    }

    func handleMember(_ member: MemberMessage) {
        let duration = TimeInterval(guardDurationMinutes * 60)
        let expiresAt = Date().addingTimeInterval(duration)

        updatePermission(
            uid: member.authorName,
            username: member.authorName,
            expiresAt: expiresAt,
            source: .guard
        )
    }

    func hasPermission(uid: String) -> Bool {
        guard let permission = permissions[uid] else { return false }
        return !permission.isExpired
    }

    func getPermission(uid: String) -> GiftPermission? {
        guard let permission = permissions[uid], !permission.isExpired else { return nil }
        return permission
    }

    func activePermissions() -> [GiftPermission] {
        permissions.values.filter { !$0.isExpired }
    }

    func cleanupExpired() {
        let expiredKeys = permissions.filter { $0.value.isExpired }.map { $0.key }
        if !expiredKeys.isEmpty {
            for key in expiredKeys {
                permissions.removeValue(forKey: key)
            }
        }
    }

    func clearAll() {
        permissions.removeAll()
    }

    private func updatePermission(uid: String, username: String, expiresAt: Date, source: PermissionSource) {
        if let existing = permissions[uid] {
            if expiresAt > existing.expiresAt {
                permissions[uid] = GiftPermission(
                    uid: uid,
                    username: username,
                    expiresAt: expiresAt,
                    source: source
                )
            }
        } else {
            permissions[uid] = GiftPermission(
                uid: uid,
                username: username,
                expiresAt: expiresAt,
                source: source
            )
        }
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanupExpired()
        }
    }

    deinit {
        cleanupTimer?.invalidate()
    }
}
