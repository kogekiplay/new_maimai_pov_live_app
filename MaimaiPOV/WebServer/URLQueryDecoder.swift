import Foundation

enum URLQueryDecoder {
    static func decodeComponent(_ rawValue: String) -> String {
        let formDecoded = rawValue.replacingOccurrences(of: "+", with: " ")
        return formDecoded.removingPercentEncoding ?? formDecoded
    }
}
