import Foundation

/// Plain text from notule HTML. Port of `htmlToPlainText` in windows/src/utils/htmlToMarkdown.ts.
/// Pure string work (no WebKit/NSAttributedString), so it runs off the main actor and on iOS.
enum HTMLPlainText {
    static func from(_ html: String) -> String {
        var s = html
        s = replace(s, "<(style|script|head)\\b[^>]*>.*?</\\1\\s*>", "")
        s = replace(s, "<!--.*?-->", "")
        s = replace(s, "<br\\s*/?>|</(?:p|h[1-6]|li|div|section|blockquote|tr)\\s*>", "$0\n")
        s = replace(s, "</(?:td|th)\\s*>", "$0\t")
        s = replace(s, "<[^>]+>", "")
        s = decodeEntities(s)

        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r")) }
        return replace(lines.joined(separator: "\n"), "\n{3,}", "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// `&amp;` is decoded last so `&amp;lt;` ends up as `&lt;`, not `<`.
    private static func decodeEntities(_ s: String) -> String {
        var out = ""
        var rest = s[...]
        let named = ["&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[amp...]
            if let semi = rest.prefix(12).firstIndex(of: ";") {
                let entity = String(rest[...semi])
                if let r = named[entity] {
                    out += r; rest = rest[rest.index(after: semi)...]; continue
                }
                if entity.hasPrefix("&#") {
                    let body = entity.dropFirst(2).dropLast()
                    let code = body.first == "x" || body.first == "X"
                        ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
                    if let code, let scalar = Unicode.Scalar(code) {
                        out.unicodeScalars.append(scalar); rest = rest[rest.index(after: semi)...]; continue
                    }
                }
            }
            out.append("&"); rest = rest.dropFirst()
        }
        out += rest
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}
