// RecordingView+Inspector.swift
// ThoughtVault
//
// Right-hand inspector of the macOS Opnemen screen (approved NorthStar). Shows
// only information and actions that already exist: participants, the live
// duration/level, source and profile, the quick note, import, YouTube and the
// saved-recordings list. Tags and the notule are filled in after processing.

#if os(macOS)
import SwiftUI

extension RecordingView {

    var studioInspector: some View {
        // Scrolls only when the window is lower than the NorthStar composition.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                inspectorTitle("Huidige opname")
                    .padding(.top, 44)
                identityCard
                    .padding(.top, 13)
                VStack(spacing: 0) {
                    metaRow(icon: "tag", text: "Tags na verwerking")
                    metaRow(icon: "person.2", text: participantsText) {
                        showParticipantPicker = true
                    }
                    metaRow(icon: "doc.text", text: "Wordt na verwerking aangevuld")
                }
                .padding(.top, 18)
                livePanel
                    .padding(.top, 33)
                inspectorTitle("Snelle acties")
                    .padding(.top, 31)
                VStack(spacing: 11) {
                    ForEach(quickActions) { action in
                        quickActionRow(action)
                    }
                }
                .padding(.top, 13)
            }
            .padding(.leading, 23)
            .padding(.trailing, 26)
            .padding(.bottom, TS.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(StudioColor.inspector)
    }

    private func inspectorTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 26)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Identity

    private var identityCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "person")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 57, height: 57)
                .overlay(Circle().strokeBorder(Color(red: 0.78, green: 0.8, blue: 0.92).opacity(0.5), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                // A calendar meeting started from the call alert already has a
                // title; otherwise the title is extracted after processing.
                Text(recordingVM.activeMeeting?.title ?? "Nieuwe opname")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Titel na verwerking")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.682, green: 0.698, blue: 0.8))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 87)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StudioColor.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(StudioColor.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var participantsText: String {
        switch recordingVM.selectedParticipantIDs.count {
        case 0: return "Geen personen"
        case 1: return "1 persoon"
        case let n: return "\(n) personen"
        }
    }

    private func metaRow(icon: String, text: String, add: (() -> Void)? = nil) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.85, green: 0.855, blue: 0.918))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(StudioColor.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 0)
            if let add {
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(red: 0.102, green: 0.125, blue: 0.212)))
                        .overlay(Circle().strokeBorder(Color(red: 0.86, green: 0.88, blue: 0.96).opacity(0.55), lineWidth: 1.5))
                }
                .buttonStyle(StudioPressStyle())
                .accessibilityLabel("Deelnemers kiezen")
            }
        }
        .padding(.leading, 7)
        .frame(height: 43)
    }

    // MARK: Live panel

    private var livePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.system(size: 16))
                Text("Live opname").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(height: 51)
            liveRow("Duur") { Text(formattedDuration).monospacedDigit() }
            liveRow("Geluidsniveau") { levelMeter }
            liveRow("Bron") { Text(recordingVM.selectedMode.displayName) }
            liveRow("Profiel") { Text(recordingVM.selectedProfile?.name ?? "Geen profiel").lineLimit(1) }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 208, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StudioColor.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(StudioColor.border, lineWidth: 1))
    }

    private func liveRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 16) {
            Circle().fill(StudioColor.violet).frame(width: 10, height: 10)
            Text(label).foregroundStyle(StudioColor.text2).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 8)
            value().foregroundStyle(Color(red: 0.91, green: 0.914, blue: 0.957))
        }
        .font(.system(size: 14))
        .frame(height: 36)
        .accessibilityElement(children: .combine)
    }

    private var levelMeter: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: recordingVM.recordingState != .recording)) { _ in
            let level = recordingVM.recordingState == .recording ? Double(recordingVM.audioLevels.last ?? 0) : 0
            let lit = Int((level * 9 * 1.3).rounded())
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<9, id: \.self) { k in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(k < lit ? StudioColor.levelOn : StudioColor.levelOff)
                        .frame(width: 4, height: 6 + CGFloat(k) * 1.2)
                }
            }
            .frame(height: 16, alignment: .bottom)
        }
        .accessibilityLabel("Geluidsniveau")
    }

    // MARK: Quick actions

    struct StudioAction: Identifiable {
        let id: String
        let icon: String
        let title: String
        var badge: String? = nil
        let perform: () -> Void
    }

    private var quickActions: [StudioAction] {
        if studioIsLive {
            return [
                StudioAction(id: "note", icon: "square.and.pencil", title: "Notitie maken") { showNoteField = true },
                StudioAction(id: "people", icon: "person.2", title: "Deelnemers kiezen") { showParticipantPicker = true },
            ]
        }
        var actions = [StudioAction(id: "import", icon: "square.and.arrow.down", title: "Audiobestand importeren") { showImporter = true }]
        if recordingVM.isYouTubeEnabled {
            actions.append(StudioAction(id: "youtube", icon: "play.rectangle", title: "YouTube-video") { showYouTubeSection = true })
        }
        let pending = recordingVM.savedRecordings.count + recordingVM.activeTasks.count
        actions.append(StudioAction(id: "saved", icon: "tray.full", title: "Opgeslagen opnames",
                                    badge: pending > 0 ? "\(pending)" : nil) { showSavedRecordings = true })
        return actions
    }

    private func quickActionRow(_ action: StudioAction) -> some View {
        Button(action: action.perform) {
            HStack(spacing: 0) {
                Image(systemName: action.icon)
                    .font(.system(size: 18))
                    .frame(width: 22)
                Text(action.title).font(.system(size: 15)).lineLimit(1)
                    .padding(.leading, 16)
                Spacer(minLength: 8)
                if let badge = action.badge {
                    Text(badge)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(StudioColor.text2)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.141, green: 0.157, blue: 0.275)))
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StudioColor.row))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(StudioColor.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(StudioPressStyle())
    }
}
#endif
