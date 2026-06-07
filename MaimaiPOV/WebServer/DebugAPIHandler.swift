import Foundation
import Swifter

final class DebugAPIHandler: @unchecked Sendable {
    weak var pipeline: LivePipelineManager?

    func simulateGift(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let authorName = body["authorName"] as? String else {
            return .badRequest(.text("Missing 'authorName'"))
        }

        let totalCoin = body["totalCoin"] as? Int ?? 1000

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result.set(["success": false, "error": "Pipeline not available"])
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
                        _ = pipeline.songCardManager.updateGiftValue(name: authorName, delta: coinValue)
                        let lockedEnd = pipeline.songCardManager.lockedEndIndex
                        if index >= lockedEnd {
                            pipeline.songCardManager.reorderQueueByGiftValue()
                        }
                    } else {
                        pipeline.scheduleRefreshLeftPanel()
                        pipeline.songCardManager.scheduleSave()
                    }
                    let prefix = "🎁 感谢 \(authorName) 送出 \(gift.giftName)"
                    pipeline.postMarquee("\(prefix) ×\(gift.num)", type: .gift, mergeKey: "gift_\(authorName)_\(gift.giftName)", mergeCount: gift.num, textPrefix: prefix)
                    pipeline.debug.log("[礼物] \(authorName) 送出 \(gift.giftName) ×\(gift.num) (\(coinValue)币)")
                }

                result.set([
                    "success": true,
                    "isPaidGift": gift.isPaidGift,
                    "authorName": authorName
                ])
            } else {
                result.set(["success": false, "error": "Failed to create GiftMessage"])
            }

            sem.signal()
        }

        sem.wait()
        return .ok(.json(result.get()))
    }

    func simulateSC(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let authorName = body["authorName"] as? String else {
            return .badRequest(.text("Missing 'authorName'"))
        }

        let price = body["price"] as? Int ?? 30
        let content = body["content"] as? String ?? ""

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result.set(["success": false, "error": "Pipeline not available"])
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

                result.set([
                    "success": true,
                    "isPrioritySC": price >= 30,
                    "authorName": authorName,
                    "price": price,
                    "content": content
                ])
            } else {
                result.set(["success": false, "error": "Failed to create SuperChatMessage"])
            }

            sem.signal()
        }

        sem.wait()
        return .ok(.json(result.get()))
    }

    func simulateMember(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let authorName = body["authorName"] as? String else {
            return .badRequest(.text("Missing 'authorName'"))
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result.set(["success": false, "error": "Pipeline not available"])
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

            if member != nil {
                let coinValue = 198 * 1000
                pipeline.songCardManager.userGiftPool[authorName, default: 0] += coinValue
                if let index = pipeline.songCardManager.findSongIndex(byName: authorName) {
                    _ = pipeline.songCardManager.updateGiftValue(name: authorName, delta: coinValue)
                    let lockedEnd = pipeline.songCardManager.lockedEndIndex
                    if index >= lockedEnd {
                        pipeline.songCardManager.reorderQueueByGiftValue()
                    }
                } else {
                    pipeline.scheduleRefreshLeftPanel()
                    pipeline.songCardManager.scheduleSave()
                }
                pipeline.postMarquee("⭐ \(authorName) 上舰了!", type: .member)
                pipeline.debug.log("[上舰] \(authorName) 上舰了!")

                result.set([
                    "success": true,
                    "authorName": authorName
                ])
            } else {
                result.set(["success": false, "error": "Failed to create MemberMessage"])
            }

            sem.signal()
        }

        sem.wait()
        return .ok(.json(result.get()))
    }

    func simulateDanmaku(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let authorName = body["authorName"] as? String,
              let content = body["content"] as? String else {
            return .badRequest(.text("Missing 'authorName' or 'content'"))
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result.set(["success": false, "error": "Pipeline not available"])
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
                result.set([
                    "success": true,
                    "authorName": authorName,
                    "content": content
                ])
            } else {
                result.set(["success": false, "error": "Failed to create DanmakuMessage"])
            }

            sem.signal()
        }

        sem.wait()
        return .ok(.json(result.get()))
    }

    func getGiftPool() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[[String: Any]]>([])

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                sem.signal()
                return
            }
            let pool = pipeline.songCardManager.userGiftPool
            let rows = pool.sorted(by: { $0.value > $1.value }).map { name, value in
                [
                    "name": name,
                    "giftValue": value
                ]
            }
            result.set(rows)
            sem.signal()
        }

        sem.wait()
        let response: [String: Any] = ["giftPool": result.get()]
        return .ok(.json(response))
    }

    func simulateMarquee(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let text = body["text"] as? String else {
            return .badRequest(.text("Missing 'text'"))
        }

        let typeRaw = body["type"] as? Int ?? 0
        let type = MarqueeItem.MarqueeItemType(rawValue: typeRaw) ?? .songSuccess
        let mergeKey = body["mergeKey"] as? String
        let mergeCount = body["mergeCount"] as? Int ?? 1
        let textPrefix = body["textPrefix"] as? String

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result.set(["success": false, "error": "Pipeline not available"])
                sem.signal()
                return
            }

            pipeline.postMarquee(text, type: type, mergeKey: mergeKey, mergeCount: mergeCount, textPrefix: textPrefix)
            result.set([
                "success": true,
                "text": text,
                "type": typeRaw,
                "mergeKey": mergeKey ?? NSNull(),
                "mergeCount": mergeCount
            ])
            sem.signal()
        }

        sem.wait()
        return .ok(.json(result.get()))
    }

    func simulateBattery(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any] else {
            return .badRequest(.text("Invalid JSON body"))
        }

        let level = body["level"] as? Int

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result.set(["success": false, "error": "Pipeline not available"])
                sem.signal()
                return
            }

            pipeline.deviceStatusManager?.setSimulatedBatteryLevel(level)
            result.set([
                "success": true,
                "simulatedLevel": level ?? NSNull(),
                "actualLevel": pipeline.deviceStatusManager?.batteryLevel ?? -1
            ])
            sem.signal()
        }

        sem.wait()
        return .ok(.json(result.get()))
    }

    func setExpirationTimeout(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let timeout = body["timeout"] as? Int else {
            return .badRequest(.text("Missing 'timeout' (seconds)"))
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result.set(["success": false, "error": "Pipeline not available"])
                sem.signal()
                return
            }

            pipeline.songCardManager.expirationTimeout = TimeInterval(timeout)
            result.set([
                "success": true,
                "expirationTimeout": timeout
            ])
            sem.signal()
        }

        sem.wait()
        return .ok(.json(result.get()))
    }

    func triggerExpirationCheck(request: HttpRequest) -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        DispatchQueue.main.async { [weak self] in
            guard let pipeline = self?.pipeline else {
                result.set(["success": false, "error": "Pipeline not available"])
                sem.signal()
                return
            }

            let expired = pipeline.songCardManager.checkAndRemoveExpiredSongs()
            if !expired.isEmpty {
                pipeline.onSongsExpired(expired)
            }
            result.set([
                "success": true,
                "expiredCount": expired.count,
                "expiredSongs": expired.map { [
                    "songName": $0.songName,
                    "requesterName": $0.requesterName ?? "未知",
                    "giftValue": $0.giftValue
                ] }
            ])
            sem.signal()
        }

        sem.wait()
        return .ok(.json(result.get()))
    }
}
