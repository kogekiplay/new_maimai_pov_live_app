import Metal

struct MarqueeItem {
    let id: UUID
    let text: String
    let type: MarqueeItemType
    var texture: MTLTexture?
    var contentWidth: Int = 0
    let createdAt: Date

    enum MarqueeItemType: Int {
        case songSuccess = 0
        case songFailure = 1
        case gift = 2
        case superChat = 3
        case member = 4
    }

    init(text: String, type: MarqueeItemType) {
        self.id = UUID()
        self.text = text
        self.type = type
        self.createdAt = Date()
    }
}
