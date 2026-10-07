// HomeView+Panels.swift
// ThoughtVault
//
// Lists of the macOS Home NorthStar: recent notulen with the
// Alle / Opnames / Notulen filter and work in progress.

import SwiftUI

/// Filter of the recent list: "Opnames" are transcripts without a notule yet.
enum HomeRecentFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
    case recordings = "Opnames"
    case notulen = "Notulen"
    var id: String { rawValue }

    func matches(_ transcript: Transcript) -> Bool {
        switch self {
        case .all: return true
        case .recordings: return transcript.notuleHtml == nil
        case .notulen: return transcript.notuleHtml != nil
        }
    }
}

extension HomeView {
    /// First words of the notule (or transcript) as plain text.
    static func preview(_ transcript: Transcript) -> String {
        let source = transcript.notuleHtml ?? transcript.rawTranscription ?? ""
        let text = source
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<h[1-6][^>]*>[\\s\\S]*?</h[1-6]>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return String(text.prefix(160))
    }
}

#if os(macOS)
extension HomeView {

    // MARK: Recent notulen

    var homeRecentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                Text("Recente notities")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.leading, 3)
                    .padding(.bottom, 13)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 16)
                HStack(spacing: 0) {
                    ForEach(HomeRecentFilter.allCases) { filter in
                        filterTab(filter)
                    }
                }
                .padding(.trailing, 7)
            }
            recentList
        }
    }

    private func filterTab(_ filter: HomeRecentFilter) -> some View {
        let selected = recentFilter == filter
        return Button { recentFilter = filter } label: {
            Text(filter.rawValue)
                .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color(red: 0.80, green: 0.62, blue: 1.0) : HomeColor.text2)
                .padding(.horizontal, 13)
                .frame(height: 36)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? Color(red: 0.72, green: 0.48, blue: 1.0) : .clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var recentList: some View {
        let items = Array(recentTranscripts.filter(recentFilter.matches).prefix(10))
        VStack(spacing: 0) {
            if let error = loadError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.statusError)
                    Text(error).font(.system(size: 13)).foregroundStyle(HomeColor.text2).lineLimit(1)
                    Spacer()
                    Button("Opnieuw") { Task { await loadRecentTranscripts() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HomeColor.lavender)
                }
                .padding(20)
            } else if isLoadingRecent && recentTranscripts.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(28)
            } else if recentTranscripts.isEmpty {
                emptyVault
            } else if items.isEmpty {
                Text(recentFilter == .recordings ? "Alle opnames hebben al een notule." : "Nog geen notulen.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(HomeColor.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, transcript in
                    if index > 0 {
                        Rectangle().fill(HomeColor.divider).frame(height: 1).padding(.leading, 80)
                    }
                    recentRow(transcript)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HomeColor.list))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HomeColor.listBorder, lineWidth: 1))
    }

    private var emptyVault: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Je vault is nog leeg")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.white)
            Text("Alles wat je inspreekt verschijnt hier als notitie of notule, met samenvatting, besluiten en actiepunten.")
                .font(.system(size: 13))
                .foregroundStyle(HomeColor.text2)
                .fixedSize(horizontal: false, vertical: true)
            Button { onStartRecording?(.microphone) } label: {
                Label("Maak je eerste opname", systemImage: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeColor.lavender)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
    }

    private func recentRow(_ transcript: Transcript) -> some View {
        let isNotule = transcript.notuleHtml != nil
        return Button { onOpenTranscript?(transcript) } label: {
            HStack(spacing: 0) {
                Image(systemName: isNotule ? "doc.text" : "doc.text.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(isNotule ? Color(red: 0.66, green: 0.47, blue: 0.96) : Color(red: 0.40, green: 0.60, blue: 0.97))
                    .frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isNotule ? Color(red: 0.145, green: 0.114, blue: 0.267) : Color(red: 0.102, green: 0.153, blue: 0.247)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
                    .padding(.leading, 9)
                VStack(alignment: .leading, spacing: 9) {
                    Text(transcript.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(HomeColor.text)
                        .lineLimit(1)
                    HStack(spacing: 30) {
                        Text(Self.recentMeta(transcript))
                            .font(.system(size: 12.5))
                            .foregroundStyle(HomeColor.text2)
                            .fixedSize()
                        Text(Self.preview(transcript))
                            .font(.system(size: 12.5))
                            .foregroundStyle(HomeColor.text3)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 21)
                Spacer(minLength: 16)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HomeColor.text2)
                    .padding(.trailing, 26)
            }
            .frame(height: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(transcript.title), \(Self.recentMeta(transcript))")
    }

    /// "18 sep 2026 · 11:43 · 42 min"
    static func recentMeta(_ transcript: Transcript) -> String {
        let nl = Locale(identifier: "nl_NL")
        let day = transcript.date.formatted(.dateTime.day().month(.abbreviated).year().locale(nl)).replacingOccurrences(of: ".", with: "")
        let time = transcript.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(nl))
        var parts = [day, time]
        if let seconds = transcript.duration, seconds > 0 {
            parts.append("\(max(1, Int((seconds / 60).rounded()))) min")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: In progress

    @ViewBuilder
    var homeActiveProcessing: some View {
        let tasks = recordingVM.activeTasks.filter { $0.status.isActive }
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bezig met verwerken")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeColor.text2)
                    .padding(.leading, 3)
                    .padding(.bottom, 10)
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().stroke(HomeColor.listBorder, lineWidth: 2)
                                Circle()
                                    .trim(from: 0, to: task.status.progress)
                                    .stroke(HomeColor.lavender, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(TS.Animation.smooth, value: task.status.progress)
                            }
                            .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.filename).font(.system(size: 13.5, weight: .medium)).foregroundStyle(HomeColor.text).lineLimit(1)
                                Text(task.status.displayName).font(.system(size: 12)).foregroundStyle(HomeColor.lavender)
                            }
                            Spacer()
                            Text("\(Int(task.status.progress * 100))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(HomeColor.text2)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HomeColor.list))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HomeColor.listBorder, lineWidth: 1))
            }
            .padding(.top, 24)
        }
    }
}
#endif
