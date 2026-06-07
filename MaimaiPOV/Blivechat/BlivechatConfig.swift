import Foundation

enum BlivechatServer: String, CaseIterable, Identifiable, Sendable {
    case cn = "api2.blive.chat"
    case auto = "api.blive.chat"
    case cloudflare = "cloudflare.blive.chat"
    case vercel = "vercel.blive.chat"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cn: return L10n.string("CN (recommended)")
        case .auto: return L10n.string("Auto")
        case .cloudflare: return "Cloudflare"
        case .vercel: return "Vercel"
        }
    }

    var websocketURL: URL {
        URL(string: "wss://\(rawValue)/api/chat")!
    }

    var originURL: String {
        "https://\(rawValue)"
    }
}

enum RoomKeyType: Int, Codable, Sendable {
    case roomId = 1
    case authCode = 2
}

enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(String)
    case error(String)
}
