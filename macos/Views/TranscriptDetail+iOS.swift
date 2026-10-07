// TranscriptDetail+iOS.swift
// ThoughtVault
//
// iOS notule detail, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-notule-detail-northstar.jpg): back /
// "Notule" / share in the navigation bar, a header card with title, time and
// tags, the Notule / Transcript switch and a content card with the actions.
// The notule itself stays the rendered HTML (sections, action points and
// owners only exist inside that HTML). "Titel" keeps the existing AI title
// action next to the three NorthStar actions.

#if os(iOS)
import SwiftUI

extension TranscriptDetailView {

    private var hasNotule: Bool { !(fullTranscript.notuleHtml ?? "").isEmpty }
    private var hasRaw: Bool { !(fullTranscript.rawTranscription ?? "").isEmpty }

    var iosDetail: some View {
        VStack(spacing: 0) {
            progressBanners
                .padding(.horizontal, IOSMetric.gutter)
            headerCard
                .padding(.horizontal, IOSMetric.gutter)
                .padding(.top, 6)
            if hasNotule && hasRaw && !isEditingNotule {
                IOSSegmented(options: [(DetailTab.notule, "Notule", "doc.text"),
                                       (.raw, "Transcript", "waveform")],
                             selection: $selectedTab, height: 38)
                    .padding(.horizontal, IOSMetric.gutter)
                    .padding(.top, 14)
            }
            contentCard
                .padding(.horizontal, IOSMetric.gutter)
                .padding(.top, 14)
        }
        .background(IOSBackground())
        .preferredColorScheme(.dark)
        .navigationTitle("Notule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { shareContent() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Delen")
                .disabled(!hasNotule && !hasRaw)
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            IOSIconTile(systemName: "doc.text", size: 50)
            VStack(alignment: .leading, spacing: 5) {
                if isEditingTitle {
                    HStack(spacing: 8) {
                        TextField("Titel", text: $pendingTitle, axis: .vertical)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(IOSColor.text)
                            .lineLimit(1...3)
                            .onSubmit { Task { await saveTitle() } }
                        Button { Task { await saveTitle() } } label: {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(IOSColor.ready)
                        }
                        .accessibilityLabel("Titel opslaan")
                        Button { isEditingTitle = false } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(IOSColor.text3)
                        }
                        .accessibilityLabel("Bewerken annuleren")
                    }
                } else {
                    Button {
                        pendingTitle = fullTranscript.title
                        isEditingTitle = true
                    } label: {
                        Text(fullTranscript.title.isEmpty ? "Naamloze opname" : fullTranscript.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(IOSColor.text)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Tik om de titel te wijzigen")
                }
                Text(timeLine)
                    .font(.system(size: 14))
                    .foregroundStyle(IOSColor.text2)
                if !fullTranscript.tags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(fullTranscript.tags.enumerated()), id: \.offset) { index, tag in
                                tagChip(tag, index: index)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RadialGradient(colors: [Color(red: 0.30, green: 0.18, blue: 0.68).opacity(0.25), .clear],
                           center: UnitPoint(x: 0.8, y: 0), startRadius: 0, endRadius: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .iosCard(raised: true)
    }

    /// "Vandaag 14:00 – 14:42 · 42 min"
    private var timeLine: String {
        let date = fullTranscript.date
        guard let seconds = fullTranscript.duration, seconds > 0 else { return IOSFormat.day(date) }
        let end = date.addingTimeInterval(seconds)
        return "\(IOSFormat.day(date)) \u{2013} \(IOSFormat.time(end))  \u{00B7}  \(IOSFormat.minutes(seconds) ?? "")"
    }

    private func tagChip(_ tag: String, index: Int) -> some View {
        let palette: [(Color, Color)] = [
            (IOSColor.tile, IOSColor.lavender),
            (Color(red: 0.12, green: 0.12, blue: 0.27), IOSColor.text),
            (IOSColor.tileBlue.opacity(0.7), IOSColor.iconBlue),
        ]
        let (fill, text) = palette[index % palette.count]
        return Text(tag)
            .font(.system(size: 12.5))
            .foregroundStyle(text)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(IOSColor.borderViolet.opacity(0.6), lineWidth: 1))
    }

    // MARK: Content

    private var contentCard: some View {
        VStack(spacing: 0) {
            if !isLoadingDetail && !isEditingNotule && (hasNotule || hasRaw) {
                actionRow
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }
            Group {
                if isLoadingDetail {
                    VStack(spacing: 8) {
                        ProgressView().tint(IOSColor.lavender)
                        Text("Laden\u{2026}").font(.system(size: 13)).foregroundStyle(IOSColor.text2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    contentArea
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .iosCard()
        .padding(.bottom, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            actionTile(icon: "sparkles", label: "Titel") { Task { await generateTitle() } }
                .disabled(!hasNotule)
            if isRegenerating {
                VStack(spacing: 5) {
                    ProgressView().tint(IOSColor.lavender).frame(width: 50, height: 32)
                    Text("Bezig\u{2026}").font(.system(size: 11.5)).foregroundStyle(IOSColor.text2)
                }
            } else {
                actionTile(icon: "arrow.clockwise", label: "Regenereren") {
                    profileSheetMode = .regenerate
                    showProfileSheet = true
                }
            }
            Menu {
                Button("PDF", systemImage: "doc.richtext") { exportAsPDF() }
                Button("Markdown", systemImage: "doc.plaintext") { exportAsMarkdown() }
                Button("Exporteer naar Obsidian", systemImage: "tray.and.arrow.down") { exportToObsidian() }
                Button("Platte tekst", systemImage: "doc.text") { exportAsTXT() }
                Divider()
                Button("Kopieer tekst", systemImage: "doc.on.doc") { copyContent() }
            } label: {
                actionLabel(icon: "square.and.arrow.down", label: "Exporteren")
            }
            if hasNotule, let html = fullTranscript.notuleHtml {
                actionTile(icon: "pencil", label: "Bewerken") {
                    editedHTML = prepareNotuleContent(html)
                    withAnimation(TS.Animation.smooth) {
                        isEditingNotule = true
                        selectedTab = .notule
                    }
                }
            }
        }
    }

    private func actionTile(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(icon: icon, label: label) }
            .buttonStyle(.plain)
    }

    private func actionLabel(icon: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(IOSColor.text)
                .frame(width: 50, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(IOSColor.control))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(IOSColor.border, lineWidth: 1))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(IOSColor.text2)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}
#endif
