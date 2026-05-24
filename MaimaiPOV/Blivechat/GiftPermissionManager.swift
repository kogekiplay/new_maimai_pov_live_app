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
}

class GiftPermissionManager: ObservableObject {
    @Published var permissions: [String: GiftPermission] = [:]

    @Published var activePermissionCount: Int = 0

    private static let scPriorityThreshold = 30

    func handleGift(_ gift: GiftMessage) {
        guard gift.isPaidGift else { return }
        addPermission(uid: gift.authorName, username: gift.authorName, source: .gift, normalChances: 1, priorityChances: 0)
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
        return permission.remainingChances > 0 || permission.priorityChances > 0
    }

    func hasPriorityPermission(uid: String) -> Bool {
        guard let permission = permissions[uid] else { return false }
        return permission.priorityChances > 0
    }

    func getPermission(uid: String) -> GiftPermission? {
        guard let permission = permissions[uid], (permission.remainingChances > 0 || permission.priorityChances > 0) else { return nil }
        return permission
    }

    func consumePermission(uid: String) -> ConsumedPermissionType? {
        guard var permission = permissions[uid] else { return nil }
        if permission.priorityChances > 0 {
            permission.priorityChances -= 1
            if permission.remainingChances <= 0 && permission.priorityChances <= 0 {
                permissions.removeValue(forKey: uid)
            } else {
                permissions[uid] = permission
            }
            updateActiveCount()
            return .priority
        } else if permission.remainingChances > 0 {
            permission.remainingChances -= 1
            if permission.remainingChances <= 0 && permission.priorityChances <= 0 {
                permissions.removeValue(forKey: uid)
            } else {
                permissions[uid] = permission
            }
            updateActiveCount()
            return .normal
        }
        return nil
    }

    func consumePriorityPermission(uid: String) -> Bool {
        guard var permission = permissions[uid], permission.priorityChances > 0 else { return false }
        permission.priorityChances -= 1
        if permission.remainingChances <= 0 && permission.priorityChances <= 0 {
            permissions.removeValue(forKey: uid)
        } else {
            permissions[uid] = permission
        }
        updateActiveCount()
        return true
    }

    func consumeNormalPermission(uid: String) -> Bool {
        guard var permission = permissions[uid], permission.remainingChances > 0 else { return false }
        permission.remainingChances -= 1
        if permission.remainingChances <= 0 && permission.priorityChances <= 0 {
            permissions.removeValue(forKey: uid)
        } else {
            permissions[uid] = permission
        }
        updateActiveCount()
        return true
    }

    func activePermissions() -> [GiftPermission] {
        permissions.values.filter { $0.remainingChances > 0 || $0.priorityChances > 0 }
    }

    func clearAll() {
        permissions.removeAll()
        updateActiveCount()
    }

    func addTestPermission(uid: String, username: String) {
        addPermission(uid: uid, username: username, source: .gift, normalChances: 99, priorityChances: 0)
    }

    func addTestPriorityPermission(uid: String, username: String) {
        addPermission(uid: uid, username: username, source: .superChat, normalChances: 0, priorityChances: 99)
    }

    private func addPermission(uid: String, username: String, source: PermissionSource, normalChances: Int, priorityChances: Int) {
        if var existing = permissions[uid] {
            existing.remainingChances += normalChances
            existing.priorityChances += priorityChances
            permissions[uid] = existing
        } else {
            permissions[uid] = GiftPermission(
                uid: uid,
                username: username,
                remainingChances: normalChances,
                priorityChances: priorityChances
            )
        }
        updateActiveCount()
    }

    private func updateActiveCount() {
        activePermissionCount = permissions.values.filter { $0.remainingChances > 0 || $0.priorityChances > 0 }.count
    }
}
