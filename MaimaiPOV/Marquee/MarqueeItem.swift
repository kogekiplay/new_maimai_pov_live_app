import Metal

struct MarqueeItem {
    let id: UUID
    var text: String
    let type: MarqueeItemType
    var texture: MTLTexture?
    var contentWidth: Int = 0
    let createdAt: Date
    var mergeKey: String?
    var mergeCount: Int = 1
    var textPrefix: String?

    enum MarqueeItemType: Int, Sendable {
        case songSuccess = 0
        case songFailure = 1
        case gift = 2
        case superChat = 3
        case member = 4
        case songExpired = 5
    }

    init(text: String, type: MarqueeItemType, mergeKey: String? = nil, mergeCount: Int = 1, textPrefix: String? = nil) {
        self.id = UUID()
        self.text = text
        self.type = type
        self.createdAt = Date()
        self.mergeKey = mergeKey
        self.mergeCount = mergeCount
        self.textPrefix = textPrefix
    }
}
