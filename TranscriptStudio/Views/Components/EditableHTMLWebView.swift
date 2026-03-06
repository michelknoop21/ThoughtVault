// EditableHTMLWebView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// A WKWebView wrapper that supports inline editing of HTML content
// via contentEditable. Provides a JavaScript bridge to extract
// modified HTML and a native formatting toolbar.

import SwiftUI
import WebKit

// MARK: - EditableHTMLWebView

struct EditableHTMLWebView: NSViewRepresentable {

    let htmlContent: String
    @Binding var editedHTML: String
    let isEditing: Bool
    var onWebViewReady: ((WKWebView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(editedHTML: $editedHTML)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "htmlChanged")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        onWebViewReady?(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let currentEditing = context.coordinator.currentlyEditing
        let contentChanged = context.coordinator.lastLoadedHTML != htmlContent

        if contentChanged || currentEditing != isEditing {
            context.coordinator.currentlyEditing = isEditing
            context.coordinator.lastLoadedHTML = htmlContent
            let styled = Self.styledHTML(htmlContent, editable: isEditing)
            webView.loadHTMLString(styled, baseURL: nil)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var editedHTML: Binding<String>
        weak var webView: WKWebView?
        var currentlyEditing = false
        var lastLoadedHTML: String?

        init(editedHTML: Binding<String>) {
            self.editedHTML = editedHTML
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "htmlChanged",
               let html = message.body as? String {
                Task { @MainActor in
                    self.editedHTML.wrappedValue = html
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if currentlyEditing {
                webView.evaluateJavaScript("document.getElementById('content').focus()", completionHandler: nil)
            }
        }
    }

    // MARK: - Extract HTML

    func extractHTML(from webView: WKWebView) async -> String? {
        try? await webView.evaluateJavaScript(
            "document.getElementById('content').innerHTML"
        ) as? String
    }

    // MARK: - Formatting Commands

    static func execCommand(_ webView: WKWebView?, command: String, value: String? = nil) {
        guard let webView else { return }
        let valueArg = value.map { "'\($0)'" } ?? "null"
        webView.evaluateJavaScript(
            "document.execCommand('\(command)', false, \(valueArg))",
            completionHandler: nil
        )
    }

    // MARK: - HTML Sanitization

    private static func sanitizeHTML(_ html: String) -> String {
        var sanitized = html
        sanitized = sanitized.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "\\s+on\\w+\\s*=\\s*\"[^\"]*\"",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        sanitized = sanitized.replacingOccurrences(
            of: "\\s+on\\w+\\s*=\\s*'[^']*'",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        sanitized = sanitized.replacingOccurrences(
            of: "javascript:",
            with: "",
            options: .caseInsensitive
        )
        return sanitized
    }

    // MARK: - Styled HTML Template

    private static func styledHTML(_ html: String, editable: Bool) -> String {
        let editableAttr = editable ? "contenteditable=\"true\"" : ""
        let editingCSS = editable ? """
            #content { outline: none; min-height: 200px; cursor: text; }
            #content:focus { box-shadow: inset 0 0 0 2px rgba(229, 0, 116, 0.15); border-radius: 4px; }
            """ : ""
        let changeScript = editable ? """
            <script>
            const content = document.getElementById('content');
            let debounce;
            content.addEventListener('input', function() {
                clearTimeout(debounce);
                debounce = setTimeout(function() {
                    window.webkit.messageHandlers.htmlChanged.postMessage(content.innerHTML);
                }, 300);
            });
            </script>
            """ : ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
            font-size: 14px;
            line-height: 1.65;
            color: #1a1a1a;
            background: transparent;
            padding: 24px;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #e5e5e5; }
            th { background: #2a2a2a; }
            td, th { border-color: #444; }
            blockquote { background: #1a1020; }
        }
        h1 { font-size: 24px; font-weight: 700; color: #E50074; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 2px solid #E50074; }
        h2 { font-size: 18px; font-weight: 600; color: #333; margin-top: 24px; margin-bottom: 8px; }
        h3 { font-size: 15px; font-weight: 600; color: #555; margin-top: 16px; margin-bottom: 6px; }
        @media (prefers-color-scheme: dark) {
            h2 { color: #ccc; }
            h3 { color: #aaa; }
        }
        p  { margin: 8px 0; }
        ul, ol { margin: 8px 0 8px 20px; }
        li { margin: 4px 0; }
        strong { font-weight: 600; }
        em { font-style: italic; color: #555; }
        @media (prefers-color-scheme: dark) { em { color: #aaa; } }
        table { border-collapse: collapse; width: 100%; margin: 12px 0; }
        th, td { border: 1px solid #e0e0e0; padding: 8px 12px; text-align: left; }
        th { background: #f8f8f8; font-weight: 600; }
        blockquote { border-left: 3px solid #E50074; margin: 12px 0; padding: 8px 16px; background: #fef6fb; }
        \(editingCSS)
        </style>
        </head>
        <body>
        <div id="content" \(editableAttr)>\(sanitizeHTML(html))</div>
        \(changeScript)
        </body>
        </html>
        """
    }
}

// MARK: - FormattingToolbar

struct FormattingToolbar: View {

    let webView: WKWebView?

    var body: some View {
        HStack(spacing: TS.Spacing.xs) {
            formatButton(icon: "bold", command: "bold")
            formatButton(icon: "italic", command: "italic")
            formatButton(icon: "underline", command: "underline")

            Divider().frame(height: 20)

            formatButton(icon: "list.bullet", command: "insertUnorderedList")
            formatButton(icon: "list.number", command: "insertOrderedList")

            Divider().frame(height: 20)

            Menu {
                Button("Kop 1") { EditableHTMLWebView.execCommand(webView, command: "formatBlock", value: "h1") }
                Button("Kop 2") { EditableHTMLWebView.execCommand(webView, command: "formatBlock", value: "h2") }
                Button("Kop 3") { EditableHTMLWebView.execCommand(webView, command: "formatBlock", value: "h3") }
                Button("Paragraaf") { EditableHTMLWebView.execCommand(webView, command: "formatBlock", value: "p") }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Color.labelSecondary)
                .frame(height: 28)
                .padding(.horizontal, TS.Spacing.xs)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
        .padding(.horizontal, TS.Spacing.sm)
        .padding(.vertical, TS.Spacing.xs)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
        }
    }

    private func formatButton(icon: String, command: String) -> some View {
        Button {
            EditableHTMLWebView.execCommand(webView, command: command)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
