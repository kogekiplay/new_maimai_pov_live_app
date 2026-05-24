import Foundation

struct ParseResult {
    enum ResultType {
        case songRequest(query: String, diffInput: String?, chartTypePreference: String?)
        case notACommand
    }
    let type: ResultType
}

class DanmakuParser {
    private let commandPrefixPattern: NSRegularExpression

    init() {
        commandPrefixPattern = try! NSRegularExpression(pattern: "^!?(?:点歌)", options: [])
    }

    func parse(_ text: String) -> ParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard commandPrefixPattern.firstMatch(in: trimmed, range: nsRange) != nil else {
            return ParseResult(type: .notACommand)
        }

        let matchPattern = "^!?点歌\\s*(.+)$"
        guard let matchRegex = try? NSRegularExpression(pattern: matchPattern, options: [.caseInsensitive]),
              let match = matchRegex.firstMatch(in: trimmed, range: nsRange),
              match.numberOfRanges > 1,
              let queryRange = Range(match.range(at: 1), in: trimmed) else {
            return ParseResult(type: .notACommand)
        }

        var rawQuery = String(trimmed[queryRange]).trimmingCharacters(in: .whitespaces)
        guard !rawQuery.isEmpty else { return ParseResult(type: .notACommand) }

        var diffInput: String?
        var chartTypePreference: String?
        var changed = true
        while changed {
            changed = false

            if let (captured, fullRange) = matchFromTail(rawQuery, pattern: "(绿|basic|黄|advanced|红|expert|紫|master|白|remaster|宴|utage)\\s*$") {
                diffInput = captured.lowercased()
                rawQuery.removeSubrange(fullRange)
                rawQuery = rawQuery.trimmingCharacters(in: .whitespaces)
                changed = true
                continue
            }

            if let (captured, fullRange) = matchFromTail(rawQuery, pattern: "(dx|标准|std|标)(?:谱)?\\s*$") {
                let token = captured.lowercased()
                chartTypePreference = (token == "dx") ? "dx" : "standard"
                rawQuery.removeSubrange(fullRange)
                rawQuery = rawQuery.trimmingCharacters(in: .whitespaces)
                changed = true
                continue
            }

            if let (captured, fullRange) = matchFromHead(rawQuery, pattern: "^(dx|标准|std|标)(?:谱)?\\s*") {
                let token = captured.lowercased()
                chartTypePreference = (token == "dx") ? "dx" : "standard"
                rawQuery.removeSubrange(fullRange)
                rawQuery = rawQuery.trimmingCharacters(in: .whitespaces)
                changed = true
                continue
            }
        }

        let queryName = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !queryName.isEmpty else { return ParseResult(type: .notACommand) }

        return ParseResult(type: .songRequest(query: queryName, diffInput: diffInput, chartTypePreference: chartTypePreference))
    }

    private func matchFromTail(_ text: String, pattern: String) -> (captured: String, fullRange: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range, in: text) else { return nil }
        return (captured: String(text[capturedRange]), fullRange: fullRange)
    }

    private func matchFromHead(_ text: String, pattern: String) -> (captured: String, fullRange: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range, in: text) else { return nil }
        return (captured: String(text[capturedRange]), fullRange: fullRange)
    }
}
