import Foundation
import Swifter

final class DebugAPIHandler: @unchecked Sendable {
    enum OptionalIntInput: Equatable {
        case valid(Int?)
        case invalid
    }

    weak var pipeline: LivePipelineManager?

    static func requiredNonBlankString(in body: [String: Any], key: String) -> String? {
        guard let value = body[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    static func requiredPositiveInt(in body: [String: Any], key: String) -> Int? {
        guard let value = positiveIntValue(body[key]) else {
            return nil
        }
        return value
    }

    static func optionalPositiveInt(in body: [String: Any], key: String, defaultValue: Int) -> Int? {
        guard let rawValue = body[key], !(rawValue is NSNull) else {
            return defaultValue
        }
        guard let value = positiveIntValue(rawValue) else {
            return nil
        }
        return value
    }

    private static func positiveIntValue(_ rawValue: Any?) -> Int? {
        let value: Int
        if let intValue = rawValue as? Int {
            value = intValue
        } else if let doubleValue = rawValue as? Double,
                  doubleValue.isFinite,
                  doubleValue.rounded(.towardZero) == doubleValue,
                  doubleValue >= Double(Int.min),
                  doubleValue <= Double(Int.max) {
            value = Int(doubleValue)
        } else {
            return nil
        }
        return value > 0 ? value : nil
    }

    static func optionalBatteryLevel(in body: [String: Any], key: String) -> OptionalIntInput {
        guard let rawValue = body[key], !(rawValue is NSNull) else {
            return .valid(nil)
        }
        guard let value = rawValue as? Int, (0...100).contains(value) else {
            return .invalid
        }
        return .valid(value)
    }

    func simulateGift(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let authorName = Self.requiredNonBlankString(in: body, key: "authorName") else {
            return .badRequest(.text("Missing 'authorName'"))
        }

        guard let totalCoin = Self.optionalPositiveInt(in: body, key: "totalCoin", defaultValue: 1000) else {
            return .badRequest(.text("Invalid 'totalCoin'"))
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        Task { @MainActor [weak self] in
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
              let authorName = Self.requiredNonBlankString(in: body, key: "authorName") else {
            return .badRequest(.text("Missing 'authorName'"))
        }

        guard let price = Self.optionalPositiveInt(in: body, key: "price", defaultValue: 30) else {
            return .badRequest(.text("Invalid 'price'"))
        }
        let content = body["content"] as? String ?? ""

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        Task { @MainActor [weak self] in
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
              let authorName = Self.requiredNonBlankString(in: body, key: "authorName") else {
            return .badRequest(.text("Missing 'authorName'"))
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        Task { @MainActor [weak self] in
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
              let authorName = Self.requiredNonBlankString(in: body, key: "authorName"),
              let content = Self.requiredNonBlankString(in: body, key: "content") else {
            return .badRequest(.text("Missing 'authorName' or 'content'"))
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        Task { @MainActor [weak self] in
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

        Task { @MainActor [weak self] in
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
              let text = Self.requiredNonBlankString(in: body, key: "text") else {
            return .badRequest(.text("Missing 'text'"))
        }

        let typeRaw = body["type"] as? Int ?? 0
        let type = MarqueeItem.MarqueeItemType(rawValue: typeRaw) ?? .songSuccess
        let mergeKey = body["mergeKey"] as? String
        guard let mergeCount = Self.optionalPositiveInt(in: body, key: "mergeCount", defaultValue: 1) else {
            return .badRequest(.text("Invalid 'mergeCount'"))
        }
        let textPrefix = body["textPrefix"] as? String

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        Task { @MainActor [weak self] in
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

        let level: Int?
        switch Self.optionalBatteryLevel(in: body, key: "level") {
        case .valid(let parsedLevel):
            level = parsedLevel
        case .invalid:
            return .badRequest(.text("Invalid 'level'"))
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        Task { @MainActor [weak self] in
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
              let timeout = Self.requiredPositiveInt(in: body, key: "timeout") else {
            return .badRequest(.text("Missing 'timeout' (seconds)"))
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<[String: Any]>(["success": true])

        Task { @MainActor [weak self] in
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

        Task { @MainActor [weak self] in
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
