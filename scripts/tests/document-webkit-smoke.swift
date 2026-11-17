// Run through document-webkit-smoke.sh so Bundle.main includes the production resources.
import AppKit
import WebKit

@MainActor enum AppEnvironment { static var supportDirectory: URL { URL(fileURLWithPath: CommandLine.arguments[2]) } }

@MainActor final class Check: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var view: WKWebView!
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.count == 4 else { fatalError("Pass the document bundle, output directory and fixture file") }
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 1200), configuration: config)
        view.navigationDelegate = self
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        view.loadFileURL(root.appending(path: "viewer.html"), allowingReadAccessTo: root)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            do {
                let root = URL(fileURLWithPath: CommandLine.arguments[1])
                let branding = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: "Yinga.tvhuisstijl")))
                let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[3])
                let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
                let fixture = fixtures["long"]!
                let library = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DocumentBrandingLibrary()))
                let standard = try DocumentBranding.standardJSON()
                let localStore = DocumentBrandingStore(url: URL(fileURLWithPath: CommandLine.arguments[2]).appending(path: "smoke-branding-library.json"))
                let defaultSnapshot = try localStore.defaultSnapshot()
                guard try DocumentBranding.parse(defaultSnapshot!).id == "thoughtvault" else { fatalError("Default snapshot failed") }
                let script = """
                if(TVDocument.validateLibrary(library).defaultId!==null)throw Error('Apple empty library failed');
                if(JSON.stringify(TVDocument.parseBranding(standard))!==JSON.stringify(TVDocument.standardBranding()))throw Error('Platform default branding differs');
                const options={...fixture,branding};
                await TVDocument.showDocument(options);
                const pages=[...document.querySelectorAll('.tv-page')];
                const overflow=pages.filter(p=>{const body=p.querySelector('.tv-body');return body&&body.scrollHeight>body.clientHeight+1}).length;
                if(pages.length<8||overflow||document.querySelectorAll('tbody tr').length!==120)throw Error('WebKit pagination failed');
                const bytes=await TVDocument.wordDocument(options);let binary='';for(const byte of bytes)binary+=String.fromCharCode(byte);
                return {pages:pages.length,overflow,rows:document.querySelectorAll('tbody tr').length,docx:btoa(binary),html:'<!doctype html>'+document.documentElement.outerHTML};
                """
                guard let result = try await view.callAsyncJavaScript(script, arguments: ["branding": branding, "fixture": fixture, "library": library, "standard": standard], in: nil, contentWorld: .page) as? [String: Any],
                      let base64 = result["docx"] as? String, let data = Data(base64Encoded: base64),
                      let html = result["html"] as? String else { fatalError("No result") }
                let out = URL(fileURLWithPath: CommandLine.arguments[2]); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                try data.write(to: out.appending(path: "webkit-long.docx"))
                try Data(html.utf8).write(to: out.appending(path: "webkit-long.html"))
                let pdf = try await DocumentExporter.pdfData(from: view)
                try pdf.write(to: out.appending(path: "webkit-long.pdf"))
                print("PASS: WebKit pages=\(result["pages"]!) rows=\(result["rows"]!) overflow=\(result["overflow"]!) DOCX=\(data.count) bytes and A4 PDF")
                NSApp.terminate(nil)
            } catch { FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8)); exit(1) }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8)); exit(1) }
}
@main enum Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let check = Check()
        app.delegate = check
        app.setActivationPolicy(.prohibited)
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            FileHandle.standardError.write(Data("FAIL: WebKit check timed out\n".utf8)); exit(1)
        }
        app.run()
    }
}
