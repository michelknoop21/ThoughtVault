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

#if os(macOS)
struct EditableHTMLWebView: NSViewRepresentable {

    let htmlContent: String
    @Binding var editedHTML: String
    let isEditing: Bool
    let isDarkMode: Bool
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
        let darkChanged = context.coordinator.lastDarkMode != isDarkMode

        if contentChanged || currentEditing != isEditing || darkChanged {
            context.coordinator.currentlyEditing = isEditing
            context.coordinator.lastLoadedHTML = htmlContent
            context.coordinator.lastDarkMode = isDarkMode
            let styled = Self.styledHTML(htmlContent, editable: isEditing, isDark: isDarkMode)
            webView.loadHTMLString(styled, baseURL: nil)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var editedHTML: Binding<String>
        weak var webView: WKWebView?
        var currentlyEditing = false
        var lastLoadedHTML: String?
        var lastDarkMode: Bool?

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

    private static func styledHTML(_ html: String, editable: Bool, isDark: Bool) -> String {
        let editableAttr = editable ? "contenteditable=\"true\"" : ""
        let editingCSS = editable ? """
            #content { outline: none; min-height: 200px; cursor: text; }
            #content:focus { box-shadow: inset 0 0 0 2px rgba(229, 0, 116, 0.12); border-radius: 6px; }
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
        let darkClass = isDark ? "dark" : ""

        return """
        <!DOCTYPE html>
        <html class="\(darkClass)">
        <head>
        <meta charset="utf-8">
        <style>
        :root {
            --text-primary: #2c2c30;
            --text-secondary: #555560;
            --text-tertiary: #8e8e93;
            --heading: #1a2744;
            --brand: #E50074;
            --brand-light: #fef2f8;
            --brand-border: rgba(229, 0, 116, 0.15);
            --border: #d8dce3;
            --surface-elevated: #f8f8fa;
            --bg-blockquote: #fef6fb;
        }
        html.dark {
            --text-primary: #f0f0f4;
            --text-secondary: #9e9ea8;
            --text-tertiary: #6c6c74;
            --heading: #c8d4e8;
            --brand: #ff3b8a;
            --brand-light: #1f0a15;
            --brand-border: rgba(255, 59, 138, 0.20);
            --border: #38383d;
            --surface-elevated: #222228;
            --bg-blockquote: #1f0e18;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif;
            font-size: 14.5px;
            line-height: 1.72;
            color: var(--text-primary);
            background: transparent;
            padding: 28px 32px;
            -webkit-font-smoothing: antialiased;
        }
        h1 {
            font-size: 21px;
            font-weight: 700;
            color: var(--heading);
            margin-bottom: 4px;
            letter-spacing: -0.3px;
            line-height: 1.3;
        }
        h1 + p, h1 + .datum {
            margin-top: 0;
            padding-bottom: 14px;
            border-bottom: 1.5px solid var(--border);
            margin-bottom: 16px;
        }
        h2 {
            font-size: 15.5px;
            font-weight: 700;
            color: var(--heading);
            margin-top: 24px;
            margin-bottom: 8px;
            letter-spacing: -0.1px;
        }
        h3 {
            font-size: 14.5px;
            font-weight: 700;
            color: var(--heading);
            margin-top: 20px;
            margin-bottom: 6px;
        }
        p { margin: 8px 0; }
        ul, ol { margin: 8px 0 8px 24px; }
        li { margin: 4px 0; }
        li::marker { color: var(--text-primary); }
        strong { font-weight: 600; color: var(--text-primary); }
        em { font-style: italic; color: var(--text-secondary); }
        a { color: var(--brand); text-decoration: none; }
        a:hover { text-decoration: underline; }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 16px 0;
            border-radius: 8px;
            overflow: hidden;
            border: 1px solid var(--border);
        }
        th, td {
            border: 1px solid var(--border);
            padding: 10px 14px;
            text-align: left;
            font-size: 13.5px;
        }
        th {
            background: var(--surface-elevated);
            font-weight: 600;
            font-size: 12.5px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            color: var(--text-secondary);
        }
        blockquote {
            border-left: 3px solid var(--brand);
            margin: 16px 0;
            padding: 12px 20px;
            background: var(--bg-blockquote);
            border-radius: 0 8px 8px 0;
            font-style: italic;
            color: var(--text-secondary);
        }
        hr {
            border: none;
            height: 1px;
            background: var(--border);
            margin: 24px 0;
        }
        code {
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 0.9em;
            background: var(--surface-elevated);
            padding: 2px 6px;
            border-radius: 4px;
        }
        pre {
            background: var(--surface-elevated);
            padding: 16px;
            border-radius: 8px;
            overflow-x: auto;
            margin: 12px 0;
            border: 1px solid var(--border);
        }
        pre code { background: none; padding: 0; }
        ::selection { background: rgba(229, 0, 116, 0.18); }
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
#else
struct EditableHTMLWebView: UIViewRepresentable {

    let htmlContent: String
    @Binding var editedHTML: String
    let isEditing: Bool
    let isDarkMode: Bool
    var onWebViewReady: ((WKWebView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(editedHTML: $editedHTML)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "htmlChanged")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        onWebViewReady?(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let currentEditing = context.coordinator.currentlyEditing
        let contentChanged = context.coordinator.lastLoadedHTML != htmlContent
        let darkChanged = context.coordinator.lastDarkMode != isDarkMode

        if contentChanged || currentEditing != isEditing || darkChanged {
            context.coordinator.currentlyEditing = isEditing
            context.coordinator.lastLoadedHTML = htmlContent
            context.coordinator.lastDarkMode = isDarkMode
            let styled = Self.styledHTML(htmlContent, editable: isEditing, isDark: isDarkMode)
            webView.loadHTMLString(styled, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var editedHTML: Binding<String>
        weak var webView: WKWebView?
        var currentlyEditing = false
        var lastLoadedHTML: String?
        var lastDarkMode: Bool?

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

    func extractHTML(from webView: WKWebView) async -> String? {
        try? await webView.evaluateJavaScript(
            "document.getElementById('content').innerHTML"
        ) as? String
    }

    static func execCommand(_ webView: WKWebView?, command: String, value: String? = nil) {
        guard let webView else { return }
        let valueArg = value.map { "'\($0)'" } ?? "null"
        webView.evaluateJavaScript(
            "document.execCommand('\(command)', false, \(valueArg))",
            completionHandler: nil
        )
    }

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

    private static func styledHTML(_ html: String, editable: Bool) -> String {
        let editableAttr = editable ? "contenteditable=\"true\"" : ""
        let editingCSS = editable ? """
            #content { outline: none; min-height: 200px; cursor: text; }
            #content:focus { box-shadow: inset 0 0 0 2px rgba(229, 0, 116, 0.12); border-radius: 6px; }
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
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
            --text-primary: #2c2c30;
            --text-secondary: #555560;
            --text-tertiary: #8e8e93;
            --heading: #1a2744;
            --brand: #E50074;
            --brand-light: #fef2f8;
            --brand-border: rgba(229, 0, 116, 0.15);
            --border: #d8dce3;
            --surface-elevated: #f8f8fa;
            --bg-blockquote: #fef6fb;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --text-primary: #f0f0f4;
                --text-secondary: #9e9ea8;
                --text-tertiary: #6c6c74;
                --heading: #c8d4e8;
                --brand: #ff3b8a;
                --brand-light: #1f0a15;
                --brand-border: rgba(255, 59, 138, 0.20);
                --border: #38383d;
                --surface-elevated: #222228;
                --bg-blockquote: #1f0e18;
            }
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif;
            font-size: 14.5px;
            line-height: 1.72;
            color: var(--text-primary);
            background: transparent;
            padding: 20px 16px;
            -webkit-font-smoothing: antialiased;
        }
        h1 { font-size: 21px; font-weight: 700; color: var(--heading); margin-bottom: 4px; letter-spacing: -0.3px; line-height: 1.3; }
        h1 + p, h1 + .datum { margin-top: 0; padding-bottom: 14px; border-bottom: 1.5px solid var(--border); margin-bottom: 16px; }
        h2 { font-size: 15.5px; font-weight: 700; color: var(--heading); margin-top: 24px; margin-bottom: 8px; letter-spacing: -0.1px; }
        h3 { font-size: 14.5px; font-weight: 700; color: var(--heading); margin-top: 20px; margin-bottom: 6px; }
        p { margin: 8px 0; }
        ul, ol { margin: 8px 0 8px 24px; }
        li { margin: 4px 0; }
        strong { font-weight: 600; color: var(--text-primary); }
        em { font-style: italic; color: var(--text-secondary); }
        table { border-collapse: collapse; width: 100%; margin: 16px 0; border-radius: 8px; overflow: hidden; border: 1px solid var(--border); }
        th, td { border: 1px solid var(--border); padding: 10px 14px; text-align: left; font-size: 13.5px; }
        th { background: var(--surface-elevated); font-weight: 600; font-size: 12.5px; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text-secondary); }
        blockquote { border-left: 3px solid var(--brand); margin: 16px 0; padding: 12px 20px; background: var(--bg-blockquote); border-radius: 0 8px 8px 0; font-style: italic; color: var(--text-secondary); }
        hr { border: none; height: 1px; background: var(--border); margin: 24px 0; }
        code { font-family: 'SF Mono', Menlo, monospace; font-size: 0.9em; background: var(--surface-elevated); padding: 2px 6px; border-radius: 4px; }
        pre { background: var(--surface-elevated); padding: 16px; border-radius: 8px; overflow-x: auto; margin: 12px 0; border: 1px solid var(--border); }
        pre code { background: none; padding: 0; }
        ::selection { background: rgba(229, 0, 116, 0.18); }
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
#endif

// MARK: - FormattingToolbar

struct FormattingToolbar: View {

    let webView: WKWebView?

    var body: some View {
        HStack(spacing: 2) {
            Group {
                formatButton(icon: "bold", command: "bold")
                formatButton(icon: "italic", command: "italic")
                formatButton(icon: "underline", command: "underline")
            }

            toolbarDivider

            Group {
                formatButton(icon: "list.bullet", command: "insertUnorderedList")
                formatButton(icon: "list.number", command: "insertOrderedList")
            }

            toolbarDivider

            Menu {
                Button("Kop 1") { EditableHTMLWebView.execCommand(webView, command: "formatBlock", value: "h1") }
                Button("Kop 2") { EditableHTMLWebView.execCommand(webView, command: "formatBlock", value: "h2") }
                Button("Kop 3") { EditableHTMLWebView.execCommand(webView, command: "formatBlock", value: "h3") }
                Divider()
                Button("Paragraaf") { EditableHTMLWebView.execCommand(webView, command: "formatBlock", value: "p") }
                Button("Citaat") { EditableHTMLWebView.execCommand(webView, command: "formatBlock", value: "blockquote") }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 44, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous)
                        .fill(Color.clear)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
        .padding(.horizontal, TS.Spacing.xs + 2)
        .padding(.vertical, TS.Spacing.xs)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.5), lineWidth: 1)
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.borderPrimary)
            .frame(width: 1, height: 18)
            .padding(.horizontal, TS.Spacing.xs)
    }

    private func formatButton(icon: String, command: String) -> some View {
        Button {
            EditableHTMLWebView.execCommand(webView, command: command)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 30, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous)
                        .fill(Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
