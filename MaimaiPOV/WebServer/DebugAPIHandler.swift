import Foundation
import Swifter

class DebugAPIHandler {
    weak var pipeline: LivePipelineManager?

    func getPermissions() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)
        var result: [[String: Any]] = []

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                sem.signal()
                return
            }
            let perms = pipeline.giftPermissionManager.activePermissions()
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"

            for perm in perms {
                result.append([
                    "uid": perm.uid,
                    "username": perm.username,
                    "remainingChances": perm.remainingChances,
                    "priorityChances": perm.priorityChances,
                    "accumulatedCoin": perm.accumulatedCoin,
                    "expiryDate": formatter.string(from: perm.expiryDate),
                    "isExpired": perm.isExpired
                ])
            }
            sem.signal()
        }

        sem.wait()
        return .ok(.json(["permissions": result]))
    }

    func addPermission(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let uid = body["uid"] as? String else {
            return .badRequest(.text("Missing 'uid'"))
        }

        let username = body["username"] as? String ?? uid
        let normalChances = body["normalChances"] as? Int ?? 1
        let priorityChances = body["priorityChances"] as? Int ?? 0
        let sourceStr = body["source"] as? String ?? "gift"
        let source = PermissionSource(rawValue: sourceStr) ?? .gift

        let sem = DispatchSemaphore(value: 0)

        DispatchQueue.main.async { [weak self] in
            self?.pipeline?.giftPermissionManager.addPermission(
                uid: uid, username: username, source: source,
                normalChances: normalChances, priorityChances: priorityChances
            )
            sem.signal()
        }

        sem.wait()
        return getPermissions()
    }

    func clearPermissions() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)

        DispatchQueue.main.async { [weak self] in
            self?.pipeline?.giftPermissionManager.clearAll()
            sem.signal()
        }

        sem.wait()
        return .ok(.json(["success": true]))
    }

    func simulateGift(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let authorName = body["authorName"] as? String else {
            return .badRequest(.text("Missing 'authorName'"))
        }

        let totalCoin = body["totalCoin"] as? Int ?? 1000

        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any] = ["success": true]

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result = ["success": false, "error": "Pipeline not available"]
                sem.signal()
                return
            }

            let gift = GiftMessage(
                fromDict: [
                    "id": UUID().uuidString,
                    "avatarUrl": "",
                    "timestamp": Int(Date().timeIntervalSince1970),
                    "authorName": authorName,
                    "totalCoin": totalCoin,
                    "totalFreeCoin": 0,
                    "giftName": "测试礼物",
                    "num": 1,
                    "privilegeType": 0,
                    "medalLevel": 0
                ]
            )

            if let gift = gift {
                pipeline.giftPermissionManager.handleGift(gift)
                result = [
                    "success": true,
                    "isPaidGift": gift.isPaidGift,
                    "authorName": authorName
                ]
            } else {
                result = ["success": false, "error": "Failed to create GiftMessage"]
            }

            sem.signal()
        }

        sem.wait()
        return .ok(.json(result))
    }

    func simulateSC(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let authorName = body["authorName"] as? String else {
            return .badRequest(.text("Missing 'authorName'"))
        }

        let price = body["price"] as? Int ?? 30
        let content = body["content"] as? String ?? ""

        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any] = ["success": true]

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result = ["success": false, "error": "Pipeline not available"]
                sem.signal()
                return
            }

            let sc = SuperChatMessage(
                fromDict: [
                    "id": UUID().uuidString,
                    "avatarUrl": "",
                    "timestamp": Int(Date().timeIntervalSince1970),
                    "authorName": authorName,
                    "price": price,
                    "content": content,
                    "translation": "",
                    "privilegeType": 0,
                    "medalLevel": 0
                ]
            )

            if let sc = sc {
                pipeline.giftPermissionManager.handleSuperChat(sc)

                if !content.isEmpty {
                    pipeline.handleSuperChatForSongRequest(sc)
                }

                result = [
                    "success": true,
                    "isPrioritySC": price >= 30,
                    "authorName": authorName,
                    "price": price,
                    "content": content
                ]
            } else {
                result = ["success": false, "error": "Failed to create SuperChatMessage"]
            }

            sem.signal()
        }

        sem.wait()
        return .ok(.json(result))
    }

    func simulateMember(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let authorName = body["authorName"] as? String else {
            return .badRequest(.text("Missing 'authorName'"))
        }

        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any] = ["success": true]

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result = ["success": false, "error": "Pipeline not available"]
                sem.signal()
                return
            }

            let member = MemberMessage(
                fromDict: [
                    "id": UUID().uuidString,
                    "avatarUrl": "",
                    "timestamp": Int(Date().timeIntervalSince1970),
                    "authorName": authorName,
                    "privilegeType": 3,
                    "giftName": "舰长",
                    "num": 1,
                    "totalCoin": 198000,
                    "price": 198
                ]
            )

            if let member = member {
                pipeline.giftPermissionManager.handleMember(member)
                result = [
                    "success": true,
                    "authorName": authorName
                ]
            } else {
                result = ["success": false, "error": "Failed to create MemberMessage"]
            }

            sem.signal()
        }

        sem.wait()
        return .ok(.json(result))
    }
}
