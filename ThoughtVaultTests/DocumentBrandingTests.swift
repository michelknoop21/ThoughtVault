import XCTest
import SwiftData
import CloudKit
import WebKit
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
@testable import ThoughtVault

@MainActor final class DocumentBrandingTests: XCTestCase {
    private func example() throws -> DocumentBranding {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Yinga", withExtension: "tvhuisstijl", subdirectory: "Document"))
        return try DocumentBranding.parse(String(contentsOf: url, encoding: .utf8))
    }

    func testLibraryRoundTripDefaultAndSnapshotsSurviveEditsAndRemoval() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "branding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "library.json")
        let store = DocumentBrandingStore(url: url)
        var style = try example()
        try store.save(DocumentBrandingLibrary(defaultId: style.id, styles: [style]))
        let applied = try XCTUnwrap(store.defaultSnapshot())
        style.name = "Aangepast"; style.revision += 1
        try store.save(DocumentBrandingLibrary(defaultId: style.id, styles: [style]))
        XCTAssertEqual(DocumentBrandingStore(url: url).library.styles.first?.name, "Aangepast")
        try store.save(DocumentBrandingLibrary())
        XCTAssertEqual(try DocumentBranding.parse(applied).name, "Yinga")
        XCTAssertEqual(try DocumentBranding.parse(applied).revision, 1)
        XCTAssertEqual(try DocumentBranding.parse(XCTUnwrap(store.defaultSnapshot())).id, "thoughtvault")
    }

    func testInvalidImportsAndUnreadableLibraryDoNotOverwriteFiles() throws {
        var style = try example()
        style.logo = "https://example.com/logo.png"
        XCTAssertThrowsError(try style.validate())
        style = try example(); style.schemaVersion = 2
        XCTAssertThrowsError(try style.validate())
        style = try example(); style.fontSize = .infinity
        XCTAssertThrowsError(try style.validate())
        let folder = FileManager.default.temporaryDirectory.appending(path: "branding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "library.json")
        try Data("broken".utf8).write(to: url)
        let store = DocumentBrandingStore(url: url)
        XCTAssertNotNil(store.error)
        XCTAssertThrowsError(try store.save(DocumentBrandingLibrary()))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken")
    }

    func testAppliedSnapshotSurvivesPortableSyncAndContentEditing() throws {
        let container = try ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LocalTranscriptStore(container: container)
        let record = TranscriptRecord(id: "branded", title: "Overleg", notuleHtml: "<p>Besluit</p>")
        let snapshot = try example().json()
        record.documentBrandingJSON = snapshot
        try store.save(record)
        try store.updateNotule(taskId: record.taskId, html: "<p>Gewijzigd besluit</p>")
        XCTAssertEqual(record.documentBrandingJSON, snapshot)
        let payload = SyncedNotule(record)
        let decoded = try JSONDecoder().decode(SyncedNotule.self, from: payload.encoded())
        XCTAssertEqual(decoded.documentBrandingJSON, snapshot)
        XCTAssertEqual(record.asTranscript.documentBrandingJSON, snapshot)
        let data = try JSONEncoder().encode(record.asTranscript)
        XCTAssertEqual(try JSONDecoder().decode(Transcript.self, from: data).documentBrandingJSON, snapshot)
        let copy = TranscriptRecord(id: record.id, title: "")
        decoded.apply(to: copy)
        XCTAssertEqual(copy.documentBrandingJSON, snapshot)
        XCTAssertEqual(copy.notuleHtml, "<p>Gewijzigd besluit</p>")
    }
}

// Opt-in device acceptance: a separate temporary zone, synthetic content only.
extension DocumentBrandingTests {
    func testPhysicalCloudSnapshotRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let phase = environment["TV_BRANDING_CLOUD_PHASE"],
              let run = environment["TV_BRANDING_CLOUD_RUN"] else {
            throw XCTSkip("Physical iCloud acceptance requires an explicit phase and run ID.")
        }
        guard ["mac-write", "phone-edit", "mac-verify"].contains(phase),
              run.range(of: "^[a-zA-Z0-9-]{1,64}$", options: .regularExpression) != nil else {
            XCTFail("Invalid acceptance phase or run ID"); return
        }
        let cloud = CKContainer(identifier: NotuleSyncService.containerID)
        let account = try await cloud.accountStatus()
        guard account == .available else { XCTFail("iCloud account unavailable on this device"); return }
        let database = cloud.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "BrandingAcceptance-\(run)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: "synthetic-note", zoneID: zoneID)
        let snapshot = try example().json()
        let directory = AppEnvironment.supportDirectory.appending(path: "CloudBrandingAcceptance")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let assetURL = directory.appending(path: "payload.json")
        func upload(_ note: SyncedNotule, record: CKRecord) async throws {
            try note.encoded().write(to: assetURL, options: .atomic)
            record["content"] = CKAsset(fileURL: assetURL)
            record["contentHash"] = try note.digest() as CKRecordValue
            record["schemaVersion"] = 1 as CKRecordValue
            _ = try await database.save(record)
        }
        if phase == "mac-write" {
            #if !os(macOS)
            XCTFail("mac-write must run on a physical Mac"); return
            #endif
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            let record = TranscriptRecord(id: "synthetic-note", title: "Huisstijlacceptatie",
                                          notuleHtml: "<p>Synthetisch besluit met café ☕.</p>")
            record.documentBrandingJSON = snapshot
            try await upload(SyncedNotule(record), record: CKRecord(recordType: "Notule", recordID: recordID))
        } else {
            let cloudRecord = try await database.record(for: recordID)
            let asset = try XCTUnwrap(cloudRecord["content"] as? CKAsset)
            let data = try Data(contentsOf: XCTUnwrap(asset.fileURL))
            let payload = try JSONDecoder().decode(SyncedNotule.self, from: data)
            XCTAssertEqual(try payload.digest(), cloudRecord["contentHash"] as? String)
            let applied = try DocumentBranding.parse(XCTUnwrap(payload.documentBrandingJSON))
            XCTAssertTrue(applied == (try example()), "Snapshot or embedded assets changed in iCloud")
            if phase == "phone-edit" {
                #if !os(iOS) || targetEnvironment(simulator)
                XCTFail("phone-edit must run on a physical iPhone or iPad"); return
                #endif
                let container = try ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
                let store = LocalTranscriptStore(container: container)
                let local = TranscriptRecord(id: payload.id, title: "")
                payload.apply(to: local)
                try store.save(local)
                try store.updateNotule(taskId: local.taskId, html: "<p>Bewerkt op fysieke iPhone — café ☕.</p>")
                XCTAssertTrue(local.documentBrandingJSON == payload.documentBrandingJSON, "Editing changed the snapshot")
                try await upload(SyncedNotule(local), record: cloudRecord)
            } else {
                #if !os(macOS)
                XCTFail("mac-verify must run on a physical Mac"); return
                #endif
                XCTAssertEqual(payload.notuleHtml, "<p>Bewerkt op fysieke iPhone — café ☕.</p>")
                _ = try await database.deleteRecordZone(withID: zoneID)
            }
        }
        print("PHYSICAL_CLOUD_BRANDING phase=\(phase) completed")
    }
}

@MainActor private final class BrandingPageLoader: NSObject, WKNavigationDelegate {
    var continuation: CheckedContinuation<Void, Error>?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(); continuation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error); continuation = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error); continuation = nil
    }
}

extension DocumentBrandingTests {
    func testNativeWebKitRendersAndExportsSharedFixtures() async throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fixtures", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: fixtureURL))
        let pageURL = try XCTUnwrap(Bundle.main.url(forResource: "viewer", withExtension: "html", subdirectory: "Document"))
        #if os(macOS)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 390, height: 844),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Huisstijlacceptatie"
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let host = try XCTUnwrap(window.contentView)
        #else
        let host = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController?.view)
        #endif
        for name in ["short", "long", "oversizedRow", "oversizedItem"] {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
            host.addSubview(view)
            defer { view.removeFromSuperview() }
            let loader = BrandingPageLoader()
            view.navigationDelegate = loader
            try await withCheckedThrowingContinuation { continuation in
                loader.continuation = continuation
                view.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
            }
            let fixture = try XCTUnwrap(fixtures[name])
            let title = try XCTUnwrap(fixture["title"])
            let options: [String: Any] = ["html": try XCTUnwrap(fixture["html"]),
                "title": title, "branding": try example().json()]
            let script = """
            await TVDocument.showDocument(options);
            const pages=[...document.querySelectorAll('.tv-page')];
            if(pages.some(p=>{const b=p.querySelector('.tv-body');return b&&b.scrollHeight>b.clientHeight+1}))throw Error('Page overflow');
            if(!document.fonts.check('11pt Carlito')||!document.fonts.check('11pt Caladea'))throw Error('Missing bundled fonts');
            if([...document.images].some(img=>!img.naturalWidth))throw Error('Missing document image');
            return pages.length;
            """
            let rendered: Any?
            do {
                rendered = try await view.callAsyncJavaScript(script, arguments: ["options": options],
                    in: nil, contentWorld: .page)
            } catch {
                let detail = error as NSError
                print("NATIVE_BRANDING domain=\(detail.domain) code=\(detail.code) info=\(detail.userInfo)")
                throw error
            }
            let count = try XCTUnwrap(rendered as? Int)
            let refreshed = try await view.callAsyncJavaScript(script, arguments: ["options": options],
                in: nil, contentWorld: .page)
            XCTAssertEqual(refreshed as? Int, count)
            XCTAssertGreaterThanOrEqual(count, name == "short" ? 2 : 3)
            let word = try await view.callAsyncJavaScript("return (await TVDocument.wordDocument(options)).length",
                arguments: ["options": options],
                in: nil, contentWorld: .page) as? Int
            XCTAssertGreaterThan(try XCTUnwrap(word), 100_000)
            // Match the exporter's A4 viewport after checking the narrow preview.
            view.frame = CGRect(x: 0, y: 0, width: 794, height: 1123)
            _ = try await view.callAsyncJavaScript("await new Promise(resolve=>requestAnimationFrame(resolve));TVDocument.fitDocument(document)",
                arguments: [:], in: nil, contentWorld: .page)
            let pdf = try await DocumentExporter.pdfData(from: view)
            let document = try XCTUnwrap(PDFDocument(data: pdf))
            XCTAssertEqual(document.pageCount, count)
            XCTAssertTrue(document.string?.contains(title) == true, "PDF is missing its document title")
            for index in 0..<count {
                let box = try XCTUnwrap(document.page(at: index)).bounds(for: .mediaBox)
                XCTAssertEqual(box.width, 595.276, accuracy: 1)
                XCTAssertEqual(box.height, 841.89, accuracy: 1)
            }
            let attachment = XCTAttachment(data: pdf, uniformTypeIdentifier: "com.adobe.pdf")
            attachment.name = "Yinga-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("NATIVE_BRANDING fixture=\(name) pages=\(count) A4 PDF=\(pdf.count) bytes")
        }
    }
}
