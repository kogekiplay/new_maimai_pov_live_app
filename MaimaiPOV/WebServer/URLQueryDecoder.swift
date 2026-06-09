import Foundation

enum URLQueryDecoder {
    static func decodeComponent(_ rawValue: String) -> String {
        let formDecoded = rawValue.replacingOccurrences(of: "+", with: " ")
        return formDecoded.removingPercentEncoding ?? formDecoded
    }

    static func decodeNonBlankComponent(_ rawValue: String) -> String? {
        let decoded = decodeComponent(rawValue)
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : decoded
    }

    static func decodeIntComponent(_ rawValue: String) -> Int? {
        Int(decodeComponent(rawValue).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
