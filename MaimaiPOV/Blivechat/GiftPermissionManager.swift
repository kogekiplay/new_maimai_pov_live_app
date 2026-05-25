import Foundation
import Combine

enum PermissionSource: String, Codable {
    case gift
    case superChat
    case guardMember
}

enum ConsumedPermissionType {
    case priority
    case normal
}

struct GiftPermission: Identifiable {
    let id = UUID()
    let uid: String
    let username: String
    var remainingChances: Int
    var priorityChances: Int
    var expiryDate: Date
    var accumulatedCoin: Int

    var isExpired: Bool {
        return Date() > expiryDate
    }
}

class GiftPermissionManager: ObservableObject {
    @Published var permissions: [String: GiftPermission] = [:]
    @Published var activePermissionCount: Int = 0

    private static let scPriorityThreshold = 30
    private static let giftNormalThreshold = 1000
    private static let giftPriorityThreshold = 30000

    func handleGift(_ gift: GiftMessage) {
        guard gift.isPaidGift else { return }
        let uid = gift.authorName
        let coin = gift.totalCoin
        let newExpiry = expiryDate(for: .gift)

        if var existing = permissions[uid] {
            if existing.isExpired {
                existing.accumulatedCoin = coin
                existing.remainingChances = 0
                existing.priorityChances = 0
                existing.expiryDate = newExpiry
            } else {
                existing.accumulatedCoin += coin
                existing.expiryDate = max(existing.expiryDate, newExpiry)
            }
            updateChancesFromAccumulatedCoin(&existing)
            permissions[uid] = existing
        } else {
            var perm = GiftPermission(
                uid: uid,
                username: uid,
                remainingChances: 0,
                priorityChances: 0,
                expiryDate: newExpiry,
                accumulatedCoin: coin
            )
            updateChancesFromAccumulatedCoin(&perm)
            permissions[uid] = perm
        }
        updateActiveCount()
    }

    func handleSuperChat(_ sc: SuperChatMessage) {
        if sc.price >= Self.scPriorityThreshold {
            addPermission(uid: sc.authorName, username: sc.authorName, source: .superChat, normalChances: 0, priorityChances: 1)
        } else {
            addPermission(uid: sc.authorName, username: sc.authorName, source: .superChat, normalChances: 1, priorityChances: 0)
        }
    }

    func handleMember(_ member: MemberMessage) {
        addPermission(uid: member.authorName, username: member.authorName, source: .guardMember, normalChances: 1, priorityChances: 0)
    }

    func hasPermission(uid: String) -> Bool {
        guard let permission = permissions[uid] else { return false }
        guard !permission.isExpired else {
            permissions.removeValue(forKey: uid)
            updateActiveCount()
            return false
        }
        return permission.remainingChances > 0 || permission.priorityChances > 0
    }

    func hasPriorityPermission(uid: String) -> Bool {
        guard let permission = permissions[uid] else { return false }
        guard !permission.isExpired else {
            permissions.removeValue(forKey: uid)
            updateActiveCount()
            return false
        }
        return permission.priorityChances > 0
    }

    func getPermission(uid: String) -> GiftPermission? {
        guard let permission = permissions[uid] else { return nil }
        guard !permission.isExpired else {
            permissions.removeValue(forKey: uid)
            updateActiveCount()
            return nil
        }
        return (permission.remainingChances > 0 || permission.priorityChances > 0) ? permission : nil
    }

    func consumePermission(uid: String) -> ConsumedPermissionType? {
        guard var permission = permissions[uid] else { return nil }
        guard !permission.isExpired else {
            permissions.removeValue(forKey: uid)
            updateActiveCount()
            return nil
        }
        if permission.priorityChances > 0 {
            permission.priorityChances = 0
            permission.remainingChances = 0
            permission.accumulatedCoin = 0
            permissions.removeValue(forKey: uid)
            updateActiveCount()
            return .priority
        } else if permission.remainingChances > 0 {
            permission.remainingChances = 0
            permission.priorityChances = 0
            permission.accumulatedCoin = 0
            permissions.removeValue(forKey: uid)
            updateActiveCount()
            return .normal
        }
        return nil
    }

    func consumePriorityPermission(uid: String) -> Bool {
        guard var permission = permissions[uid], permission.priorityChances > 0 else { return false }
        guard !permission.isExpired else {
            permissions.removeValue(forKey: uid)
            updateActiveCount()
            return false
        }
        permission.priorityChances = 0
        permission.remainingChances = 0
        permission.accumulatedCoin = 0
        permissions.removeValue(forKey: uid)
        updateActiveCount()
        return true
    }

    func consumeNormalPermission(uid: String) -> Bool {
        guard var permission = permissions[uid], permission.remainingChances > 0 else { return false }
        guard !permission.isExpired else {
            permissions.removeValue(forKey: uid)
            updateActiveCount()
            return false
        }
        permission.remainingChances = 0
        permission.priorityChances = 0
        permission.accumulatedCoin = 0
        permissions.removeValue(forKey: uid)
        updateActiveCount()
        return true
    }

    func activePermissions() -> [GiftPermission] {
        cleanExpiredPermissions()
        return permissions.values.filter { $0.remainingChances > 0 || $0.priorityChances > 0 }
    }

    func clearAll() {
        permissions.removeAll()
        updateActiveCount()
    }

    func cleanExpiredPermissions() {
        let expiredKeys = permissions.filter { $0.value.isExpired }.map { $0.key }
        for key in expiredKeys {
            permissions.removeValue(forKey: key)
        }
        if !expiredKeys.isEmpty {
            updateActiveCount()
        }
    }

    func addTestPermission(uid: String, username: String) {
        addPermission(uid: uid, username: username, source: .gift, normalChances: 1, priorityChances: 0)
    }

    func addTestPriorityPermission(uid: String, username: String) {
        addPermission(uid: uid, username: username, source: .superChat, normalChances: 0, priorityChances: 1)
    }

    private func expiryDate(for source: PermissionSource) -> Date {
        let durationMinutes: Int
        switch source {
        case .gift:
            durationMinutes = Config.giftDurationMinutes
        case .superChat:
            durationMinutes = Config.superChatDurationMinutes
        case .guardMember:
            durationMinutes = Config.guardDurationMinutes
        }
        return Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    private func updateChancesFromAccumulatedCoin(_ perm: inout GiftPermission) {
        if perm.accumulatedCoin >= Self.giftPriorityThreshold {
            perm.priorityChances = 1
            perm.remainingChances = 0
        } else if perm.accumulatedCoin >= Self.giftNormalThreshold {
            perm.remainingChances = 1
            perm.priorityChances = 0
        } else {
            perm.remainingChances = 0
            perm.priorityChances = 0
        }
    }

    func addPermission(uid: String, username: String, source: PermissionSource, normalChances: Int, priorityChances: Int) {
        let newExpiry = expiryDate(for: source)
        if var existing = permissions[uid] {
            if existing.isExpired {
                existing.remainingChances = min(normalChances, 1)
                existing.priorityChances = min(priorityChances, 1)
                existing.expiryDate = newExpiry
                existing.accumulatedCoin = 0
            } else {
                if normalChances > 0 { existing.remainingChances = 1 }
                if priorityChances > 0 { existing.priorityChances = 1 }
                existing.expiryDate = max(existing.expiryDate, newExpiry)
            }
            permissions[uid] = existing
        } else {
            permissions[uid] = GiftPermission(
                uid: uid,
                username: username,
                remainingChances: min(normalChances, 1),
                priorityChances: min(priorityChances, 1),
                expiryDate: newExpiry,
                accumulatedCoin: 0
            )
        }
        updateActiveCount()
    }

    private func updateActiveCount() {
        activePermissionCount = permissions.values.filter { !$0.isExpired && ($0.remainingChances > 0 || $0.priorityChances > 0) }.count
    }
}
