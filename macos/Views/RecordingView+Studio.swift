// RecordingView+Studio.swift
// ThoughtVault
//
// macOS Opnemen screen, reconstructed from the approved NorthStar (2026-09-29):
// a wide recording workspace (status, timer, light-thread waveform, transport
// controls, control bar) next to a fixed inspector (RecordingView+Inspector).
// Every control maps onto existing RecordingViewModel behaviour; nothing here
// introduces new product logic. Geometry values are the NorthStar's, measured
// at a 1478 x 880 window.

#if os(macOS)
import SwiftUI

/// Colours sampled from the approved NorthStar for this screen only.
enum StudioColor {
    static let workspaceTop = Color(red: 0.043, green: 0.067, blue: 0.157)
    static let workspaceBottom = Color(red: 0.035, green: 0.055, blue: 0.133)
    static let inspector = Color(red: 0.055, green: 0.090, blue: 0.157)
    static let panel = Color(red: 0.063, green: 0.094, blue: 0.165)
    static let row = Color(red: 0.106, green: 0.133, blue: 0.212)
    static let rowHover = Color(red: 0.137, green: 0.169, blue: 0.271)
    static let pill = Color(red: 0.071, green: 0.094, blue: 0.188)
    static let group = Color(red: 0.071, green: 0.094, blue: 0.188)
    static let iconCircle = Color(red: 0.122, green: 0.145, blue: 0.259)
    static let control = Color(red: 0.133, green: 0.153, blue: 0.259)
    static let hairline = Color(red: 0.47, green: 0.51, blue: 0.75).opacity(0.22)
    static let border = Color(red: 0.35, green: 0.39, blue: 0.59).opacity(0.45)
    static let divider = Color(red: 0.31, green: 0.35, blue: 0.59).opacity(0.55)
    static let text2 = Color(red: 0.788, green: 0.800, blue: 0.878)
    static let text3 = Color(red: 0.647, green: 0.663, blue: 0.769)
    static let live = Color(red: 0.227, green: 0.918, blue: 0.345)
    static let liveText = Color(red: 0.255, green: 0.643, blue: 0.345)
    static let violet = Color(red: 0.686, green: 0.314, blue: 0.992)
    static let levelOn = Color(red: 0.604, green: 0.306, blue: 0.941)
    static let levelOff = Color(red: 0.227, green: 0.247, blue: 0.384)
}

/// The NorthStar has no window title; the traffic lights stay. Also used by Home.
struct HiddenWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content.navigationTitle("")
        }
    }
}

/// NorthStar geometry (measured at a 930 x 880 workspace) with the fallbacks a
/// smaller window needs: `regular` is the approved composition; `medium` drops
/// the control-bar icons; `narrow` keeps icon-only controls. Low windows move
/// the top and bottom clusters closer and give the wave what is left.
struct StudioLayout {
    enum Tier { case regular, medium, narrow }
    let w: CGFloat
    let h: CGFloat

    var tier: Tier { w >= 880 ? .regular : (w >= 500 ? .medium : .narrow) }
    var lowHeight: Bool { h < 720 }
    var inset: CGFloat { tier == .narrow ? 20 : 45 }
    var trailingInset: CGFloat { tier == .narrow ? 20 : 32 }
    var pillTop: CGFloat { lowHeight ? 24 : 45 }
    var timerSize: CGFloat { lowHeight ? 64 : 85 }
    var timerY: CGFloat { lowHeight ? 124 : 208 }
    var listenY: CGFloat { lowHeight ? 196 : 302 }
    var transportY: CGFloat { lowHeight ? h - 190 : h - 235 }
    var barBottom: CGFloat { lowHeight ? 20 : 37 }
    var transportItemWidth: CGFloat { min(164, (w - 2 * inset) / 3) }
    var waveY: CGFloat { lowHeight ? (listenY + 20 + transportY - 65) / 2 : h * 0.483 }
    var waveHeight: CGFloat { lowHeight ? max(60, transportY - 65 - listenY + 20) : 280 }
}

/// Pressed-state scale for the round transport controls.
struct StudioPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(TS.Animation.quick, value: configuration.isPressed)
    }
}

/// NorthStar switch: 47 x 28, violet when on.
struct StudioSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Color(red: 0.624, green: 0.286, blue: 0.992) : Color(red: 0.204, green: 0.227, blue: 0.353))
                .frame(width: 47, height: 28)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 22, height: 22).padding(3)
                }
                .animation(TS.Animation.quick, value: configuration.isOn)
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension RecordingView {

    // MARK: Composition

    var studioView: some View {
        HStack(spacing: 0) {
            studioWorkspace
            Rectangle().fill(StudioColor.divider).frame(width: 1)
            studioInspector
                .frame(width: 309)
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(HiddenWindowTitle())
        .sheet(isPresented: $showParticipantPicker) {
            ParticipantPickerSheet(selectedIDs: Bindable(recordingVM).selectedParticipantIDs)
        }
        .sheet(isPresented: $showSavedRecordings) {
            studioSheet(title: "Opgeslagen opnames", isPresented: $showSavedRecordings) {
                ScrollView { unifiedBottomBar(isCompact: false).padding(TS.Spacing.lg) }
            }
            .frame(minWidth: 640, minHeight: 420)
            .sheet(item: $selectedReprocessRecording) { reprocessSheet(for: $0) }
        }
        .sheet(isPresented: $showYouTubeSection) {
            studioSheet(title: "YouTube-video", isPresented: $showYouTubeSection) {
                youtubeInlineSection.padding(TS.Spacing.lg)
            }
            .frame(width: 520)
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

    private func studioSheet<Content: View>(title: String, isPresented: Binding<Bool>,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(TS.Font.headline)
                Spacer()
                Button("Sluiten") { isPresented.wrappedValue = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(TS.Spacing.md)
            Divider()
            content()
        }
    }

    // MARK: State helpers

    var studioIsLive: Bool { recordingVM.recordingState.isRecording }

    private var statusText: String {
        switch recordingVM.recordingState {
        case .recording: return "OPNAME ACTIEF"
        case .paused: return "OPNAME GEPAUZEERD"
        case .preparing: return "OPNAME STARTEN"
        case .stopping: return "OPNAME STOPPEN"
        default: return "KLAAR OM OP TE NEMEN"
        }
    }

    private var listenText: String {
        switch recordingVM.recordingState {
        case .recording:
            let text = recordingVM.liveTranscriptText
            return text.isEmpty ? "Ik luister..." : text
        case .paused: return "Opname is gepauzeerd"
        case .preparing, .stopping: return "Even geduld..."
        default: return "Klaar"
        }
    }

    // MARK: Workspace

    private var studioWorkspace: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let m = StudioLayout(w: w, h: h)
            // The approved NorthStar centres timer and transport 14 pt right of the workspace middle.
            let axis = w / 2 + 14
            ZStack(alignment: .topLeading) {
                studioBackground(width: w, height: h)

                WaveformView(
                    levelsProvider: { recordingVM.audioLevels },
                    isActive: recordingVM.recordingState == .recording,
                    maxFPS: 60
                )
                .frame(width: w, height: m.waveHeight)
                .position(x: w / 2, y: m.waveY)
#if DEBUG
                .overlay(alignment: .bottomLeading) {
                    Text(recordingVM.meterDebugText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(StudioColor.text3)
                        .padding(8)
                }
#endif

                statusPill
                    .padding(.leading, m.inset)
                    .padding(.top, m.pillTop)

                languagePill(iconOnly: m.tier == .narrow)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, m.trailingInset)
                    .padding(.top, m.pillTop)

                Text(formattedDuration)
                    .font(.system(size: m.timerSize, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .position(x: axis, y: m.timerY)

                listenIndicator
                    .frame(width: max(160, w - 180))
                    .position(x: axis, y: m.listenY)

                VStack(spacing: TS.Spacing.sm) {
                    offlineStatusBanner
                    audioMixFallbackBanner
                    errorBanner
                }
                .frame(width: max(0, min(600, w - 2 * m.inset)))
                .padding(.top, m.pillTop + 59)
                .frame(maxWidth: .infinity)
                .offset(x: 14)

                transport(itemWidth: m.transportItemWidth)
                    .frame(height: 130, alignment: .top)
                    .position(x: axis, y: m.transportY)

                let barWidth = max(0, w - m.inset - (m.tier == .narrow ? m.inset : 38))
                controlBar(tier: m.tier)
                    .frame(width: barWidth, height: 90)
                    .position(x: m.inset + barWidth / 2, y: h - m.barBottom - 45)
            }
        }
    }

    private func studioBackground(width w: CGFloat, height h: CGFloat) -> some View {
        // Soft light pools as in the NorthStar: violet top-centre, blue left and lower right.
        func pool(_ color: Color, x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat) -> some View {
            EllipticalGradient(colors: [color, .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.35)
                .frame(width: 2 * rx * w, height: 2 * ry * h)
                .position(x: x * w, y: y * h)
        }
        return ZStack {
            LinearGradient(colors: [StudioColor.workspaceTop, StudioColor.workspaceBottom], startPoint: .top, endPoint: .bottom)
            pool(Color(red: 0.42, green: 0.23, blue: 0.86).opacity(0.38), x: 0.55, y: 0.02, rx: 0.55, ry: 0.38)
            pool(Color(red: 0.16, green: 0.24, blue: 0.82).opacity(0.38), x: 0.06, y: 0.42, rx: 0.34, ry: 0.50)
            pool(Color(red: 0.16, green: 0.20, blue: 0.67).opacity(0.20), x: 0.95, y: 0.70, rx: 0.40, ry: 0.30)
            pool(Color(red: 0.43, green: 0.16, blue: 0.78).opacity(0.12), x: 0.50, y: 0.50, rx: 0.45, ry: 0.25)
        }
        .frame(width: w, height: h)
        .clipped()
    }

    // MARK: Header

    private var statusPill: some View {
        let state = recordingVM.recordingState
        let dot: Color = state == .recording ? StudioColor.live : (state == .paused ? Color.statusWarning : StudioColor.text3)
        return HStack(spacing: 13) {
            Circle()
                .fill(dot)
                .frame(width: 12, height: 12)
                .shadow(color: state == .recording ? StudioColor.live.opacity(0.55) : .clear, radius: 5)
            Text(statusText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(Capsule().fill(StudioColor.pill.opacity(0.72)))
        .overlay(Capsule().strokeBorder(StudioColor.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// Read-only: transcription language is fixed to Dutch (LocalTranscriber,
    /// OnDeviceTranscriber); there is no language setting to change.
    private func languagePill(iconOnly: Bool) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "ear")
                .font(.system(size: 17, weight: .regular))
                .frame(width: 46, height: 46)
            if !iconOnly {
                Rectangle().fill(StudioColor.hairline).frame(width: 1, height: 46)
                Text("Spreektaal: Nederlands")
                    .font(.system(size: 14))
                    .padding(.leading, 13)
                    .padding(.trailing, 18)
            }
        }
        .foregroundStyle(.white)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.086, green: 0.094, blue: 0.204).opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(StudioColor.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spreektaal: Nederlands")
        .help("Spreektaal: Nederlands")
    }

    // MARK: Listening indicator

    private var listenIndicator: some View {
        VStack(spacing: 9) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: recordingVM.recordingState != .recording)) { _ in
                let levels = recordingVM.recordingState == .recording ? recordingVM.audioLevels : []
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<9, id: \.self) { k in
                        let v = levels.count > k * 1 ? Double(levels[levels.count - 1 - k]) : 0
                        Capsule()
                            .fill(Color(red: 0.604, green: 0.357, blue: 0.969).opacity(1 - Double(k) * 0.07))
                            .frame(width: 3, height: 3 + 11 * v * (1 - Double(k) / 12))
                    }
                }
                .frame(height: 14)
            }
            Text(listenText)
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.682, green: 0.698, blue: 0.800))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Transport

    @ViewBuilder
    private func transport(itemWidth: CGFloat) -> some View {
        switch recordingVM.recordingState {
        case .recording:
            HStack(alignment: .top, spacing: 0) {
                roundControl(systemName: "pause.fill", label: "Pauzeer", size: 74, width: itemWidth) { recordingVM.pauseRecording() }
                stopControl(label: "Stop en verwerk", width: itemWidth) { Task { await recordingVM.stopAndUpload() } }
                roundControl(systemName: "square.and.pencil", label: "Notitie", size: 70, width: itemWidth) { showNoteField.toggle() }
                    .popover(isPresented: $showNoteField, arrowEdge: .top) {
                        noteFieldCard.frame(width: 340).padding(TS.Spacing.sm)
                    }
            }
        case .paused:
            HStack(alignment: .top, spacing: 0) {
                roundControl(systemName: "play.fill", label: "Hervat", size: 74, width: itemWidth) { recordingVM.resumeRecording() }
                stopControl(label: "Verstuur opname", width: itemWidth) { Task { await recordingVM.stopAndUpload() } }
                roundControl(systemName: "xmark", label: "Annuleer", size: 70, width: itemWidth, tint: Color.statusError) { showCancelConfirm = true }
            }
        case .preparing, .stopping:
            VStack(spacing: 11) {
                ProgressView().controlSize(.large).frame(width: 100, height: 100)
                Text("Even geduld...").font(.system(size: 15)).foregroundStyle(StudioColor.text2)
            }
        default:
            VStack(spacing: 11) {
                Button { Task { await recordingVM.startRecording() } } label: {
                    ZStack {
                        Circle().fill(RadialGradient(colors: [Color(red: 0.42, green: 0.23, blue: 0.79), Color(red: 0.31, green: 0.15, blue: 0.62)],
                                                     center: .center, startRadius: 0, endRadius: 50))
                        Circle().strokeBorder(Color(red: 0.73, green: 0.55, blue: 1), lineWidth: 2.5)
                        Circle().fill(.white).frame(width: 30, height: 30)
                    }
                    .frame(width: 100, height: 100)
                    .shadow(color: Color(red: 0.63, green: 0.35, blue: 0.98).opacity(0.6), radius: 9)
                }
                .buttonStyle(StudioPressStyle())
                .accessibilityLabel("Start opname")
                Text("Start opname").font(.system(size: 15)).foregroundStyle(.white.opacity(0.95))
            }
        }
    }

    private func roundControl(systemName: String, label: String, size: CGFloat, width: CGFloat, tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        VStack(spacing: 9) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(Circle().fill(StudioColor.control.opacity(0.85)))
                    .overlay(Circle().strokeBorder(Color(red: 0.63, green: 0.67, blue: 0.86).opacity(0.32), lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(StudioPressStyle())
            .accessibilityLabel(label)
            transportLabel(label)
        }
        .padding(.top, (100 - size) / 2)
        .frame(width: width)
    }

    private func transportLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 15)).foregroundStyle(.white.opacity(0.95))
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    private func stopControl(label: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        VStack(spacing: 11) {
            Button(action: action) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(red: 0.54, green: 0.14, blue: 0.31), Color(red: 0.42, green: 0.11, blue: 0.27)],
                                                 center: .center, startRadius: 0, endRadius: 50))
                    Circle().strokeBorder(Color(red: 1, green: 0.435, blue: 0.557), lineWidth: 2.5)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(red: 1, green: 0.635, blue: 0.714))
                        .frame(width: 29, height: 29)
                }
                .frame(width: 100, height: 100)
                .shadow(color: Color(red: 1, green: 0.24, blue: 0.43).opacity(0.65), radius: 9)
            }
            .buttonStyle(StudioPressStyle())
            .accessibilityLabel(label)
            transportLabel(label)
        }
        .frame(width: width)
    }

    // MARK: Control bar

    private func controlBar(tier: StudioLayout.Tier) -> some View {
        HStack(spacing: tier == .regular ? 24 : 12) {
            if tier == .regular {
                sourceMenu(tier: tier).frame(width: 269)
                profileMenu(tier: tier).frame(width: 249)
            } else {
                sourceMenu(tier: tier)
                profileMenu(tier: tier)
            }
            onDeviceTranscriptionControl(tier: tier)
        }
        .padding(.horizontal, tier == .regular ? 19 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.059, green: 0.082, blue: 0.165).opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(StudioColor.hairline, lineWidth: 1))
    }

    private func controlGroup(icon: String, label: String, value: String, tier: StudioLayout.Tier) -> some View {
        HStack(spacing: 0) {
            if tier != .medium {
                iconCircle(icon)
                    .padding(.leading, 1)
                    .padding(.trailing, tier == .regular ? 18 : 6)
            }
            if tier != .narrow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13)).foregroundStyle(StudioColor.text3)
                    Text(value).font(.system(size: 14.5)).foregroundStyle(.white)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.leading, tier == .medium ? 14 : 0)
            }
            Spacer(minLength: tier == .narrow ? 0 : 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.85, green: 0.855, blue: 0.918))
        }
        .padding(.trailing, tier == .narrow ? 10 : 18)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StudioColor.group.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(StudioColor.hairline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func iconCircle(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Circle().fill(StudioColor.iconCircle))
    }

    /// Existing macOS source choice: microphone only, or microphone + system audio.
    /// Fixed once a recording runs.
    private func sourceMenu(tier: StudioLayout.Tier) -> some View {
        Menu {
            Picker("Bron", selection: Bindable(recordingVM).selectedMode) {
                Text("Microfoon (fysieke meeting)").tag(RecordingMode.microphone)
                Text("Microfoon + systeemgeluid (videocall)").tag(RecordingMode.combined)
            }
            .pickerStyle(.inline)
        } label: {
            controlGroup(icon: recordingVM.selectedMode.iconName, label: "Bron", value: recordingVM.selectedMode.displayName, tier: tier)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(studioIsLive || recordingVM.recordingState == .preparing || recordingVM.recordingState == .stopping)
        .accessibilityLabel("Bron: \(recordingVM.selectedMode.displayName)")
    }

    /// Existing profiles + premium option; the profile is read when the
    /// recording is uploaded, so it stays changeable while recording.
    private func profileMenu(tier: StudioLayout.Tier) -> some View {
        Menu {
            if recordingVM.availableProfiles.isEmpty {
                if showProfileLoadError {
                    Text("Profielen konden niet geladen worden")
                    Button("Opnieuw proberen") { Task { await loadStudioProfiles() } }
                } else {
                    Text("Profielen laden...")
                }
            } else {
                if let description = recordingVM.selectedProfile?.description, !description.isEmpty {
                    Section(description) {}
                }
                ForEach(recordingVM.availableProfiles) { profile in
                    Button {
                        recordingVM.selectedProfile = profile
                    } label: {
                        if recordingVM.selectedProfile?.id == profile.id {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
                Divider()
                Toggle("Premium model: betere kwaliteit, langzamer", isOn: Bindable(recordingVM).usePremium)
            }
        } label: {
            controlGroup(icon: "waveform", label: "Opnameprofiel",
                         value: (recordingVM.selectedProfile?.name ?? "Geen profiel") + (recordingVM.usePremium ? " · Premium" : ""),
                         tier: tier)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .task {
            if recordingVM.availableProfiles.isEmpty { await loadStudioProfiles() }
        }
        .accessibilityLabel("Opnameprofiel: \(recordingVM.selectedProfile?.name ?? "Geen profiel")")
    }

    private func loadStudioProfiles() async {
        showProfileLoadError = false
        await recordingVM.reloadProfiles()
        if recordingVM.availableProfiles.isEmpty { showProfileLoadError = true }
    }

    /// The existing "Transcriptie op apparaat" setting (same key as SettingsView).
    /// It is read when a recording starts, so it is fixed while one runs.
    private func onDeviceTranscriptionControl(tier: StudioLayout.Tier) -> some View {
        HStack(spacing: 0) {
            if tier != .medium {
                iconCircle("captions.bubble")
                    .padding(.trailing, tier == .regular ? 18 : 6)
                    .help("Live transcriptie")
            }
            if tier != .narrow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live transcriptie").font(.system(size: 13)).foregroundStyle(StudioColor.text3)
                    if recordingVM.onDeviceTranscriptionAvailable {
                        Text(preferOnDeviceTranscription ? "Aan" : "Uit")
                            .font(.system(size: 14.5))
                            .foregroundStyle(preferOnDeviceTranscription ? StudioColor.liveText : StudioColor.text3)
                    } else {
                        Text("Niet beschikbaar").font(.system(size: 14.5)).foregroundStyle(StudioColor.text3)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            Spacer(minLength: tier == .narrow ? 0 : 8)
            if recordingVM.onDeviceTranscriptionAvailable {
                Toggle("Live transcriptie (transcriptie op apparaat)", isOn: $preferOnDeviceTranscription)
                    .toggleStyle(StudioSwitchStyle())
                    .labelsHidden()
                    .disabled(studioIsLive || recordingVM.recordingState == .preparing)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
