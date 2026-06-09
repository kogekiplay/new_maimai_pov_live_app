import Foundation

struct ParseResult {
    enum ResultType {
        case songRequest(query: String, diffInput: String?, chartTypePreference: String?)
        case cancelRequest
        case notACommand
    }
    let type: ResultType
    let originalQuery: String
}

final class DanmakuParser {
    private let commandPrefixPattern: NSRegularExpression?
    private let cancelPattern: NSRegularExpression?
    private let matchPattern: NSRegularExpression?
    private let difficultyTailPattern: NSRegularExpression?
    private let chartTailPattern: NSRegularExpression?
    private let difficultyHeadPattern: NSRegularExpression?
    private let chartHeadPattern: NSRegularExpression?

    init() {
        commandPrefixPattern = Self.makeRegex("^!?(?:点歌)")
        cancelPattern = Self.makeRegex("^!?取消$")
        matchPattern = Self.makeRegex("^!?点歌\\s*(.+)$", options: [.caseInsensitive])
        difficultyTailPattern = Self.makeRegex("(绿|basic|黄|advanced|红|expert|紫|master|白|remaster|宴|utage)\\s*$", options: [.caseInsensitive])
        chartTailPattern = Self.makeRegex("(dx|标准|std|标)(?:谱)?\\s*$", options: [.caseInsensitive])
        difficultyHeadPattern = Self.makeRegex("^(绿|basic|黄|advanced|红|expert|紫|master|白|remaster|宴|utage)\\s*", options: [.caseInsensitive])
        chartHeadPattern = Self.makeRegex("^(dx|标准|std|标)(?:谱)?\\s*", options: [.caseInsensitive])
    }

    func parse(_ text: String) -> ParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let commandPrefixPattern, let cancelPattern, let matchPattern else {
            return ParseResult(type: .notACommand, originalQuery: "")
        }

        if cancelPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return ParseResult(type: .cancelRequest, originalQuery: trimmed)
        }

        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard commandPrefixPattern.firstMatch(in: trimmed, range: nsRange) != nil else {
            return ParseResult(type: .notACommand, originalQuery: "")
        }

        guard let match = matchPattern.firstMatch(in: trimmed, range: nsRange),
              match.numberOfRanges > 1,
              let queryRange = Range(match.range(at: 1), in: trimmed) else {
            return ParseResult(type: .notACommand, originalQuery: "")
        }

        var rawQuery = String(trimmed[queryRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawQuery.isEmpty else { return ParseResult(type: .notACommand, originalQuery: "") }

        let originalQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        var diffInput: String?
        var chartTypePreference: String?
        var changed = true
        while changed {
            changed = false

            if let (captured, fullRange) = matchFromTail(rawQuery, regex: difficultyTailPattern) {
                diffInput = captured.lowercased()
                rawQuery.removeSubrange(fullRange)
                rawQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                continue
            }

            if let (captured, fullRange) = matchFromTail(rawQuery, regex: chartTailPattern) {
                let token = captured.lowercased()
                chartTypePreference = (token == "dx") ? "dx" : "standard"
                rawQuery.removeSubrange(fullRange)
                rawQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                continue
            }

            if let (captured, fullRange) = matchFromHead(rawQuery, regex: difficultyHeadPattern) {
                diffInput = captured.lowercased()
                rawQuery.removeSubrange(fullRange)
                rawQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                continue
            }

            if let (captured, fullRange) = matchFromHead(rawQuery, regex: chartHeadPattern) {
                let token = captured.lowercased()
                chartTypePreference = (token == "dx") ? "dx" : "standard"
                rawQuery.removeSubrange(fullRange)
                rawQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                continue
            }
        }

        let queryName = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if queryName.isEmpty {
            return ParseResult(type: .songRequest(query: originalQuery, diffInput: nil, chartTypePreference: nil), originalQuery: originalQuery)
        }

        return ParseResult(type: .songRequest(query: queryName, diffInput: diffInput, chartTypePreference: chartTypePreference), originalQuery: originalQuery)
    }

    private static func makeRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            DebugInfoManager.logAsync("DanmakuParser: invalid regex \(pattern): \(error.localizedDescription)")
            return nil
        }
    }

    private func matchFromTail(_ text: String, regex: NSRegularExpression?) -> (captured: String, fullRange: Range<String.Index>)? {
        guard let regex else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range, in: text) else { return nil }
        return (captured: String(text[capturedRange]), fullRange: fullRange)
    }

    private func matchFromHead(_ text: String, regex: NSRegularExpression?) -> (captured: String, fullRange: Range<String.Index>)? {
        guard let regex else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range, in: text) else { return nil }
        return (captured: String(text[capturedRange]), fullRange: fullRange)
    }
}
