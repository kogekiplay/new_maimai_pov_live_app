import Foundation

enum BlivechatServer: String, CaseIterable, Identifiable {
    case cn = "api2.blive.chat"
    case auto = "api.blive.chat"
    case cloudflare = "cloudflare.blive.chat"
    case vercel = "vercel.blive.chat"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cn: return "CN (国内推荐)"
        case .auto: return "Auto (自动)"
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

enum RoomKeyType: Int, Codable {
    case roomId = 1
    case authCode = 2
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}
