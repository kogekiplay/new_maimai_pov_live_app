import Foundation
import Swifter

class DebugAPIHandler {
    weak var pipeline: LivePipelineManager?

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
                let coinValue = max(gift.totalCoin, gift.totalFreeCoin)
                if coinValue > 0 {
                    pipeline.songCardManager.userGiftPool[authorName, default: 0] += coinValue
                    if let index = pipeline.songCardManager.findSongIndex(byName: authorName) {
                        pipeline.songCardManager.updateGiftValue(name: authorName, delta: coinValue)
                        let lockedEnd = pipeline.songCardManager.lockedEndIndex
                        if index >= lockedEnd {
                            pipeline.songCardManager.reorderQueueByGiftValue()
                            pipeline.reorderRightPanel()
                        }
                    }
                    pipeline.refreshLeftPanel()
                    pipeline.postMarquee("🎁 感谢 \(authorName) 送出 \(gift.giftName) ×\(gift.num)", type: .gift)
                }

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
                pipeline.handleSuperChatForSongRequest(sc)

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
                let coinValue = 198 * 1000
                pipeline.songCardManager.userGiftPool[authorName, default: 0] += coinValue
                if let index = pipeline.songCardManager.findSongIndex(byName: authorName) {
                    pipeline.songCardManager.updateGiftValue(name: authorName, delta: coinValue)
                    let lockedEnd = pipeline.songCardManager.lockedEndIndex
                    if index >= lockedEnd {
                        pipeline.songCardManager.reorderQueueByGiftValue()
                        pipeline.reorderRightPanel()
                    }
                }
                pipeline.refreshLeftPanel()
                pipeline.postMarquee("⭐ \(authorName) 上舰了!", type: .member)

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

    func simulateDanmaku(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let authorName = body["authorName"] as? String,
              let content = body["content"] as? String else {
            return .badRequest(.text("Missing 'authorName' or 'content'"))
        }

        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any] = ["success": true]

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result = ["success": false, "error": "Pipeline not available"]
                sem.signal()
                return
            }

            let danmaku = DanmakuMessage(
                fromArray: [
                    "",
                    Int(Date().timeIntervalSince1970),
                    authorName,
                    0,
                    content,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    UUID().uuidString,
                    "",
                    0,
                    0,
                    0,
                    0,
                    ""
                ]
            )

            if let danmaku = danmaku {
                pipeline.handleDanmakuForSongRequest(danmaku)
                result = [
                    "success": true,
                    "authorName": authorName,
                    "content": content
                ]
            } else {
                result = ["success": false, "error": "Failed to create DanmakuMessage"]
            }

            sem.signal()
        }

        sem.wait()
        return .ok(.json(result))
    }

    func getGiftPool() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)
        var result: [[String: Any]] = []

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                sem.signal()
                return
            }
            let pool = pipeline.songCardManager.userGiftPool
            for (name, value) in pool.sorted(by: { $0.value > $1.value }) {
                result.append([
                    "name": name,
                    "giftValue": value
                ])
            }
            sem.signal()
        }

        sem.wait()
        let response: [String: Any] = ["giftPool": result]
        return .ok(.json(response))
    }

    func simulateMarquee(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let text = body["text"] as? String else {
            return .badRequest(.text("Missing 'text'"))
        }

        let typeRaw = body["type"] as? Int ?? 0
        let type = MarqueeItem.MarqueeItemType(rawValue: typeRaw) ?? .songSuccess

        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any] = ["success": true]

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result = ["success": false, "error": "Pipeline not available"]
                sem.signal()
                return
            }

            pipeline.postMarquee(text, type: type)
            result = [
                "success": true,
                "text": text,
                "type": typeRaw
            ]
            sem.signal()
        }

        sem.wait()
        return .ok(.json(result))
    }
}
