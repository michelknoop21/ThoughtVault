import Foundation
import Observation
import ImageIO

/// Portable version 1. Images are embedded so snapshots remain independent of the library.
struct DocumentBranding: Codable, Hashable, Sendable, Identifiable {
    var schemaVersion: Int
    var id: String
    var revision: Int
    var name: String
    var company: String
    var contact: String
    var layout: String
    var textColor: String
    var headingColor: String
    var accentColor: String
    var bodyFont: String
    var headingFont: String
    var fontSize: Double
    var lineHeight: Double
    var marginTop: Double
    var marginBottom: Double
    var marginLeft: Double
    var marginRight: Double
    var header: String
    var footer: String
    var coverHeader: String
    var coverFooter: String
    var pageNumbers: Bool
    var runningHeader: Bool
    var runningFooter: Bool
    var logo: String
    var coverBanner: String
    var headerBanner: String
    var footerBanner: String

    static let maximumBytes = 12 * 1024 * 1024
    static let invalid = NSError(domain: "DocumentBranding", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "De huisstijl is ongeldig of te groot. Gebruik een .tvhuisstijl-bestand met PNG- of JPEG-afbeeldingen van maximaal 2 MB.")])

    func validate() throws {
        guard schemaVersion == 1, revision >= 1, ["compact", "cover"].contains(layout),
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.count <= 100,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              [bodyFont, headingFont].allSatisfy({ ["Carlito", "Caladea"].contains($0) }),
              [textColor, headingColor, accentColor].allSatisfy({ $0.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil }),
              [company, contact, header, footer, coverHeader, coverFooter].allSatisfy({ $0.count <= 1200 }),
              (9...20).contains(fontSize), (1...2.5).contains(lineHeight),
              [marginTop, marginBottom].allSatisfy({ (15...40).contains($0) }),
              [marginLeft, marginRight].allSatisfy({ (10...40).contains($0) }) else { throw Self.invalid }
        for image in [logo, coverBanner, headerBanner, footerBanner] where !image.isEmpty {
            let png = image.hasPrefix("data:image/png;base64,")
            guard png || image.hasPrefix("data:image/jpeg;base64,"),
                  let comma = image.firstIndex(of: ","),
                  image.utf8.count <= 2 * 1024 * 1024 * 4 / 3 + 100,
                  let data = Data(base64Encoded: String(image[image.index(after: comma)...])),
                  data.count <= 2 * 1024 * 1024, data.count >= 16,
                  png ? data.starts(with: [137,80,78,71,13,10,26,10]) : data.starts(with: [255,216,255]) else { throw Self.invalid }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 10000, height <= 10000, width * height <= 25_000_000,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw Self.invalid }
        }
        guard try JSONEncoder().encode(self).count <= Self.maximumBytes else { throw Self.invalid }
    }

    static func standardJSON() throws -> String {
        guard let url = Bundle.main.url(forResource: "ThoughtVault", withExtension: "tvhuisstijl", subdirectory: "Document") else { throw invalid }
        let json = try String(contentsOf: url, encoding: .utf8)
        _ = try parse(json)
        return json
    }

    static func parse(_ json: String) throws -> Self {
        guard json.utf8.count <= maximumBytes else { throw invalid }
        let value = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
        try value.validate()
        return value
    }

    func json() throws -> String {
        try validate()
        return String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }
}

struct DocumentBrandingLibrary: Codable, Sendable {
    var schemaVersion = 1
    var defaultId: String?
    var styles: [DocumentBranding] = []

    func validate() throws {
        guard schemaVersion == 1, styles.count <= 40,
              Set(styles.map(\.id)).count == styles.count,
              defaultId == nil || styles.contains(where: { $0.id == defaultId }) else { throw DocumentBranding.invalid }
        for style in styles { try style.validate() }
    }
}

@MainActor @Observable
final class DocumentBrandingStore {
    static let shared = DocumentBrandingStore()
    private(set) var library = DocumentBrandingLibrary()
    private(set) var error: String?
    @ObservationIgnored private let url: URL

    init(url: URL? = nil) {
        let url = url ?? AppEnvironment.supportDirectory.appending(path: "ThoughtVault/document-branding.json")
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let value = try JSONDecoder().decode(DocumentBrandingLibrary.self, from: Data(contentsOf: url))
                try value.validate()
                library = value
            }
        } catch { self.error = error.localizedDescription }
    }

    func save(_ value: DocumentBrandingLibrary) throws {
        // An unreadable library is never silently replaced with an empty one.
        guard error == nil else { throw DocumentBranding.invalid }
        try value.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        library = value
    }

    func defaultSnapshot() throws -> String? {
        guard error == nil else { throw DocumentBranding.invalid }
        return try library.styles.first(where: { $0.id == library.defaultId })?.json() ?? DocumentBranding.standardJSON()
    }
}
