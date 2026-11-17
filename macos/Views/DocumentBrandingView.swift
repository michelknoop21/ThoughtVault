import SwiftUI
import WebKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct DocumentBrandingView: View {
    var body: some View {
        if let error = DocumentBrandingStore.shared.error {
            Text(error).foregroundStyle(Color.statusError).padding()
        } else {
            DocumentWebView(editor: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Huisstijlen")
        }
    }
}

struct DocumentBrandingPicker: View {
    let taskId: String
    var onApply: (String?) -> Void = { _ in }
    @State private var snapshot: String?
    @State private var error: String?
    @State private var showManager = false
    private var store: DocumentBrandingStore { .shared }
    private var applied: DocumentBranding? { snapshot.flatMap { try? DocumentBranding.parse($0) } }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { choices; actions }
            VStack(alignment: .leading) { choices; actions }
        }
        .padding(TS.Spacing.sm)
        .onAppear { snapshot = LocalTranscriptStore.shared.record(forTaskId: taskId)?.documentBrandingJSON }
        .sheet(isPresented: $showManager) {
            VStack {
                HStack { Text("Huisstijlen").font(TS.Font.headline); Spacer(); Button("Gereed") { showManager = false } }.padding()
                DocumentBrandingView()
            }
            #if os(macOS)
            .frame(minWidth: 850, minHeight: 650)
            #endif
        }
    }

    private var choices: some View {
        Picker("Huisstijl", selection: Binding(get: { applied?.id == "thoughtvault" ? "" : applied?.id ?? "legacy" }, set: apply)) {
            if applied == nil { Text("Huidige weergave behouden").tag("legacy").disabled(true) }
            Text("Standaard ThoughtVault").tag("")
            ForEach(store.library.styles) { style in Text(style.name).tag(style.id) }
            if let applied, applied.id != "thoughtvault", !store.library.styles.contains(where: { $0.id == applied.id }) {
                Text("\(applied.name) (bewaarde versie)").tag(applied.id)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack {
            if let applied {
                Text("Versie \(applied.revision)").font(TS.Font.caption)
                if store.library.styles.contains(where: { $0.id == applied.id }) {
                    Button("Nieuwste versie toepassen") { apply(applied.id) }
                }
            }
            Button("Huisstijlen beheren") { showManager = true }
            if let error { Text(error).font(TS.Font.caption).foregroundStyle(Color.statusError) }
        }
    }

    private func apply(_ id: String) {
        do {
            let json = try store.library.styles.first(where: { $0.id == id })?.json() ?? DocumentBranding.standardJSON()
            try LocalTranscriptStore.shared.applyBranding(taskId: taskId, snapshot: json)
            snapshot = json
            error = nil
            onApply(json)
        } catch { self.error = error.localizedDescription }
    }
}

/// The same bundled document module drives Apple webviews and the Windows UI.
@MainActor struct DocumentWebView {
    var editor = false
    var html = ""
    var title = ""
    var snapshot: String?
    var editable = false
    var onContent: (String) -> Void = { _ in }
    var onWebViewReady: ((WKWebView) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "branding")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.webView = view
        if let url = Bundle.main.url(forResource: editor ? "editor" : "viewer", withExtension: "html", subdirectory: "Document") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        onWebViewReady?(view)
        return view
    }

    func update(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.parent = self
        if coordinator.loaded { coordinator.refresh() }
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent = DocumentWebView()
        weak var webView: WKWebView?
        var loaded = false
        var lastOptions: String?
        var renderTask: Task<Void, Never>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if parent.editor {
                Task {
                    do {
                        let data = try JSONEncoder().encode(DocumentBrandingStore.shared.library)
                        let object = try JSONSerialization.jsonObject(with: data)
                        _ = try await webView.callAsyncJavaScript("window.brandingEditor.loadLibrary(library)", arguments: ["library": object], in: nil, contentWorld: .page)
                    } catch { showError(error) }
                }
            } else { refresh() }
        }

        func refresh() {
            guard let webView, !parent.editor else { return }
            let options: [String: Any] = ["html": parent.html, "title": parent.title, "branding": parent.snapshot as Any? ?? NSNull(), "editable": parent.editable]
            guard let data = try? JSONSerialization.data(withJSONObject: options, options: .sortedKeys) else { return }
            let key = String(decoding: data, as: UTF8.self)
            guard key != lastOptions else { return }
            lastOptions = key
            renderTask?.cancel()
            renderTask = Task {
                do {
                    _ = try await webView.callAsyncJavaScript("await TVDocument.showDocument(options)", arguments: ["options": options], in: nil, contentWorld: .page)
                } catch { showError(error) }
            }
        }

        private func showError(_ error: Error) {
            guard let webView else { return }
            Task { _ = try? await webView.callAsyncJavaScript("const p=document.createElement('p');p.setAttribute('role','alert');p.textContent=message;document.body.prepend(p)", arguments: ["message": error.localizedDescription], in: nil, contentWorld: .page) }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            do {
                switch type {
                case "content":
                    if parent.editable, let html = body["html"] as? String { parent.onContent(html) }
                case "save":
                    guard parent.editor, let library = body["library"] else { return }
                    let data = try JSONSerialization.data(withJSONObject: library)
                    let value = try JSONDecoder().decode(DocumentBrandingLibrary.self, from: data)
                    try DocumentBrandingStore.shared.save(value)
                    webView?.evaluateJavaScript("window.brandingEditor.saved()", completionHandler: nil)
                case "export":
                    guard parent.editor, let text = body["text"] as? String, let name = body["name"] as? String else { return }
                    _ = try DocumentBranding.parse(text)
                    try DocumentExporter.save(Data(text.utf8), title: (name as NSString).deletingPathExtension, ext: "tvhuisstijl")
                default: break
                }
            } catch {
                if type == "save", let webView {
                    Task { _ = try? await webView.callAsyncJavaScript("window.brandingEditor.saved(message)", arguments: ["message": error.localizedDescription], in: nil, contentWorld: .page) }
                } else { showError(error) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if navigationAction.navigationType == .linkActivated {
                if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #else
                    await UIApplication.shared.open(url)
                    #endif
                }
                return .cancel
            }
            return url.isFileURL || url.scheme == "about" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
            #if os(macOS)
            let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "Verwijderen"); alert.addButton(withTitle: "Annuleren")
            return alert.runModal() == .alertFirstButtonReturn
            #else
            guard let root = DocumentExporter.presentingViewController else { return false }
            return await withCheckedContinuation { continuation in
                let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Verwijderen", style: .destructive) { _ in continuation.resume(returning: true) })
                alert.addAction(UIAlertAction(title: "Annuleren", style: .cancel) { _ in continuation.resume(returning: false) })
                root.present(alert, animated: true)
            }
            #endif
        }
        #if os(macOS)
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
            let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
            return await panel.begin() == .OK ? panel.urls : nil
        }
        #endif
    }
}

#if os(macOS)
extension DocumentWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
}
#else
extension DocumentWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
}
#endif
