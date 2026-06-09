import Foundation

private func normalizedAuthorName(_ value: Any?) -> String {
    (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func integralInt(_ value: Any?) -> Int? {
    if value is Bool {
        return nil
    }
    if let intValue = value as? Int {
        return intValue
    }
    guard let doubleValue = value as? Double,
          doubleValue.isFinite,
          doubleValue.rounded(.towardZero) == doubleValue,
          doubleValue >= Double(Int.min),
          doubleValue <= Double(Int.max) else {
        return nil
    }
    return Int(doubleValue)
}

private func intValue(_ value: Any?, default defaultValue: Int = 0) -> Int {
    integralInt(value) ?? defaultValue
}

enum BlivechatCommand: Int, Codable, Sendable {
    case heartbeat = 0
    case joinRoom = 1
    case addText = 2
    case addGift = 3
    case addMember = 4
    case addSuperChat = 5
    case delSuperChat = 6
    case updateTranslation = 7
    case fatalError = 8
}

struct BlivechatEnvelope: Codable {
    let cmd: Int
    let data: AnyCodable?
}

enum AuthorType: Int, Sendable {
    case normal = 0
    case member = 1
    case moderator = 2
    case streamer = 3
}

enum PrivilegeType: Int, Sendable {
    case none = 0
    case governor = 1
    case admiral = 2
    case captain = 3
}

struct DanmakuMessage: Sendable {
    let avatarUrl: String
    let timestamp: Int
    let authorName: String
    let authorType: AuthorType
    let content: String
    let privilegeType: PrivilegeType
    let isGiftDanmaku: Bool
    let authorLevel: Int
    let isNewbie: Bool
    let isMobileVerified: Bool
    let medalLevel: Int
    let id: String
    let translation: String
    let contentType: Int
    let uid: String
    let medalName: String

    var effectiveUid: String { uid.isEmpty ? authorName : uid }

    init?(fromArray data: [Any]) {
        guard data.count >= 17 else { return nil }

        self.avatarUrl = data[0] as? String ?? ""
        self.timestamp = intValue(data[1])
        self.authorName = normalizedAuthorName(data[2])
        self.authorType = AuthorType(rawValue: intValue(data[3])) ?? .normal
        self.content = data[4] as? String ?? ""
        self.privilegeType = PrivilegeType(rawValue: intValue(data[5])) ?? .none
        self.isGiftDanmaku = intValue(data[6]) != 0
        self.authorLevel = intValue(data[7])
        self.isNewbie = intValue(data[8]) != 0
        self.isMobileVerified = intValue(data[9]) != 0
        self.medalLevel = intValue(data[10])
        self.id = data[11] as? String ?? ""
        self.translation = data[12] as? String ?? ""
        self.contentType = intValue(data[13])
        self.uid = data[16] as? String ?? ""
        self.medalName = data.count > 17 ? (data[17] as? String ?? "") : ""
    }
}

struct GiftMessage: Sendable {
    let id: String
    let avatarUrl: String
    let timestamp: Int
    let authorName: String
    let totalCoin: Int
    let totalFreeCoin: Int
    let giftName: String
    let num: Int
    let privilegeType: PrivilegeType
    let medalLevel: Int
    let uid: String

    var isPaidGift: Bool { totalCoin >= 1000 }

    var effectiveUid: String { uid.isEmpty ? authorName : uid }

    init?(fromDict data: [String: Any]) {
        self.id = data["id"] as? String ?? ""
        self.avatarUrl = data["avatarUrl"] as? String ?? ""
        self.timestamp = intValue(data["timestamp"])
        self.authorName = normalizedAuthorName(data["authorName"])
        self.totalCoin = intValue(data["totalCoin"])
        self.totalFreeCoin = intValue(data["totalFreeCoin"])
        self.giftName = data["giftName"] as? String ?? ""
        self.num = intValue(data["num"])
        self.privilegeType = PrivilegeType(rawValue: intValue(data["privilegeType"])) ?? .none
        self.medalLevel = intValue(data["medalLevel"])
        self.uid = data["uid"] as? String ?? ""
    }
}

struct MemberMessage: Sendable {
    let id: String
    let avatarUrl: String
    let timestamp: Int
    let authorName: String
    let privilegeType: PrivilegeType
    let giftName: String
    let num: Int
    let totalCoin: Int
    let price: Int
    let uid: String

    var effectiveUid: String { uid.isEmpty ? authorName : uid }

    init?(fromDict data: [String: Any]) {
        self.id = data["id"] as? String ?? ""
        self.avatarUrl = data["avatarUrl"] as? String ?? ""
        self.timestamp = intValue(data["timestamp"])
        self.authorName = normalizedAuthorName(data["authorName"])
        self.privilegeType = PrivilegeType(rawValue: intValue(data["privilegeType"])) ?? .none
        self.giftName = data["giftName"] as? String ?? ""
        self.num = intValue(data["num"])
        self.totalCoin = intValue(data["totalCoin"])
        self.price = intValue(data["price"])
        self.uid = data["uid"] as? String ?? ""
    }
}

struct SuperChatMessage: Sendable {
    let id: String
    let avatarUrl: String
    let timestamp: Int
    let authorName: String
    let price: Int
    let content: String
    let translation: String
    let privilegeType: PrivilegeType
    let medalLevel: Int
    let uid: String

    var effectiveUid: String { uid.isEmpty ? authorName : uid }

    init?(fromDict data: [String: Any]) {
        self.id = data["id"] as? String ?? ""
        self.avatarUrl = data["avatarUrl"] as? String ?? ""
        self.timestamp = intValue(data["timestamp"])
        self.authorName = normalizedAuthorName(data["authorName"])
        self.price = intValue(data["price"])
        self.content = data["content"] as? String ?? ""
        self.translation = data["translation"] as? String ?? ""
        self.privilegeType = PrivilegeType(rawValue: intValue(data["privilegeType"])) ?? .none
        self.medalLevel = intValue(data["medalLevel"])
        self.uid = data["uid"] as? String ?? ""
    }
}

struct BlivechatErrorMessage: Sendable {
    let code: Int
    let message: String

    init?(fromDict data: [String: Any]) {
        self.code = intValue(data["code"], default: -1)
        self.message = data["msg"] as? String ?? ""
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map { $0.value }
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let intVal as Int:
            try container.encode(intVal)
        case let doubleVal as Double:
            try container.encode(doubleVal)
        case let boolVal as Bool:
            try container.encode(boolVal)
        case let stringVal as String:
            try container.encode(stringVal)
        case let arrayVal as [Any]:
            try container.encode(arrayVal.map { AnyCodable($0) })
        case let dictVal as [String: Any]:
            try container.encode(dictVal.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    var arrayValue: [Any]? { value as? [Any] }
    var dictValue: [String: Any]? { value as? [String: Any] }
    var stringValue: String? { value as? String }
    var intValue: Int? { integralInt(value) }
}
