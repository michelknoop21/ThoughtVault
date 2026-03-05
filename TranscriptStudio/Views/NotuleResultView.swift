// NotuleResultView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Displays completed transcription result with HTML notule rendering,
// export options (PDF, TXT, DOCX, Share), and raw transcription tab.

import SwiftUI
import WebKit

// MARK: - NotuleResultView

struct NotuleResultView: View {

    let task: TranscriptTask
    let onDismiss: () -> Void

    @Environment(RecordingViewModel.self) var recordingVM

    @State private var selectedTab: ResultTab = .notule
    @State private var showExportMenu: Bool = false
    @State private var isExporting: Bool = false
    @State private var exportError: String? = nil
    @State private var isEditing: Bool = false
    @State private var editableNotuleHtml: String = ""
    @State private var showAddTag: Bool = false
    @State private var newTagText: String = ""
    @Namespace private var tabNamespace

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
            // Toolbar
            toolbar

            // Tab selector
            tabBar

            // Content
            Group {
                switch selectedTab {
                case .notule:
                    if let html = task.notuleHtml, !html.isEmpty {
                        ZStack(alignment: .topTrailing) {
                            HTMLWebView(htmlContent: html)

                            // Edit toggle button
                            Button {
                                isEditing.toggle()
                                if isEditing {
                                    editableNotuleHtml = html
                                }
                            } label: {
                                Image(systemName: isEditing ? "xmark" : "pencil")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(isEditing ? Color.statusError : Color.brandPrimary)
                                    .padding(TS.Spacing.sm)
                                    .background {
                                        Circle()
                                            .fill(Color.surfaceSecondary)
                                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .padding(TS.Spacing.md)
                        }
                    } else {
                        emptyNotuleView
                    }
                case .transcriptie:
                    transcriptieView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.surfacePrimary)
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

                Text("Resultaat")
                    .font(TS.Font.headlineBold)
                    .foregroundStyle(Color.labelPrimary)

                Spacer()

                HStack(spacing: TS.Spacing.sm) {
                    // Add tag button
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

                    // Hertranscribeer button
                    Button {
                        // TODO: trigger retranscription
                    } label: {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "arrow.clockwise")
                            Text("Hertranscribeer")
                        }
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, TS.Spacing.xs)
                        .background {
                            Capsule()
                                .fill(Color.accentBgPrimary)
                        }
                    }
                    .buttonStyle(.plain)

                    // Export button
                    Button {
                        showExportMenu = true
                    } label: {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Deel & Exporteer")
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
            .padding(.vertical, TS.Spacing.sm + 2)
            .background(Color.surfacePrimary)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
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
                            try? await APIService.shared.updateTranscriptTags(id: task.id, tags: updatedTags)
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
        HStack(spacing: 0) {
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
                    .foregroundStyle(selectedTab == tab ? Color.brandPrimary : Color.labelSecondary)
                    .padding(.vertical, TS.Spacing.sm)
                    .padding(.horizontal, TS.Spacing.md)
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Rectangle()
                                .fill(Color.brandPrimary)
                                .frame(height: 2)
                                .matchedGeometryEffect(id: "resultTabIndicator", in: tabNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(Color.surfaceSecondary)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Transcriptie View

    private var transcriptieView: some View {
        Group {
            if let raw = task.rawTranscription, !raw.isEmpty {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: TS.Spacing.md) {
                            Text(raw)
                                .font(TS.Font.body)
                                .foregroundStyle(Color.labelPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(TS.Spacing.lg)
                    }

                    // Action buttons
                    HStack(spacing: TS.Spacing.sm) {
                        Spacer()
                        Button("Kopieer") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(raw, forType: .string)
                            #endif
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button("Sluiten") {
                            onDismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(TS.Spacing.md)
                    .background(Color.surfacePrimary)
                    .overlay(alignment: .top) { Divider() }
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

        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 595, height: 842) // A4
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        webView.loadHTMLString(styledHTML(html), baseURL: nil)

        // Brief delay for render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let op = webView.printOperation(with: printInfo)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.run()
        }
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

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "notulen.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? decoded.write(to: url, atomically: true, encoding: .utf8)
        }
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

        let picker = NSSharingServicePicker(items: [stripped])
        if let window = NSApp.keyWindow, let view = window.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    private func styledHTML(_ html: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { font-family: -apple-system, Helvetica Neue, Arial, sans-serif; font-size: 12pt; line-height: 1.6; color: #1a1a1a; margin: 0; padding: 20pt; }
        h1 { font-size: 18pt; font-weight: 700; color: #E50074; margin-bottom: 12pt; }
        h2 { font-size: 14pt; font-weight: 600; margin-top: 16pt; }
        h3 { font-size: 12pt; font-weight: 600; margin-top: 12pt; }
        p  { margin: 6pt 0; }
        ul, ol { margin: 6pt 0; padding-left: 20pt; }
        li { margin: 3pt 0; }
        table { border-collapse: collapse; width: 100%; margin: 12pt 0; }
        th, td { border: 1px solid #ddd; padding: 6pt 8pt; text-align: left; }
        th { background: #f5f5f5; font-weight: 600; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }
}

// MARK: - HTMLWebView

struct HTMLWebView: NSViewRepresentable {
    let htmlContent: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let styled = """
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
        h1 { font-size: 24px; font-weight: 700; color: #E50074; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 2px solid #E50074; }
        h2 { font-size: 18px; font-weight: 600; color: #333; margin-top: 24px; margin-bottom: 8px; }
        h3 { font-size: 15px; font-weight: 600; color: #555; margin-top: 16px; margin-bottom: 6px; }
        p  { margin: 8px 0; }
        ul, ol { margin: 8px 0 8px 20px; }
        li { margin: 4px 0; }
        strong { font-weight: 600; }
        em { font-style: italic; color: #555; }
        table { border-collapse: collapse; width: 100%; margin: 12px 0; }
        th, td { border: 1px solid #e0e0e0; padding: 8px 12px; text-align: left; }
        th { background: #f8f8f8; font-weight: 600; }
        blockquote { border-left: 3px solid #E50074; margin: 12px 0; padding: 8px 16px; background: #fef6fb; }
        </style>
        </head>
        <body>\(htmlContent)</body>
        </html>
        """
        webView.loadHTMLString(styled, baseURL: nil)
    }
}

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
