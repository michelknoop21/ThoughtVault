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

    /// Named entities beyond the basics: Latin-1 (160-255, `&nbsp;` is a plain space) plus common typographic ones.
    private static let namedEntities: [String: String] = [
        "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&quot;": "\"", "&apos;": "'",
        "&iexcl;": "\u{00A1}",
        "&cent;": "\u{00A2}",
        "&pound;": "\u{00A3}",
        "&curren;": "\u{00A4}",
        "&yen;": "\u{00A5}",
        "&brvbar;": "\u{00A6}",
        "&sect;": "\u{00A7}",
        "&uml;": "\u{00A8}",
        "&copy;": "\u{00A9}",
        "&ordf;": "\u{00AA}",
        "&laquo;": "\u{00AB}",
        "&not;": "\u{00AC}",
        "&shy;": "\u{00AD}",
        "&reg;": "\u{00AE}",
        "&macr;": "\u{00AF}",
        "&deg;": "\u{00B0}",
        "&plusmn;": "\u{00B1}",
        "&sup2;": "\u{00B2}",
        "&sup3;": "\u{00B3}",
        "&acute;": "\u{00B4}",
        "&micro;": "\u{00B5}",
        "&para;": "\u{00B6}",
        "&middot;": "\u{00B7}",
        "&cedil;": "\u{00B8}",
        "&sup1;": "\u{00B9}",
        "&ordm;": "\u{00BA}",
        "&raquo;": "\u{00BB}",
        "&frac14;": "\u{00BC}",
        "&frac12;": "\u{00BD}",
        "&frac34;": "\u{00BE}",
        "&iquest;": "\u{00BF}",
        "&Agrave;": "\u{00C0}",
        "&Aacute;": "\u{00C1}",
        "&Acirc;": "\u{00C2}",
        "&Atilde;": "\u{00C3}",
        "&Auml;": "\u{00C4}",
        "&Aring;": "\u{00C5}",
        "&AElig;": "\u{00C6}",
        "&Ccedil;": "\u{00C7}",
        "&Egrave;": "\u{00C8}",
        "&Eacute;": "\u{00C9}",
        "&Ecirc;": "\u{00CA}",
        "&Euml;": "\u{00CB}",
        "&Igrave;": "\u{00CC}",
        "&Iacute;": "\u{00CD}",
        "&Icirc;": "\u{00CE}",
        "&Iuml;": "\u{00CF}",
        "&ETH;": "\u{00D0}",
        "&Ntilde;": "\u{00D1}",
        "&Ograve;": "\u{00D2}",
        "&Oacute;": "\u{00D3}",
        "&Ocirc;": "\u{00D4}",
        "&Otilde;": "\u{00D5}",
        "&Ouml;": "\u{00D6}",
        "&times;": "\u{00D7}",
        "&Oslash;": "\u{00D8}",
        "&Ugrave;": "\u{00D9}",
        "&Uacute;": "\u{00DA}",
        "&Ucirc;": "\u{00DB}",
        "&Uuml;": "\u{00DC}",
        "&Yacute;": "\u{00DD}",
        "&THORN;": "\u{00DE}",
        "&szlig;": "\u{00DF}",
        "&agrave;": "\u{00E0}",
        "&aacute;": "\u{00E1}",
        "&acirc;": "\u{00E2}",
        "&atilde;": "\u{00E3}",
        "&auml;": "\u{00E4}",
        "&aring;": "\u{00E5}",
        "&aelig;": "\u{00E6}",
        "&ccedil;": "\u{00E7}",
        "&egrave;": "\u{00E8}",
        "&eacute;": "\u{00E9}",
        "&ecirc;": "\u{00EA}",
        "&euml;": "\u{00EB}",
        "&igrave;": "\u{00EC}",
        "&iacute;": "\u{00ED}",
        "&icirc;": "\u{00EE}",
        "&iuml;": "\u{00EF}",
        "&eth;": "\u{00F0}",
        "&ntilde;": "\u{00F1}",
        "&ograve;": "\u{00F2}",
        "&oacute;": "\u{00F3}",
        "&ocirc;": "\u{00F4}",
        "&otilde;": "\u{00F5}",
        "&ouml;": "\u{00F6}",
        "&divide;": "\u{00F7}",
        "&oslash;": "\u{00F8}",
        "&ugrave;": "\u{00F9}",
        "&uacute;": "\u{00FA}",
        "&ucirc;": "\u{00FB}",
        "&uuml;": "\u{00FC}",
        "&yacute;": "\u{00FD}",
        "&thorn;": "\u{00FE}",
        "&yuml;": "\u{00FF}",
        "&ndash;": "\u{2013}",
        "&mdash;": "\u{2014}",
        "&lsquo;": "\u{2018}",
        "&rsquo;": "\u{2019}",
        "&sbquo;": "\u{201A}",
        "&ldquo;": "\u{201C}",
        "&rdquo;": "\u{201D}",
        "&bdquo;": "\u{201E}",
        "&bull;": "\u{2022}",
        "&hellip;": "\u{2026}",
        "&euro;": "\u{20AC}",
        "&trade;": "\u{2122}"
    ]

    /// `&amp;` is decoded last so `&amp;lt;` ends up as `&lt;`, not `<`.
    private static func decodeEntities(_ s: String) -> String {
        var out = ""
        var rest = s[...]
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[amp...]
            if let semi = rest.prefix(12).firstIndex(of: ";") {
                let entity = String(rest[...semi])
                if let r = namedEntities[entity] {
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
