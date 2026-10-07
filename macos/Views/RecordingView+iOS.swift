// RecordingView+iOS.swift
// ThoughtVault
//
// iOS Opnemen, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-opnemen-northstar.jpg), which shows the
// live state: status and language pills, timer, the level-driven waveform,
// pause / stop / note, source-profile-live row, live transcript and live
// stats. The idle state uses the same components with the existing actions
// (profile, premium, participants, import, YouTube, saved recordings).
// Language and source are fixed on iOS (nl-NL, microphone), so their pills
// are read-only.

#if os(iOS)
import SwiftUI

extension RecordingView {

    private var isLive: Bool {
        recordingVM.recordingState.isRecording || recordingVM.recordingState == .preparing || recordingVM.recordingState == .stopping
    }

    var iosBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                IOSBrandBar()
                    .padding(.top, -10)
                    .padding(.horizontal, IOSMetric.gutter)
                titleRow
                    .padding(.top, 16)
                    .padding(.horizontal, IOSMetric.gutter)
                if !isLive {
                    VStack(spacing: 10) {
                        offlineStatusBanner
                        audioMixFallbackBanner
                        errorBanner
                    }
                    .padding(.horizontal, IOSMetric.gutter)
                }
                timerBlock
                    .padding(.top, 14)
                IOSLiveWave(isActive: recordingVM.recordingState == .recording,
                            levels: { recordingVM.audioLevels })
                    .frame(height: 130)
                    .padding(.top, -34)
                controls
                    .padding(.top, 4)
                    .padding(.horizontal, IOSMetric.gutter)
                if showNoteField && isLive {
                    iosNoteCard
                        .padding(.top, 18)
                        .padding(.horizontal, IOSMetric.gutter)
                }
                settingsRow
                    .padding(.top, 20)
                    .padding(.horizontal, IOSMetric.gutter)
                if isLive {
                    if recordingVM.isLiveTranscribing {
                        liveTranscriptCard
                            .padding(.top, 14)
                            .padding(.horizontal, IOSMetric.gutter)
                    }
                    liveStatsCard
                        .padding(.top, 14)
                        .padding(.horizontal, IOSMetric.gutter)
                } else {
                    idleOptions
                        .padding(.top, 14)
                        .padding(.horizontal, IOSMetric.gutter)
                }
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .iosScreen()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedReprocessRecording) { reprocessSheet(for: $0) }
        .sheet(isPresented: $showParticipantPicker) {
            ParticipantPickerSheet(selectedIDs: Bindable(recordingVM).selectedParticipantIDs)
        }
        .sheet(isPresented: $showSavedRecordings) {
            NavigationStack {
                ScrollView { unifiedBottomBar(isCompact: true).padding(TS.Spacing.md) }
                    .navigationTitle("Opgeslagen opnames")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gereed") { showSavedRecordings = false } } }
            }
            .sheet(item: $selectedReprocessRecording) { reprocessSheet(for: $0) }
        }
        .sheet(isPresented: $showYouTubeSection) {
            NavigationStack {
                ScrollView { youtubeInlineSection.padding(TS.Spacing.md) }
                    .navigationTitle("YouTube-video")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gereed") { showYouTubeSection = false } } }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await recordingVM.importAudioFile(url) }
            }
        }
        .confirmationDialog("Opname annuleren?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Annuleer opname", role: .destructive) {
                Task { await recordingVM.cancelRecording() }
            }
            Button("Doorgaan met opnemen", role: .cancel) {}
        } message: {
            Text("Je huidige opname wordt verwijderd. Dit kan niet ongedaan worden gemaakt.")
        }
    }

    // MARK: Title

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text("Opnemen")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(IOSColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            statusPill
            HStack(spacing: 7) {
                Image(systemName: "globe").font(.system(size: 13))
                Text("Nederlands").font(.system(size: 11.5))
            }
            .foregroundStyle(IOSColor.text)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(IOSColor.control.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(IOSColor.border, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Spreektaal: Nederlands")
        }
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            switch recordingVM.recordingState {
            case .recording: return ("OPNAME ACTIEF", IOSColor.ready)
            case .paused: return ("GEPAUZEERD", IOSColor.warning)
            case .preparing, .stopping, .uploading: return ("EVEN GEDULD", IOSColor.lavender)
            case .error: return ("FOUT", IOSColor.danger)
            case .idle: return ("KLAAR", IOSColor.text3)
            }
        }()
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 10.5, weight: .semibold)).kerning(0.3)
        }
        .foregroundStyle(IOSColor.text)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Capsule().fill(IOSColor.control.opacity(0.7)))
        .overlay(Capsule().strokeBorder(IOSColor.border, lineWidth: 1))
        .fixedSize()
    }

    // MARK: Timer

    private var timerBlock: some View {
        VStack(spacing: 8) {
            Text(formattedDuration)
                .font(.system(size: 56, weight: .light).monospacedDigit())
                .foregroundStyle(IOSColor.text)
                .contentTransition(.numericText())
            HStack(spacing: 3) {
                ForEach(0..<9, id: \.self) { k in
                    Capsule()
                        .fill(k < 5 ? IOSColor.lavender : IOSColor.lavender.opacity(0.4))
                        .frame(width: 3.5, height: [5, 8, 11, 14, 10, 5, 5, 5, 5][k])
                }
            }
            .frame(height: 14)
            .opacity(recordingVM.recordingState == .recording ? 1 : 0.35)
            .accessibilityHidden(true)
            Text(listenCaption)
                .font(.system(size: 14))
                .foregroundStyle(IOSColor.link)
        }
        .frame(maxWidth: .infinity)
    }

    private var listenCaption: String {
        switch recordingVM.recordingState {
        case .recording: return "Ik luister\u{2026}"
        case .paused: return "Gepauzeerd"
        case .preparing: return "Voorbereiden\u{2026}"
        case .stopping, .uploading: return "Opslaan\u{2026}"
        default: return "Klaar om op te nemen"
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch recordingVM.recordingState {
        case .recording:
            HStack(alignment: .top) {
                roundControl(icon: "pause.fill", label: "Pauzeer") { recordingVM.pauseRecording() }
                Spacer()
                stopControl
                Spacer()
                roundControl(icon: "flag", label: "Notitie", selected: showNoteField) { showNoteField.toggle() }
            }
            .padding(.horizontal, 20)
        case .paused:
            HStack(alignment: .top) {
                roundControl(icon: "play.fill", label: "Hervat") { recordingVM.resumeRecording() }
                Spacer()
                stopControl
                Spacer()
                roundControl(icon: "xmark", label: "Annuleer", tint: IOSColor.danger) { showCancelConfirm = true }
            }
            .padding(.horizontal, 20)
        case .idle, .error:
            VStack(spacing: 12) {
                Button { Task { await recordingVM.startRecording() } } label: {
                    IOSMicOrb(size: 118)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start opname")
                Text("Start opname")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IOSColor.text)
            }
            .frame(maxWidth: .infinity)
        default:
            HStack(spacing: 10) {
                ProgressView().tint(IOSColor.lavender)
                Text("Even geduld\u{2026}").font(.system(size: 14)).foregroundStyle(IOSColor.text2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
        }
    }

    private func roundControl(icon: String, label: String, selected: Bool = false, tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(selected ? IOSColor.tile : Color(red: 0.12, green: 0.12, blue: 0.27)))
                    .overlay(Circle().strokeBorder(IOSColor.borderViolet, lineWidth: 1))
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(IOSColor.text)
            }
            .frame(width: 90)
        }
        .buttonStyle(.plain)
    }

    private var stopControl: some View {
        Button { Task { await recordingVM.stopAndUpload() } } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 0.62, green: 0.13, blue: 0.24), Color(red: 0.36, green: 0.07, blue: 0.16)],
                                             center: .center, startRadius: 4, endRadius: 40))
                    Circle().strokeBorder(Color(red: 1.0, green: 0.38, blue: 0.45), lineWidth: 2)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.62, blue: 0.66))
                        .frame(width: 20, height: 20)
                }
                .frame(width: 72, height: 72)
                .shadow(color: Color(red: 1.0, green: 0.25, blue: 0.35).opacity(0.55), radius: 14)
                Text("Stop en verwerk")
                    .font(.system(size: 12.5))
                    .foregroundStyle(IOSColor.text)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, -7)
    }

    // MARK: Note

    private var iosNoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notitie")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IOSColor.text)
            TextField("Bijv. actiepunt of context\u{2026}", text: Bindable(recordingVM).quickNote, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(IOSColor.text)
                .lineLimit(2...4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(IOSColor.control))
        }
        .padding(14)
        .iosCard()
    }

    // MARK: Source / profile / live row

    private var settingsRow: some View {
        HStack(spacing: 0) {
            settingCell(icon: "mic", label: "Bron") {
                Text("Microfoon").font(.system(size: 13)).foregroundStyle(IOSColor.text).lineLimit(1).minimumScaleFactor(0.85)
            }
            cellDivider
            settingCell(icon: "waveform", label: "Opnameprofiel") {
                if isLive {
                    Text(recordingVM.selectedProfile?.name ?? "Geen").font(.system(size: 13)).foregroundStyle(IOSColor.text).lineLimit(1)
                } else {
                    Menu {
                        ForEach(recordingVM.availableProfiles) { profile in
                            Button(profile.name) { recordingVM.selectedProfile = profile }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(recordingVM.selectedProfile?.name ?? "Kies").lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(IOSColor.text)
                    }
                    .disabled(recordingVM.availableProfiles.isEmpty)
                }
            }
            // Same setting as "Transcriptie op apparaat": it also runs the live
            // transcript, so the cell is labelled by what it really switches.
            if OnDeviceTranscriber.shared.isAvailable() {
            cellDivider
            settingCell(icon: "doc.plaintext", label: "Op apparaat") {
                HStack(spacing: 4) {
                    Text(preferOnDeviceTranscription ? "Aan" : "Uit")
                        .font(.system(size: 13))
                        .foregroundStyle(preferOnDeviceTranscription ? IOSColor.ready : IOSColor.text2)
                    Spacer(minLength: 0)
                    Toggle("Transcriptie op apparaat", isOn: $preferOnDeviceTranscription)
                        .labelsHidden()
                        .tint(IOSColor.violet)
                        .scaleEffect(0.7, anchor: .trailing)
                        .frame(width: 36)
                        .disabled(isLive)
                }
            }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .iosCard(raised: true)
    }

    private var cellDivider: some View {
        Rectangle().fill(IOSColor.divider).frame(width: 1, height: 44)
    }

    private func settingCell<V: View>(icon: String, label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(IOSColor.text)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(IOSColor.control))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(IOSColor.border, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(IOSColor.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                value()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }

    // MARK: Live cards

    private var liveTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IOSIconTile(systemName: "doc.text", size: 32)
                Text("Live transcriptie")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IOSColor.text)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(IOSColor.ready).frame(width: 7, height: 7)
                    Text("Live").font(.system(size: 13)).foregroundStyle(IOSColor.text2)
                }
            }
            let text = recordingVM.liveTranscriptText
            Text(text.isEmpty ? "Luisteren\u{2026}" : text)
                .font(.system(size: 16))
                .lineSpacing(3)
                .foregroundStyle(text.isEmpty ? IOSColor.text3 : IOSColor.text)
                .lineLimit(5)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .iosCard(raised: true)
    }

    private var liveStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(IOSColor.iconViolet)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(IOSColor.tile))
                Text("Live opname")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IOSColor.text)
            }
            HStack(spacing: 0) {
                statCell(icon: "clock", label: "Duur") {
                    Text(formattedDuration).monospacedDigit()
                }
                cellDivider
                statCell(icon: "chart.bar", label: "Geluidsniveau") {
                    IOSLevelMeter(levels: { recordingVM.audioLevels }, isActive: recordingVM.recordingState == .recording)
                }
                cellDivider
                statCell(icon: "doc.text", label: "Profiel") {
                    Text(recordingVM.selectedProfile?.name ?? "Geen").lineLimit(1)
                }
            }
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(IOSColor.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(IOSColor.border, lineWidth: 1))
        }
        .padding(14)
        .iosCard(raised: true)
    }

    private func statCell<V: View>(icon: String, label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(IOSColor.iconViolet)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(IOSColor.tile))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 10)).foregroundStyle(IOSColor.text2).lineLimit(1).minimumScaleFactor(0.8)
                value().font(.system(size: 13)).foregroundStyle(IOSColor.text)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Idle options

    private var idleOptions: some View {
        VStack(spacing: 0) {
            IOSRow(icon: "sparkles", title: "Premium model", subtitle: "Betere kwaliteit, langzamer") {
                Toggle("Premium model", isOn: Bindable(recordingVM).usePremium).labelsHidden().tint(IOSColor.violet)
            }
            IOSDivider()
            Button { showParticipantPicker = true } label: {
                IOSRow(icon: "person.2", title: "Deelnemers", subtitle: participantsSummary) { IOSChevron() }
            }
            .buttonStyle(.plain)
            IOSDivider()
            Button { showImporter = true } label: {
                IOSRow(icon: "square.and.arrow.down", title: "Audiobestand importeren") { IOSChevron() }
            }
            .buttonStyle(.plain)
            if recordingVM.isYouTubeEnabled {
                IOSDivider()
                Button { showYouTubeSection = true } label: {
                    IOSRow(icon: "play.rectangle", title: "YouTube-video") { IOSChevron() }
                }
                .buttonStyle(.plain)
            }
            IOSDivider()
            Button { showSavedRecordings = true } label: {
                IOSRow(icon: "tray.full", title: "Opgeslagen opnames", subtitle: savedSummary) { IOSChevron() }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .iosCard()
    }

    private var participantsSummary: String {
        switch recordingVM.selectedParticipantIDs.count {
        case 0: return "Geen personen gekozen"
        case 1: return "1 persoon"
        case let n: return "\(n) personen"
        }
    }

    private var savedSummary: String {
        let saved = recordingVM.savedRecordings.count, busy = recordingVM.activeTasks.count
        if saved == 0 && busy == 0 { return "Geen opnames" }
        return [saved > 0 ? "\(saved) bewaard" : nil, busy > 0 ? "\(busy) in verwerking" : nil]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Live wave and level meter

/// Full-width live waveform: the shared level-driven WaveformView over a soft
/// violet haze. Quiet when not recording.
struct IOSLiveWave: View {
    let isActive: Bool
    let levels: () -> [Float]

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.36, green: 0.18, blue: 0.80).opacity(isActive ? 0.35 : 0.15), .clear],
                           center: .center, startRadius: 0, endRadius: 220)
                .scaleEffect(x: 1.6, y: 0.6)
            WaveformView(levelsProvider: levels, isActive: isActive, maxFPS: 60)
        }
        .accessibilityHidden(true)
    }
}

/// Nine bars lit by the current input level.
struct IOSLevelMeter: View {
    let levels: () -> [Float]
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { _ in
            let level = isActive ? Double(levels().last ?? 0) : 0
            let lit = Int((level * 9 * 1.3).rounded())
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<9, id: \.self) { k in
                    Capsule()
                        .fill(k < lit ? IOSColor.lavender : IOSColor.lavender.opacity(0.25))
                        .frame(width: 3, height: 8 + CGFloat(min(k, 8 - k)) * 1.5)
                }
            }
            .frame(height: 16)
        }
        .accessibilityLabel("Geluidsniveau")
    }
}
#endif
