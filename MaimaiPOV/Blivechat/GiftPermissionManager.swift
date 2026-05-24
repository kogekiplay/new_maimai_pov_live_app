import Foundation
import Combine

enum PermissionSource: String, Codable {
    case gift
    case superChat
    case guardMember
}

struct GiftPermission: Identifiable {
    let id = UUID()
    let uid: String
    let username: String
    let source: PermissionSource
    var remainingChances: Int
}

class GiftPermissionManager: ObservableObject {
    @Published var permissions: [String: GiftPermission] = [:]

    @Published var activePermissionCount: Int = 0

    func handleGift(_ gift: GiftMessage) {
        guard gift.isPaidGift else { return }
        addPermission(uid: gift.authorName, username: gift.authorName, source: .gift, chances: 1)
    }

    func handleSuperChat(_ sc: SuperChatMessage) {
        addPermission(uid: sc.authorName, username: sc.authorName, source: .superChat, chances: 1)
    }

    func handleMember(_ member: MemberMessage) {
        addPermission(uid: member.authorName, username: member.authorName, source: .guardMember, chances: 1)
    }

    func hasPermission(uid: String) -> Bool {
        guard let permission = permissions[uid] else { return false }
        return permission.remainingChances > 0
    }

    func getPermission(uid: String) -> GiftPermission? {
        guard let permission = permissions[uid], permission.remainingChances > 0 else { return nil }
        return permission
    }

    func consumePermission(uid: String) -> Bool {
        guard var permission = permissions[uid], permission.remainingChances > 0 else { return false }
        permission.remainingChances -= 1
        if permission.remainingChances <= 0 {
            permissions.removeValue(forKey: uid)
        } else {
            permissions[uid] = permission
        }
        updateActiveCount()
        return true
    }

    func activePermissions() -> [GiftPermission] {
        permissions.values.filter { $0.remainingChances > 0 }
    }

    func clearAll() {
        permissions.removeAll()
        updateActiveCount()
    }

    private func addPermission(uid: String, username: String, source: PermissionSource, chances: Int) {
        if var existing = permissions[uid] {
            existing.remainingChances += chances
            permissions[uid] = existing
        } else {
            permissions[uid] = GiftPermission(
                uid: uid,
                username: username,
                source: source,
                remainingChances: chances
            )
        }
        updateActiveCount()
    }

    private func updateActiveCount() {
        activePermissionCount = permissions.values.filter { $0.remainingChances > 0 }.count
    }
}
