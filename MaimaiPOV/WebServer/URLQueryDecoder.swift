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

enum JSONNumberInput {
    static func double(_ rawValue: Any?) -> Double? {
        let value: Double
        if let doubleValue = rawValue as? Double {
            value = doubleValue
        } else if let intValue = rawValue as? Int {
            value = Double(intValue)
        } else {
            return nil
        }
        return value.isFinite ? value : nil
    }

    static func integralInt(_ rawValue: Any?) -> Int? {
        if let intValue = rawValue as? Int {
            return intValue
        }
        guard let doubleValue = rawValue as? Double,
              doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue >= Double(Int.min),
              doubleValue <= Double(Int.max) else {
            return nil
        }
        return Int(doubleValue)
    }
}
