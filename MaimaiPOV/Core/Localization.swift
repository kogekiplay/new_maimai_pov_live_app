import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = string(key)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static func streamStatus(_ status: String) -> String {
        if status.hasPrefix("Reconnecting(") {
            return status.replacingOccurrences(of: "Reconnecting", with: string("Reconnecting"))
        }

        switch status {
        case "Idle", "Connecting", "Connected", "Publishing", "Rejected", "BadName", "Reconnect failed":
            return string(status)
        case "Error: URL/Key empty":
            return string("Error: URL/Key empty")
        case "Reconnect failed, retry manually":
            return string("Reconnect failed, retry manually")
        default:
            return status
        }
    }
}
