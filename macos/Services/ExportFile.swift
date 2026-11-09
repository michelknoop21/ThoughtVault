import Foundation
import UniformTypeIdentifiers

/// Export naming, content types and raw-transcript HTML escaping.
/// Filename rule is a port of `windows/src/services/textExport.ts`.
enum ExportFile {
    static func filename(title: String, ext: String) -> String {
        let forbidden = CharacterSet(charactersIn: "<>:\"/\\|?*").union(CharacterSet(charactersIn: "\u{0}"..."\u{1F}"))
        var name = String(title.unicodeScalars.map { forbidden.contains($0) ? "_" : Character($0) })
        while let last = name.last, last == "." || last == " " { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? "notulen" : name) + "." + ext
    }

    static func contentType(ext: String) -> UTType {
        switch ext {
        case "txt": return .plainText
        case "pdf": return .pdf
        case "html": return .html
        default: return UTType(filenameExtension: ext) ?? (ext == "md" ? .plainText : .data)
        }
    }

    /// Raw transcripts are plain text: escape markup before embedding them in print HTML.
    static func transcriptHTML(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
