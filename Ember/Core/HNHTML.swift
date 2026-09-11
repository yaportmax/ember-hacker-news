import Foundation

/// Small, non-executing renderer for the markup emitted by Hacker News.
/// HTML never enters a web view, so scripts, images and tracking pixels cannot run.
enum HNHTML {
    struct Run: Equatable, Sendable {
        var text: String
        var bold = false
        var italic = false
        var code = false
        var link: URL?
    }

    static func plainText(_ html: String) -> String {
        runs(html).map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func runs(_ html: String) -> [Run] {
        // Bound work for unexpectedly large API values.
        let source = String(html.prefix(200_000))
            .replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: "<[^>]*>|[^<]+|<") else { return [] }
        let ns = source as NSString
        var result: [Run] = []
        var bold = 0, italic = 0, code = 0, pre = 0
        var link: URL?
        func append(_ text: String) {
            guard !text.isEmpty else { return }
            let run = Run(text: text, bold: bold > 0, italic: italic > 0, code: code > 0, link: link)
            if let previous = result.last,
               previous.bold == run.bold, previous.italic == run.italic,
               previous.code == run.code, previous.link == run.link {
                result[result.count - 1].text += text
            } else { result.append(run) }
        }
        func paragraph() {
            guard !result.isEmpty else { return }
            let tail = result.suffix(2).map(\.text).joined()
            if tail.hasSuffix("\n\n") { return }
            append(tail.hasSuffix("\n") ? "\n" : "\n\n")
        }
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            guard token.hasPrefix("<"), token.hasSuffix(">") else {
                var text = decodeEntities(token)
                if pre == 0 {
                    text = text.replacingOccurrences(of: "[\\t\\r\\n ]+", with: " ", options: .regularExpression)
                }
                append(text)
                continue
            }
            let body = token.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            let closing = body.hasPrefix("/")
            let name = body.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(whereSeparator: { $0.isWhitespace || $0 == "/" }).first?.lowercased() ?? ""
            let delta = closing ? -1 : 1
            switch name {
            case "b", "strong": bold = max(0, bold + delta)
            case "i", "em": italic = max(0, italic + delta)
            case "code": code = max(0, code + delta)
            case "pre": paragraph(); pre = max(0, pre + delta); code = max(0, code + delta)
            case "p", "div", "blockquote": paragraph()
            case "br": append("\n")
            case "li": paragraph(); if !closing { append("• ") }
            case "a":
                if closing { link = nil } else {
                    let pattern = "(?i)\\bhref\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
                    if let matcher = try? NSRegularExpression(pattern: pattern),
                       let found = matcher.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) {
                        let raw = (1...3).compactMap { index -> String? in
                            guard let range = Range(found.range(at: index), in: token) else { return nil }
                            return String(token[range])
                        }.first
                        if let raw {
                            let decoded = decodeEntities(raw)
                            let resolved = URL(string: decoded, relativeTo: HNLinks.home)?.absoluteURL.absoluteString
                            link = WebURL.validated(resolved)
                        }
                    }
                }
            default: break
            }
        }
        if !result.isEmpty {
            result[0].text = result[0].text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
            result[result.count - 1].text = result[result.count - 1].text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
        return result.filter { !$0.text.isEmpty }
    }

    static func decodeEntities(_ text: String) -> String {
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
                                      "nbsp": " ", "ndash": "–", "mdash": "—", "hellip": "…",
                                      "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "copy": "©"]
        guard let regex = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#X[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let bodyRange = Range(match.range(at: 1), in: text), let wholeRange = Range(match.range, in: result) else { continue }
            let entity = String(text[bodyRange])
            var replacement = named[entity]
            if entity.hasPrefix("#") {
                let hex = entity.lowercased().hasPrefix("#x")
                if let value = UInt32(entity.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                   let scalar = UnicodeScalar(value), value != 0 { replacement = String(scalar) }
            }
            if let replacement { result.replaceSubrange(wholeRange, with: replacement) }
        }
        return result
    }
}
