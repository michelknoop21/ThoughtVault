// HomeView+Side.swift
// ThoughtVault
//
// Right column of the macOS Home NorthStar: today's meetings from the existing
// calendar integration (status only), quick capture (starts a recording with
// an existing mode or the Notitie profile) and the brand note.

#if os(macOS)
import SwiftUI

extension HomeView {

    // MARK: Right column

    var homeSideColumn: some View {
        VStack(spacing: 19) {
            agendaCard(minHeight: 400)
            quickCaptureCard
            brandNoteCard
        }
    }

    /// Below the NorthStar width: agenda and quick capture side by side (or
    /// stacked when narrow); the decorative brand note is dropped.
    func compactSideCards(_ layout: HomeLayout) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                agendaCard().frame(minWidth: 300)
                quickCaptureCard.frame(minWidth: 300)
            }
            VStack(spacing: 18) {
                agendaCard()
                quickCaptureCard
            }
        }
    }

    private func sideCard<Content: View>(minHeight: CGFloat = 0, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.leading, 23)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HomeColor.side))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HomeColor.sideBorder, lineWidth: 1))
    }

    private func sideTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 24)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Agenda

    private func agendaCard(minHeight: CGFloat = 0) -> some View {
        let calendar = CalendarService.shared
        let meetings = Array(calendar.upcomingMeetings.filter { Calendar.current.isDateInToday($0.date) }.prefix(4))
        let connected = calendar.hasCalendarAccess || calendar.isMicrosoftConnected
        return sideCard(minHeight: minHeight) {
            VStack(alignment: .leading, spacing: 0) {
                sideTitle("Vandaag")
                    .padding(.top, 25)
                if !connected {
                    Text("Koppel je agenda om je meetings van vandaag hier te zien.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(HomeColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                    Button {
                        if calendar.activeProvider == .apple {
                            Task { await calendar.requestAccess() }
                        } else {
                            onOpenSettings?()
                        }
                    } label: {
                        Text("Agenda koppelen")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(HomeColor.text)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(HomeColor.control))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HomeColor.controlBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                } else if meetings.isEmpty {
                    Text("Geen meetings meer vandaag.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(HomeColor.text3)
                        .padding(.top, 16)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                            if index > 0 {
                                Rectangle().fill(HomeColor.divider).frame(height: 1).padding(.leading, 40)
                            }
                            meetingRow(meeting)
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .padding(.bottom, 20)
        }
        .task {
            if calendar.hasCalendarAccess || calendar.isMicrosoftConnected {
                await calendar.fetchUpcomingMeetings()
            }
        }
    }

    /// Status only: a meeting that has ended gets a check; nothing is toggled.
    private func meetingRow(_ meeting: CalendarEvent) -> some View {
        let ended = meeting.endDate < Date()
        let time = meeting.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return HStack(alignment: .top, spacing: 18) {
            ZStack {
                if ended {
                    Circle().fill(Color(red: 0.48, green: 0.29, blue: 0.99))
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(Color(red: 0.72, green: 0.74, blue: 0.84), lineWidth: 1.5)
                }
            }
            .frame(width: 22, height: 22)
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 7) {
                Text(meeting.title)
                    .font(.system(size: 14.5))
                    .foregroundStyle(HomeColor.text)
                    .lineLimit(2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Vandaag, \(time)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(HomeColor.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityValue(ended ? "Afgelopen" : "")
    }

    // MARK: Quick capture

    private var notitieProfile: Profile? {
        recordingVM.availableProfiles.first { $0.id == "notitie" }
    }

    private var quickCaptureCard: some View {
        sideCard {
            VStack(alignment: .leading, spacing: 12) {
                sideTitle("Snel vastleggen")
                    .padding(.top, 22)
                    .padding(.bottom, 9)
                quickButton("mic", "Alleen audio opnemen") { onStartRecording?(.microphone) }
                if let profile = notitieProfile {
                    quickButton("doc.text", "Spraak naar notitie") {
                        recordingVM.selectedProfile = profile
                        onStartRecording?(.microphone)
                    }
                }
                quickButton("bubble.left.and.text.bubble.right", "Gesprek opnemen") { onStartRecording?(.combined) }
            }
            .padding(.bottom, 20)
        }
    }

    private func quickButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.67, green: 0.52, blue: 1.0))
                    .frame(width: 26)
                    .padding(.leading, 16)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(HomeColor.text)
                    .padding(.leading, 20)
                Spacer(minLength: 0)
            }
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 0.086, green: 0.110, blue: 0.172)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HomeColor.controlBorder.opacity(0.8), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(StudioPressStyle())
    }

    // MARK: Brand note

    private var brandNoteCard: some View {
        sideCard {
            HStack(alignment: .top, spacing: 19) {
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.78, green: 0.49, blue: 1), Color(red: 0.48, green: 0.25, blue: 0.95)],
                                                    startPoint: .top, endPoint: .bottom))
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Laat gedachten groeien tot kennis.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.72, green: 0.55, blue: 1.0))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 150, alignment: .leading)
                    Text("E\u{00E9}n gesprek kan meerdere inzichten, taken en plannen opleveren.")
                        .font(.system(size: 14))
                        .lineSpacing(6)
                        .foregroundStyle(HomeColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 4)
            .padding(.top, 30)
            .padding(.bottom, 30)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
