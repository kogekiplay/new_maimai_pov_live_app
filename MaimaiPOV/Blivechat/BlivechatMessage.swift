import Foundation

enum BlivechatCommand: Int, Codable {
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

enum AuthorType: Int {
    case normal = 0
    case member = 1
    case moderator = 2
    case streamer = 3
}

enum PrivilegeType: Int {
    case none = 0
    case governor = 1
    case admiral = 2
    case captain = 3
}

struct DanmakuMessage {
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
        self.timestamp = data[1] as? Int ?? 0
        self.authorName = data[2] as? String ?? ""
        self.authorType = AuthorType(rawValue: data[3] as? Int ?? 0) ?? .normal
        self.content = data[4] as? String ?? ""
        self.privilegeType = PrivilegeType(rawValue: data[5] as? Int ?? 0) ?? .none
        self.isGiftDanmaku = (data[6] as? Int ?? 0) != 0
        self.authorLevel = data[7] as? Int ?? 0
        self.isNewbie = (data[8] as? Int ?? 0) != 0
        self.isMobileVerified = (data[9] as? Int ?? 0) != 0
        self.medalLevel = data[10] as? Int ?? 0
        self.id = data[11] as? String ?? ""
        self.translation = data[12] as? String ?? ""
        self.contentType = data[13] as? Int ?? 0
        self.uid = data[16] as? String ?? ""
        self.medalName = data.count > 17 ? (data[17] as? String ?? "") : ""
    }
}

struct GiftMessage {
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
        self.timestamp = data["timestamp"] as? Int ?? 0
        self.authorName = data["authorName"] as? String ?? ""
        self.totalCoin = data["totalCoin"] as? Int ?? 0
        self.totalFreeCoin = data["totalFreeCoin"] as? Int ?? 0
        self.giftName = data["giftName"] as? String ?? ""
        self.num = data["num"] as? Int ?? 0
        self.privilegeType = PrivilegeType(rawValue: data["privilegeType"] as? Int ?? 0) ?? .none
        self.medalLevel = data["medalLevel"] as? Int ?? 0
        self.uid = data["uid"] as? String ?? ""
    }
}

struct MemberMessage {
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
        self.timestamp = data["timestamp"] as? Int ?? 0
        self.authorName = data["authorName"] as? String ?? ""
        self.privilegeType = PrivilegeType(rawValue: data["privilegeType"] as? Int ?? 0) ?? .none
        self.giftName = data["giftName"] as? String ?? ""
        self.num = data["num"] as? Int ?? 0
        self.totalCoin = data["totalCoin"] as? Int ?? 0
        self.price = data["price"] as? Int ?? 0
        self.uid = data["uid"] as? String ?? ""
    }
}

struct SuperChatMessage {
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
        self.timestamp = data["timestamp"] as? Int ?? 0
        self.authorName = data["authorName"] as? String ?? ""
        self.price = data["price"] as? Int ?? 0
        self.content = data["content"] as? String ?? ""
        self.translation = data["translation"] as? String ?? ""
        self.privilegeType = PrivilegeType(rawValue: data["privilegeType"] as? Int ?? 0) ?? .none
        self.medalLevel = data["medalLevel"] as? Int ?? 0
        self.uid = data["uid"] as? String ?? ""
    }
}

struct BlivechatErrorMessage {
    let code: Int
    let message: String

    init?(fromDict data: [String: Any]) {
        self.code = data["code"] as? Int ?? -1
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
    var intValue: Int? { value as? Int }
}
