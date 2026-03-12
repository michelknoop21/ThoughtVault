// NotuleResultView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Displays completed transcription result with HTML notule rendering,
// export options (PDF, TXT, DOCX, Share), and raw transcription tab.

import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#endif

// MARK: - NotuleResultView

struct NotuleResultView: View {

    let task: TranscriptTask
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab: ResultTab = .notule
    @State private var showExportMenu: Bool = false
    @State private var exportError: String? = nil
    @State private var showAddTag: Bool = false
    @State private var newTagText: String = ""

    enum ResultTab: String, CaseIterable {
        case notule = "Notulen"
        case transcriptie = "Transcriptie"

        var icon: String {
            switch self {
            case .notule:       return "doc.richtext"
            case .transcriptie: return "text.alignleft"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            resultMetaBar
            tabBar

            VStack(spacing: TS.Spacing.md) {
                switch selectedTab {
                case .notule:
                    notuleView
                case .transcriptie:
                    transcriptieView
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(macOS)
            YingaFooter()
                .background(Color.surfacePrimary)
                .overlay(alignment: .top) { Divider() }
            #endif
        }
        .background(Color.surfacePrimary)
        .onAppear {
            let hasNotule = !(task.notuleHtml ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasRaw = !(task.rawTranscription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasNotule && hasRaw {
                selectedTab = .transcriptie
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: TS.Spacing.xs) {
                        Image(systemName: "chevron.left")
                        Text("Terug")
                    }
                    .font(TS.Font.bodyMedium)
                    .foregroundStyle(Color.brandPrimary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(task.status == .completed ? "Notulen klaar" : "Resultaat")
                    .font(TS.Font.headlineBold)
                    .foregroundStyle(Color.labelPrimary)

                Spacer()

                HStack(spacing: TS.Spacing.sm) {
                    Button {
                        showAddTag.toggle()
                    } label: {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "plus")
                            Text("Tag")
                        }
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(Color.brandSecondary)
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, TS.Spacing.xs)
                        .background {
                            Capsule()
                                .fill(Color.accentBgSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showAddTag) {
                        addTagPopover
                    }

                    Button {
                        showExportMenu = true
                    } label: {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Exporteer")
                        }
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, TS.Spacing.xs)
                        .background {
                            Capsule()
                                .fill(Color.brandOrange)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showExportMenu, arrowEdge: .top) {
                        exportMenuContent
                    }
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
            .background(Color.surfacePrimary)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }

    private var resultMetaBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TS.Spacing.xs) {
                metaPill(icon: "waveform", text: task.status.displayName, color: task.status == .error ? Color.statusError : Color.brandPrimary)
                if let createdAt = task.createdAt {
                    metaPill(icon: "calendar", text: formattedDate(createdAt), color: Color.labelSecondary)
                }
                if let profileId = task.profileId, !profileId.isEmpty {
                    metaPill(icon: "person.fill", text: profileId.capitalized, color: Color.brandSecondary)
                }
                if !task.tags.isEmpty {
                    ForEach(task.tags.prefix(3), id: \.self) { tag in
                        metaPill(icon: "tag.fill", text: tag, color: Color.brandOrange)
                    }
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.xs)
        }
        .background(Color.surfaceSecondary.opacity(0.65))
    }

    private func metaPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(TS.Font.captionMedium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, TS.Spacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.10)))
    }

    // MARK: - Add Tag Popover

    private var addTagPopover: some View {
        VStack(spacing: TS.Spacing.sm) {
            Text("Tag toevoegen")
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelPrimary)

            TextField("Tagnaam...", text: $newTagText)
                .textFieldStyle(.plain)
                .font(TS.Font.body)
                .padding(TS.Spacing.sm)
                .background(Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.xs))
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.xs)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                }

            HStack {
                Button("Annuleer") {
                    newTagText = ""
                    showAddTag = false
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Toevoegen") {
                    if !newTagText.isEmpty {
                        Task {
                            var updatedTags = task.tags
                            updatedTags.append(newTagText)
                            do {
                                try await APIService.shared.updateTranscriptTags(taskId: task.taskId, tags: updatedTags)
                            } catch {
                                exportError = "Tag opslaan mislukt: \(error.localizedDescription)"
                            }
                        }
                        newTagText = ""
                        showAddTag = false
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newTagText.isEmpty)
            }
        }
        .padding(TS.Spacing.md)
        .frame(width: 260)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: TS.Spacing.xs) {
            ForEach(ResultTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(TS.Animation.smooth) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: TS.Spacing.xs) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                            .font(TS.Font.footnoteSemibold)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? Color.brandPrimary : Color.labelSecondary)
                    .padding(.vertical, TS.Spacing.sm)
                    .padding(.horizontal, TS.Spacing.md)
                    .background {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .fill(selectedTab == tab ? Color.accentBgPrimary : Color.surfaceSecondary)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(selectedTab == tab ? Color.brandPrimary.opacity(0.35) : Color.borderPrimary.opacity(0.5), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TS.Spacing.md)
        .padding(.top, TS.Spacing.sm)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var notuleView: some View {
        if let html = task.notuleHtml, !html.isEmpty {
            HTMLWebView(htmlContent: html, isDarkMode: colorScheme == .dark)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                        .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
                }
        } else {
            emptyNotuleView
        }
    }

    // MARK: - Transcriptie View

    private var transcriptieView: some View {
        Group {
            if let raw = task.rawTranscription, !raw.isEmpty {
                VStack(spacing: TS.Spacing.sm) {
                    HStack {
                        Text("Ruwe transcriptie")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Button("Kopieer") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(raw, forType: .string)
                            #else
                            UIPasteboard.general.string = raw
                            #endif
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: TS.Spacing.md) {
                            Text(raw)
                                .font(TS.Font.body)
                                .foregroundStyle(Color.labelPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(TS.Spacing.md)
                    }
                    .background(Color.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                            .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
                    }
                }
            } else {
                VStack(spacing: TS.Spacing.md) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.labelTertiary)
                    Text("Geen transcriptie beschikbaar")
                        .font(TS.Font.callout)
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Empty Notule

    private var emptyNotuleView: some View {
        VStack(spacing: TS.Spacing.md) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 40))
                .foregroundStyle(Color.labelTertiary)
            Text("Geen notulen beschikbaar")
                .font(TS.Font.callout)
                .foregroundStyle(Color.labelSecondary)
            Text("De verwerking is mogelijk nog niet voltooid.")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.45), lineWidth: 1)
        }
    }

    // MARK: - Export Menu

    private var exportMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Exporteren als")
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.labelSecondary)
                .padding(.horizontal, TS.Spacing.md)
                .padding(.top, TS.Spacing.md)
                .padding(.bottom, TS.Spacing.sm)

            exportButton(icon: "doc.fill", title: "PDF", action: exportAsPDF)
            Divider()
            exportButton(icon: "doc.plaintext", title: "Platte tekst (.txt)", action: exportAsTXT)
            Divider()
            exportButton(icon: "doc.richtext.fill", title: "Word document (.docx)", action: exportAsDOCX)
            Divider()
            exportButton(icon: "square.and.arrow.up", title: "Delen...", action: shareContent)

            if let error = exportError {
                Text(error)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.statusError)
                    .padding(.horizontal, TS.Spacing.md)
                    .padding(.bottom, TS.Spacing.sm)
            }
        }
        .frame(width: 240)
        .padding(.bottom, TS.Spacing.sm)
    }

    private func exportButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 20)
                Text(title)
                    .font(TS.Font.body)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export Actions

    private func exportAsPDF() {
        showExportMenu = false
        guard let html = task.notuleHtml else { return }

        #if os(macOS)
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 595, height: 842) // A4
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        webView.loadHTMLString(styledHTML(html), baseURL: nil)

        // Brief delay for WKWebView to finish rendering before printing
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            let op = webView.printOperation(with: printInfo)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.run()
        }
        #else
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842))
        webView.loadHTMLString(styledHTML(html), baseURL: nil)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            let printFormatter = webView.viewPrintFormatter()
            let printController = UIPrintInteractionController.shared
            printController.printFormatter = printFormatter
            printController.present(animated: true)
        }
        #endif
    }

    private func exportAsTXT() {
        showExportMenu = false
        // Strip HTML tags
        guard let html = task.notuleHtml else { return }
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let decoded = stripped
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "notulen.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try decoded.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                exportError = "Exporteren mislukt: \(error.localizedDescription)"
            }
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("notulen.txt")
        do {
            try decoded.write(to: tempURL, atomically: true, encoding: .utf8)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            exportError = "Exporteren mislukt: \(error.localizedDescription)"
        }
        #endif
    }

    private func exportAsDOCX() {
        showExportMenu = false
        exportError = "DOCX-export is nog niet beschikbaar. Gebruik PDF of tekst als alternatief."
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { exportError = nil }
        }
    }

    private func shareContent() {
        showExportMenu = false
        guard let html = task.notuleHtml else { return }
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        #if os(macOS)
        let picker = NSSharingServicePicker(items: [stripped])
        if let window = NSApp.keyWindow, let view = window.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
        #else
        let activityVC = UIActivityViewController(activityItems: [stripped], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
    }

    private func styledHTML(_ html: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        :root {
            --text-primary: #1a1a1a;
            --text-heading: #333;
            --text-subtle: #555;
            --brand: #E50074;
            --border: #e0e0e0;
            --surface: #f8f8f8;
            --surface-light: #f5f5f5;
            --bg-blockquote: #fef6fb;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --text-primary: #f0f0f4;
                --text-heading: #c8d4e8;
                --text-subtle: #9e9ea8;
                --brand: #ff3b8a;
                --border: #38383d;
                --surface: #222228;
                --surface-light: #222228;
                --bg-blockquote: #1f0e18;
            }
        }
        body { font-family: -apple-system, Helvetica Neue, Arial, sans-serif; font-size: 12pt; line-height: 1.6; color: var(--text-primary); margin: 0; padding: 20pt; }
        h1 { font-size: 18pt; font-weight: 700; color: var(--brand); margin-bottom: 12pt; }
        h2 { font-size: 14pt; font-weight: 600; color: var(--text-heading); margin-top: 16pt; }
        h3 { font-size: 12pt; font-weight: 600; color: var(--text-subtle); margin-top: 12pt; }
        p  { margin: 6pt 0; }
        ul, ol { margin: 6pt 0; padding-left: 20pt; }
        li { margin: 3pt 0; }
        table { border-collapse: collapse; width: 100%; margin: 12pt 0; }
        th, td { border: 1px solid var(--border); padding: 6pt 8pt; text-align: left; }
        th { background: var(--surface-light); font-weight: 600; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - HTMLWebView

#if os(macOS)
struct HTMLWebView: NSViewRepresentable {
    let htmlContent: String
    let isDarkMode: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let darkClass = isDarkMode ? "dark" : ""
        let styled = """
        <!DOCTYPE html>
        <html class="\(darkClass)">
        <head>
        <meta charset="utf-8">
        <style>
        :root {
            --text-primary: #1a1a1a;
            --text-heading: #333;
            --text-subtle: #555;
            --brand: #E50074;
            --border: #e0e0e0;
            --surface: #f8f8f8;
            --surface-light: #f5f5f5;
            --bg-blockquote: #fef6fb;
        }
        html.dark {
            --text-primary: #f0f0f4;
            --text-heading: #c8d4e8;
            --text-subtle: #9e9ea8;
            --brand: #ff3b8a;
            --border: #38383d;
            --surface: #222228;
            --surface-light: #222228;
            --bg-blockquote: #1f0e18;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
            font-size: 14px;
            line-height: 1.65;
            color: var(--text-primary);
            background: transparent;
            padding: 24px;
        }
        h1 { font-size: 24px; font-weight: 700; color: var(--brand); margin-bottom: 12px; padding-bottom: 8px; border-bottom: 2px solid var(--brand); }
        h2 { font-size: 18px; font-weight: 600; color: var(--text-heading); margin-top: 24px; margin-bottom: 8px; }
        h3 { font-size: 15px; font-weight: 600; color: var(--text-subtle); margin-top: 16px; margin-bottom: 6px; }
        p  { margin: 8px 0; }
        ul, ol { margin: 8px 0 8px 20px; }
        li { margin: 4px 0; }
        strong { font-weight: 600; }
        em { font-style: italic; color: var(--text-subtle); }
        table { border-collapse: collapse; width: 100%; margin: 12px 0; }
        th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
        th { background: var(--surface); font-weight: 600; }
        blockquote { border-left: 3px solid var(--brand); margin: 12px 0; padding: 8px 16px; background: var(--bg-blockquote); }
        </style>
        </head>
        <body>\(htmlContent)</body>
        </html>
        """
        webView.loadHTMLString(styled, baseURL: nil)
    }
}
#else
struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    let isDarkMode: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let darkClass = isDarkMode ? "dark" : ""
        let styled = """
        <!DOCTYPE html>
        <html class="\(darkClass)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
            --text-primary: #1a1a1a;
            --text-heading: #333;
            --text-subtle: #555;
            --brand: #E50074;
            --border: #e0e0e0;
            --surface: #f8f8f8;
            --surface-light: #f5f5f5;
            --bg-blockquote: #fef6fb;
        }
        html.dark {
            --text-primary: #f0f0f4;
            --text-heading: #c8d4e8;
            --text-subtle: #9e9ea8;
            --brand: #ff3b8a;
            --border: #38383d;
            --surface: #222228;
            --surface-light: #222228;
            --bg-blockquote: #1f0e18;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
            font-size: 14px;
            line-height: 1.65;
            color: var(--text-primary);
            background: transparent;
            padding: 16px;
        }
        h1 { font-size: 22px; font-weight: 700; color: var(--brand); margin-bottom: 12px; padding-bottom: 8px; border-bottom: 2px solid var(--brand); }
        h2 { font-size: 18px; font-weight: 600; color: var(--text-heading); margin-top: 24px; margin-bottom: 8px; }
        h3 { font-size: 15px; font-weight: 600; color: var(--text-subtle); margin-top: 16px; margin-bottom: 6px; }
        p  { margin: 8px 0; }
        ul, ol { margin: 8px 0 8px 20px; }
        li { margin: 4px 0; }
        strong { font-weight: 600; }
        em { font-style: italic; color: var(--text-subtle); }
        table { border-collapse: collapse; width: 100%; margin: 12px 0; }
        th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
        th { background: var(--surface); font-weight: 600; }
        blockquote { border-left: 3px solid var(--brand); margin: 12px 0; padding: 8px 16px; background: var(--bg-blockquote); }
        </style>
        </head>
        <body>\(htmlContent)</body>
        </html>
        """
        webView.loadHTMLString(styled, baseURL: nil)
    }
}
#endif

// MARK: - Preview

#Preview {
    NotuleResultView(
        task: TranscriptTask(
            id: "preview",
            taskId: "preview-task",
            status: .completed,
            rawTranscription: "Dit is de ruwe transcriptie van de vergadering.",
            notuleHtml: "<h1>Vergadernotulen</h1><h2>Actiepunten</h2><ul><li>Item 1 — <strong>Michel</strong> — 15 maart</li><li>Item 2 — <strong>Team</strong> — einde sprint</li></ul><p>Volgende vergadering: <em>woensdag 12 maart 10:00</em></p>",
            profileId: "zakelijk"
        ),
        onDismiss: {}
    )
    .environment(RecordingViewModel())
    .frame(width: 700, height: 600)
}
