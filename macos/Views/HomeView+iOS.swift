// HomeView+iOS.swift
// ThoughtVault
//
// iOS Home, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-home-northstar.jpg): brand bar, greeting
// with the night illustration, the new-recording card, recent notulen, work in
// progress and today's agenda. Every control maps onto existing behaviour.

#if os(iOS)
import SwiftUI

extension HomeView {

    var iosBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                IOSBrandBar(initials: authVM.currentUser?.initials ?? "", onAccount: onOpenSettings)
                    .padding(.top, -10)
                iosHeader
                    .padding(.top, 12)
                iosRecordCard
                    .padding(.top, 20)
                iosRecentSection
                    .padding(.top, 22)
                iosProcessingSection
                iosAgendaSection
            }
            .padding(.horizontal, IOSMetric.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .iosScreen()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await loadRecentTranscripts() }
    }

    // MARK: Header

    private var iosHeader: some View {
        ZStack(alignment: .topTrailing) {
            IOSNightIllustration()
                .frame(width: 230, height: 118)
                .offset(x: IOSMetric.gutter, y: 4)
            VStack(alignment: .leading, spacing: 0) {
                IOSKicker(text: dateKicker)
                Group {
                    Text(greeting + (firstName.isEmpty ? "." : ","))
                        .foregroundStyle(IOSColor.text)
                    if !firstName.isEmpty {
                        Text(firstName + ".")
                            .foregroundStyle(IOSColor.nameGradient)
                    }
                }
                .font(.system(size: 28, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, firstName.isEmpty ? 8 : 4)
                Text("\u{201C}Goede idee\u{00EB}n beginnen\nvaak met een gesprek.\u{201D}")
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundStyle(IOSColor.text2)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Record card

    private var iosRecordCard: some View {
        Button { onStartRecording?(.microphone) } label: {
            HStack(spacing: 14) {
                IOSMicOrb(size: 108)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Begin een nieuwe opname")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(IOSColor.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Spreek je gedachten, vergaderingen of idee\u{00EB}n. ThoughtVault maakt er automatisch notities van.")
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .foregroundStyle(IOSColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IOSColor.text)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(IOSColor.control))
                    .overlay(Circle().strokeBorder(IOSColor.border, lineWidth: 1))
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .iosCard(raised: true)
            .contentShape(RoundedRectangle(cornerRadius: IOSMetric.radius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Begin een nieuwe opname")
    }

    // MARK: Recent

    private var iosRecentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IOSSectionHeader(title: "Recente notities") {
                if !recentTranscripts.isEmpty {
                    IOSLink(title: "Alles bekijken") { onNavigateToTranscripts?() }
                }
            }
            if let error = loadError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IOSColor.danger)
                    Text(error).font(.system(size: 13)).foregroundStyle(IOSColor.text2).lineLimit(2)
                    Spacer()
                    Button("Opnieuw") { Task { await loadRecentTranscripts() } }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IOSColor.link)
                }
                .padding(16)
                .iosCard()
            } else if isLoadingRecent && recentTranscripts.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(24).iosCard()
            } else if recentTranscripts.isEmpty {
                iosEmptyVault
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentTranscripts.prefix(3).enumerated()), id: \.element.id) { index, transcript in
                        if index > 0 { IOSDivider(inset: 12).padding(.trailing, 12) }
                        iosRecentRow(transcript)
                    }
                }
                .iosCard()
            }
        }
    }

    private var iosEmptyVault: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Je vault is nog leeg")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IOSColor.text)
            Text("Alles wat je inspreekt verschijnt hier als notitie of notule, met samenvatting, besluiten en actiepunten.")
                .font(.system(size: 13))
                .foregroundStyle(IOSColor.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .iosCard()
    }

    private func iosRecentRow(_ transcript: Transcript) -> some View {
        let isNotule = transcript.notuleHtml != nil
        return Button { onOpenTranscript?(transcript) } label: {
            HStack(spacing: 16) {
                IOSIconTile(systemName: isNotule ? "doc.text" : "doc.text.fill", tint: isNotule ? .violet : .blue, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(transcript.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(IOSColor.text)
                        .lineLimit(1)
                    Text(IOSFormat.meta(transcript.date, duration: transcript.duration))
                        .font(.system(size: 12.5))
                        .foregroundStyle(IOSColor.text2)
                    let preview = HomeView.preview(transcript)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 12))
                            .foregroundStyle(IOSColor.text3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                IOSChevron()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Processing

    @ViewBuilder
    private var iosProcessingSection: some View {
        let tasks = recordingVM.activeTasks.filter { $0.status.isActive }
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                IOSSectionHeader(title: "Wordt verwerkt") {
                    Text("\(tasks.count) actief")
                        .font(.system(size: 14))
                        .foregroundStyle(IOSColor.text2)
                }
                ForEach(tasks) { task in
                    NavigationLink {
                        IOSProcessingView(taskID: task.taskId)
                    } label: {
                        IOSProcessingCard(task: task)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 26)
        }
    }

    // MARK: Agenda

    @ViewBuilder
    private var iosAgendaSection: some View {
        let calendar = CalendarService.shared
        let meetings = Array(calendar.upcomingMeetings.filter { Calendar.current.isDateInToday($0.date) && $0.endDate > Date() }.prefix(3))
        if !meetings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                IOSSectionHeader("Vandaag")
                VStack(spacing: 0) {
                    ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                        if index > 0 { IOSDivider(inset: 12).padding(.trailing, 12) }
                        iosMeetingRow(meeting)
                    }
                }
                .iosCard()
            }
            .padding(.top, 26)
        }
    }

    private func iosMeetingRow(_ meeting: CalendarEvent) -> some View {
        HStack(spacing: 14) {
            IOSIconTile(systemName: "calendar", size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IOSColor.text)
                    .lineLimit(1)
                Text("\(IOSFormat.time(meeting.date)) \u{2013} \(IOSFormat.time(meeting.endDate))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(IOSColor.text2)
                if meeting.platform != .other {
                    Text(meeting.platform.rawValue)
                        .font(.system(size: 12.5))
                        .foregroundStyle(IOSColor.text3)
                }
            }
            Spacer(minLength: 6)
            Button { onStartMeeting?(meeting) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "mic").font(.system(size: 13, weight: .medium)).foregroundStyle(IOSColor.iconViolet)
                    Text("Start opname").font(.system(size: 13, weight: .medium)).foregroundStyle(IOSColor.text)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(IOSColor.tile))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(IOSColor.borderViolet, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(recordingVM.recordingState != .idle)
        }
        .padding(12)
    }
}

// MARK: - Shared iOS pieces

/// Glowing violet microphone orb with concentric rings.
struct IOSMicOrb: View {
    var size: CGFloat = 108
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.30, green: 0.18, blue: 0.62).opacity(0.55), .clear],
                                     center: .center, startRadius: size * 0.3, endRadius: size * 0.5))
            Circle().strokeBorder(Color(red: 0.36, green: 0.26, blue: 0.72).opacity(0.45), lineWidth: 1)
                .padding(size * 0.03)
            Circle().strokeBorder(Color(red: 0.50, green: 0.34, blue: 0.95).opacity(0.55), lineWidth: 1)
                .padding(size * 0.1)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.80, green: 0.50, blue: 1.0), Color(red: 0.48, green: 0.26, blue: 0.93)],
                                     center: UnitPoint(x: 0.38, y: 0.3), startRadius: 2, endRadius: size * 0.42))
                .padding(size * 0.16)
                .shadow(color: Color(red: 0.60, green: 0.32, blue: 1.0).opacity(0.6), radius: 12)
            Image(systemName: "mic")
                .font(.system(size: size * 0.24, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "Wordt verwerkt" card: ring, name, meta and current step.
struct IOSProcessingCard: View {
    let task: TranscriptTask
    var body: some View {
        HStack(spacing: 18) {
            IOSProgressRing(progress: task.displayProgress, size: 54, lineWidth: 5)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.filename)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IOSColor.text)
                    .lineLimit(1)
                if let created = task.createdAt {
                    Text(IOSFormat.day(created))
                        .font(.system(size: 12.5))
                        .foregroundStyle(IOSColor.text2)
                }
                Text(task.status.displayName + "\u{2026}")
                    .font(.system(size: 12.5))
                    .foregroundStyle(IOSColor.text2)
            }
            Spacer(minLength: 4)
            IOSChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RadialGradient(colors: [Color(red: 0.32, green: 0.18, blue: 0.70).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.7, y: 0), startRadius: 0, endRadius: 220)
                .clipShape(RoundedRectangle(cornerRadius: IOSMetric.radius, style: .continuous))
        )
        .iosCard(raised: true)
        .contentShape(Rectangle())
    }
}
#endif
