import Foundation
import WebKit
import PDFKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor enum DocumentExporter {
    private final class Loader: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Error>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { continuation?.resume(throwing: error); continuation = nil }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { continuation?.resume(throwing: error); continuation = nil }
    }

    static func export(html: String, title: String, snapshot: String?, ext: String) async throws {
        if let snapshot { _ = try DocumentBranding.parse(snapshot) }
        guard let url = Bundle.main.url(forResource: "viewer", withExtension: "html", subdirectory: "Document") else { throw DocumentBranding.invalid }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123))
        let loader = Loader(); view.navigationDelegate = loader
        try await withCheckedThrowingContinuation { continuation in
            loader.continuation = continuation
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        let options: [String: Any] = ["html": html, "title": title, "branding": snapshot as Any? ?? NSNull()]
        if ext == "docx" {
            let result = try await view.callAsyncJavaScript("const bytes=await TVDocument.wordDocument(options);let text='';for(const byte of bytes)text+=String.fromCharCode(byte);return btoa(text)", arguments: ["options": options], in: nil, contentWorld: .page)
            guard let base64 = result as? String, let data = Data(base64Encoded: base64) else { throw DocumentBranding.invalid }
            try save(data, title: title, ext: ext)
            return
        }
        _ = try await view.callAsyncJavaScript("await TVDocument.showDocument(options)", arguments: ["options": options], in: nil, contentWorld: .page)
        if ext == "html" {
            guard let html = try await view.evaluateJavaScript("'<!doctype html>'+document.documentElement.outerHTML") as? String else { throw DocumentBranding.invalid }
            try save(Data(html.utf8), title: title, ext: ext)
        } else {
            let data = try await pdfData(from: view)
            #if os(macOS)
            if ext == "print" {
                guard let document = PDFDocument(data: data),
                      let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleDownToFit, autoRotate: true) else { throw DocumentBranding.invalid }
                operation.showsPrintPanel = true; operation.showsProgressPanel = true
                operation.run()
            } else { try save(data, title: title, ext: "pdf") }
            #else
            try save(data, title: title, ext: "pdf")
            #endif
        }
    }

    /// Capture each already-paginated page. Native HTML print formatters can repaginate
    /// fixed-height web content indefinitely; fixed PDF rectangles cannot change the flow.
    static func pdfData(from view: WKWebView) async throws -> Data {
        guard let rectangles = try await view.evaluateJavaScript("[...document.querySelectorAll('.tv-page')].map(p=>{const r=p.getBoundingClientRect();return {x:r.x+scrollX,y:r.y+scrollY,width:r.width,height:r.height}})") as? [[String: Double]],
              !rectangles.isEmpty else { throw DocumentBranding.invalid }
        let output = NSMutableData()
        var paper = CGRect(x: 0, y: 0, width: 595.276, height: 841.89)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &paper, nil) else { throw DocumentBranding.invalid }
        for rect in rectangles {
            guard let x = rect["x"], let y = rect["y"], let width = rect["width"], let height = rect["height"] else { throw DocumentBranding.invalid }
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: x, y: y, width: width, height: height)
            let chunk = try await view.pdf(configuration: config)
            guard let provider = CGDataProvider(data: chunk as CFData),
                  let document = CGPDFDocument(provider), document.numberOfPages == 1,
                  let page = document.page(at: 1) else { throw DocumentBranding.invalid }
            context.beginPDFPage(nil)
            context.saveGState()
            context.concatenate(page.getDrawingTransform(.mediaBox, rect: paper, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    static func save(_ data: Data, title: String, ext: String) throws {
        let name = ExportFile.filename(title: title, ext: ext)
        #if os(macOS)
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        panel.allowedContentTypes = [ExportFile.contentType(ext: ext)]
        if panel.runModal() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
        #else
        guard let root = presentingViewController else { throw DocumentBranding.invalid }
        let folder = FileManager.default.temporaryDirectory.appending(path: "DocumentExports/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = root.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: folder) }
        root.present(controller, animated: true)
        #endif
    }
    #if os(iOS)
    static var presentingViewController: UIViewController? {
        var root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = root?.presentedViewController { root = presented }
        return root
    }
    #endif
}
