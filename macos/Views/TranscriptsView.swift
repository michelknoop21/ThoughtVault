// TranscriptsView.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Full transcript library with search, filters, bulk-delete, tag management,
// and a complete detail view with inline editing, regeneration, retranscription,
// and export capabilities.

import SwiftUI
import WebKit
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "TranscriptsView")

/// Locally processed records carry a deterministic "local-<uuid>" task id (minted in
/// RecordingViewModel.processLocally) and live in SwiftData, not on the server.
/// Server ids never use this prefix, so the check is unambiguous.
func isLocalTranscript(_ taskId: String) -> Bool { taskId.hasPrefix("local-") }


// MARK: - TranscriptsView

struct TranscriptsView: View {

    // MARK: Dependencies

    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Navigation path — controlled by ContentView to dismiss on tab change.
    @Binding var transcriptsNavPath: NavigationPath

    /// Called when the empty-library CTA is tapped. Parent navigates to the recording screen.
    var onStartRecording: (() -> Void)?

    // MARK: State — list

    @State private var transcripts: [Transcript] = []
    @State private var isLoading = false
    @State private var loadErrorMessage: String? = nil
    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var sortNewest = true
    @State private var selectedDateFilter: DateFilter = .all
    @State private var selectedTags: Set<String> = []

    // MARK: State — selection / bulk

    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var showBulkDeleteConfirm = false
    @State private var transcriptToDelete: Transcript? = nil
    @State private var showSingleDeleteConfirm = false

    // MARK: State — auto-refresh debounce

    @State private var lastRefreshDate: Date = .distantPast

    // MARK: Enums

    enum DateFilter: String, CaseIterable, Identifiable {
        case all    = "Alles"
        case today  = "Vandaag"
        case week   = "Deze week"
        case month  = "Deze maand"
        var id: String { rawValue }
    }

    // MARK: Computed

    private var availableTags: [String] {
        Array(Set(transcripts.flatMap { $0.tags })).sorted()
    }

    private var filteredTranscripts: [Transcript] {
        var result = transcripts

        // Search
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                ($0.rawTranscription?.lowercased().contains(q) ?? false)
            }
        }

        // Date filter
        let calendar = Calendar.current
        let now = Date()
        switch selectedDateFilter {
        case .today:
            result = result.filter { calendar.isDateInToday($0.date) }
        case .week:
            guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { break }
            result = result.filter { $0.date >= weekAgo }
        case .month:
            guard let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) else { break }
            result = result.filter { $0.date >= monthAgo }
        case .all:
            break
        }

        // Tag filter
        if !selectedTags.isEmpty {
            result = result.filter { !Set($0.tags).intersection(selectedTags).isEmpty }
        }

        // Sort
        result.sort { sortNewest ? $0.date > $1.date : $0.date < $1.date }

        return result
    }

    private var pendingOfflineCount: Int {
        recordingVM.offlineQueue.count
    }

    private var activeTasks: [TranscriptTask] {
        recordingVM.activeTasks.filter { $0.status.isActive }
    }

    private var errorTasks: [TranscriptTask] {
        recordingVM.activeTasks.filter { $0.status == .error }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filtersRow
            tagFilterRow
            mainContent
        }
        .navigationTitle("Notulen")
        .toolbar { toolbarContent }
        .navigationDestination(for: Transcript.self) { transcript in
            TranscriptDetailView(transcript: transcript)
        }
        .confirmationDialog(
            "Geselecteerde transcripties verwijderen?",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Verwijder \(selectedIds.count)", role: .destructive) {
                Task { await bulkDelete() }
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Dit kan niet ongedaan worden gemaakt.")
        }
        .confirmationDialog(
            "Transcriptie verwijderen?",
            isPresented: $showSingleDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Verwijderen", role: .destructive) {
                if let transcript = transcriptToDelete {
                    Task { await deleteTranscript(transcript) }
                }
                transcriptToDelete = nil
            }
            Button("Annuleren", role: .cancel) {
                transcriptToDelete = nil
            }
        } message: {
            Text("Deze transcriptie wordt permanent verwijderd.")
        }
        .task { await loadTranscripts() }
#if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard Date().timeIntervalSince(lastRefreshDate) >= 10 else { return }
            Task { await loadTranscripts() }
        }
#endif
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.labelTertiary)
                .font(.system(size: 15))

            TextField("Zoeken...", text: $searchText)
                .font(TS.Font.body)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, _ in
                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        // Filtered transcripts are computed, no async search needed
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoekveld wissen")
            }
        }
        .padding(.horizontal, TS.Spacing.md)
        .padding(.vertical, TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(Color.surfaceSecondary)
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                }
        }
        .padding(.horizontal, TS.Spacing.md)
        .padding(.top, TS.Spacing.sm)
        .padding(.bottom, TS.Spacing.xs)
    }

    // MARK: - Filters row

    private var filtersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TS.Spacing.xs) {
                // Sort menu
                Menu {
                    Button {
                        sortNewest = true
                    } label: {
                        Label("Nieuwste eerst", systemImage: sortNewest ? "checkmark" : "")
                    }
                    Button {
                        sortNewest = false
                    } label: {
                        Label("Oudste eerst", systemImage: sortNewest ? "" : "checkmark")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text(sortNewest ? "Nieuwste" : "Oudste")
                            .font(TS.Font.captionSemibold)
                    }
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs + 2)
                    .background {
                        Capsule()
                            .fill(Color.surfaceSecondary)
                            .overlay { Capsule().stroke(Color.borderPrimary, lineWidth: 1) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Date filter chips
                ForEach(DateFilter.allCases) { filter in
                    dateFilterChip(filter)
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.xs)
        }
    }

    private func dateFilterChip(_ filter: DateFilter) -> some View {
        let isSelected = selectedDateFilter == filter
        return Button {
            withAnimation(TS.Animation.smooth) {
                selectedDateFilter = filter
            }
        } label: {
            Text(filter.rawValue)
                .font(TS.Font.captionSemibold)
                .foregroundStyle(isSelected ? .white : Color.labelSecondary)
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, TS.Spacing.xs + 2)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.brandSecondary : Color.surfaceSecondary)
                        .overlay {
                            if !isSelected {
                                Capsule().stroke(Color.borderPrimary, lineWidth: 1)
                            }
                        }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tag filter row

    @ViewBuilder
    private var tagFilterRow: some View {
        if !availableTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TS.Spacing.xs) {
                    ForEach(availableTags, id: \.self) { tag in
                        tagFilterChip(tag)
                    }
                }
                .padding(.horizontal, TS.Spacing.md)
                .padding(.bottom, TS.Spacing.xs)
            }
        }
    }

    private func tagFilterChip(_ tag: String) -> some View {
        let isSelected = selectedTags.contains(tag)
        return Button {
            withAnimation(TS.Animation.smooth) {
                if isSelected {
                    selectedTags.remove(tag)
                } else {
                    selectedTags.insert(tag)
                }
            }
        } label: {
            HStack(spacing: 3) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(tag)
                    .font(TS.Font.microMedium)
            }
            .foregroundStyle(isSelected ? Color.brandSecondary : Color.labelSecondary)
            .padding(.horizontal, TS.Spacing.xs + 2)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(isSelected ? Color.accentBgSecondary : Color.surfaceTertiary)
                    .overlay {
                        Capsule().stroke(
                            isSelected ? Color.brandSecondary.opacity(0.35) : Color.borderSecondary,
                            lineWidth: 1
                        )
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main content

    private var mainContent: some View {
        List {
            Section {
                offlineQueueBanner
                errorBanner
                activeProcessingSection
                errorTasksSection
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: TS.Spacing.md, bottom: 0, trailing: TS.Spacing.md))
            .listRowBackground(Color.clear)

            if isLoading && transcripts.isEmpty {
                ProgressView("Laden...")
                    .padding(TS.Spacing.xl)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if filteredTranscripts.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredTranscripts) { transcript in
                    transcriptCardRow(transcript)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: TS.Spacing.sm / 2, leading: TS.Spacing.md, bottom: TS.Spacing.sm / 2, trailing: TS.Spacing.md))
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: Offline queue banner

    @ViewBuilder
    private var offlineQueueBanner: some View {
        if pendingOfflineCount > 0 {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(Color.brandOrange)
                Text("\(pendingOfflineCount) opname(s) wachten op upload")
                    .font(TS.Font.footnoteMedium)
                    .foregroundStyle(Color.brandOrange)
                Spacer()
                Button("Upload nu") {
                    Task { await recordingVM.processQueueOnStartupIfNeeded() }
                }
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(.white)
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, TS.Spacing.xs)
                .background {
                    Capsule().fill(Color.brandOrange)
                }
                .buttonStyle(.plain)
            }
            .padding(TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.accentBgOrange)
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(Color.brandOrange.opacity(0.25), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = loadErrorMessage {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.statusError)
                Text(error)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.statusError)
                Spacer()
                Button("Opnieuw") {
                    Task { await loadTranscripts() }
                }
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.brandPrimary)
                Button {
                    loadErrorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foutmelding sluiten")
            }
            .padding(TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.statusError.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(Color.statusError.opacity(0.25), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: Active processing section

    @ViewBuilder
    private var activeProcessingSection: some View {
        if !activeTasks.isEmpty {
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                Label("Bezig met verwerken", systemImage: "gearshape.2")
                    .font(TS.Font.captionSemibold)
                    .foregroundStyle(Color.labelSecondary)

                ForEach(activeTasks) { task in
                    HStack(spacing: TS.Spacing.sm) {
                        ProgressView(value: task.status.progress)
                            .tint(Color.brandPrimary)
                            .frame(width: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.filename)
                                .font(TS.Font.captionMedium)
                                .foregroundStyle(Color.labelPrimary)
                                .lineLimit(1)
                            Text(task.status.displayName)
                                .font(TS.Font.micro)
                                .foregroundStyle(Color.brandPrimary)
                        }
                        Spacer()
                        Text("\(Int(task.status.progress * 100))%")
                            .font(TS.Font.captionMonospaced)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .padding(TS.Spacing.xs)
                }
            }
            .padding(TS.Spacing.sm)
            .modernCard()
        }
    }

    // MARK: Error tasks section

    @ViewBuilder
    private var errorTasksSection: some View {
        if !errorTasks.isEmpty {
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                ForEach(errorTasks) { task in
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.statusError)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.filename)
                                .font(TS.Font.captionMedium)
                                .foregroundStyle(Color.labelPrimary)
                                .lineLimit(1)
                            Text(task.errorMessage ?? "Onbekende fout")
                                .font(TS.Font.micro)
                                .foregroundStyle(Color.statusError)
                        }
                        Spacer()
                    }
                    .padding(TS.Spacing.xs)
                }
            }
            .padding(TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.statusError.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(Color.statusError.opacity(0.2), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: TS.Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(searchText.isEmpty ? Color.brandPrimary : Color.labelTertiary)
            if searchText.isEmpty {
                Text("Nog geen transcripties")
                    .font(TS.Font.calloutSemibold)
                    .foregroundStyle(Color.labelPrimary)
                Text("Zodra je een opname maakt, verschijnt hier de volledige transcriptie. Je kunt die later teruglezen, doorzoeken en gebruiken om je notule te controleren.")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)

                Button {
                    onStartRecording?()
                } label: {
                    HStack(spacing: TS.Spacing.xs) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Start opname")
                            .font(TS.Font.footnoteSemibold)
                    }
                    .foregroundStyle(Color.brandPrimary)
                    .padding(.horizontal, TS.Spacing.md)
                    .padding(.vertical, TS.Spacing.sm)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.brandPrimary.opacity(0.10))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.brandPrimary.opacity(0.28), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, TS.Spacing.xs)
            } else {
                Text("Geen resultaten")
                    .font(TS.Font.calloutSemibold)
                    .foregroundStyle(Color.labelSecondary)
                Text("Probeer een andere zoekterm")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(TS.Spacing.xxl)
    }

    // MARK: - Card row

    private func transcriptCardRow(_ transcript: Transcript) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                transcriptsNavPath.append(transcript)
            } label: {
                TranscriptListCard(transcript: transcript)
                    .contentShape(RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            // Selection overlay
            if isSelecting {
                selectionOverlay(for: transcript)
            } else {
                TranscriptCardMenu(
                    transcript: transcript,
                    onDelete: {
                        transcriptToDelete = transcript
                        showSingleDeleteConfirm = true
                    }
                )
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                transcriptToDelete = transcript
                showSingleDeleteConfirm = true
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                transcriptsNavPath.append(transcript)
            } label: {
                Label("Openen", systemImage: "arrow.up.right.square")
            }
            Divider()
            Button(role: .destructive) {
                transcriptToDelete = transcript
                showSingleDeleteConfirm = true
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        }
    }

    private func selectionOverlay(for transcript: Transcript) -> some View {
        let isSelected = selectedIds.contains(transcript.id)
        return Button {
            if isSelected {
                selectedIds.remove(transcript.id)
            } else {
                selectedIds.insert(transcript.id)
            }
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.brandSecondary : Color.labelTertiary)
                .background(
                    Circle()
                        .fill(Color.surfacePrimary)
                        .frame(width: 26, height: 26)
                )
        }
        .buttonStyle(.plain)
        .offset(x: -14)
        .padding(.top, TS.Spacing.sm)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if isSelecting {
                HStack(spacing: TS.Spacing.sm) {
                    if !selectedIds.isEmpty {
                        Button {
                            showBulkDeleteConfirm = true
                        } label: {
                            Label("Verwijder \(selectedIds.count)", systemImage: "trash")
                                .foregroundStyle(Color.statusError)
                        }
                    }
                    Button("Klaar") {
                        withAnimation(TS.Animation.smooth) {
                            isSelecting = false
                            selectedIds.removeAll()
                        }
                    }
                }
            } else {
                HStack(spacing: TS.Spacing.sm) {
                    Button {
                        Task { await loadTranscripts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isLoading && !reduceMotion ? 360 : 0))
                            .animation(
                                (isLoading && !reduceMotion) ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                value: isLoading
                            )
                    }
                    .accessibilityLabel("Vernieuwen")
                    .disabled(isLoading)

                    Button {
                        withAnimation(TS.Animation.smooth) {
                            isSelecting = true
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel("Selectiemodus")
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadTranscripts() async {
        isLoading = true
        loadErrorMessage = nil

        // Local records first — always available without the server.
        let local = LocalTranscriptStore.shared.allTranscripts()

        var server: [Transcript] = []
        if !ProcessingMode.isLocalMode {
            do {
                server = try await APIService.shared.getTranscripts().items
            } catch {
                // Server unavailable is fine; only surface if no local records.
                if local.isEmpty { loadErrorMessage = error.localizedDescription }
            }
        }

        let localIds = Set(local.map(\.taskId))
        transcripts = (local + server.filter { !localIds.contains($0.taskId) })
            .sorted { $0.date > $1.date }
        lastRefreshDate = Date()
        isLoading = false
    }

    private func deleteTranscript(_ transcript: Transcript) async {
        if isLocalTranscript(transcript.taskId) {
            LocalTranscriptStore.shared.delete(taskId: transcript.taskId)
            withAnimation(TS.Animation.smooth) {
                transcripts.removeAll { $0.id == transcript.id }
            }
            return
        }
        do {
            try await APIService.shared.deleteTranscript(taskId: transcript.taskId)
            withAnimation(TS.Animation.smooth) {
                transcripts.removeAll { $0.id == transcript.id }
            }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func bulkDelete() async {
        let idsToDelete = selectedIds
        var deletedIds: Set<String> = []
        var failCount = 0

        for id in idsToDelete {
            guard let transcript = transcripts.first(where: { $0.id == id }) else {
                failCount += 1
                continue
            }
            if isLocalTranscript(transcript.taskId) {
                LocalTranscriptStore.shared.delete(taskId: transcript.taskId)
                deletedIds.insert(id)
                continue
            }
            do {
                try await APIService.shared.deleteTranscript(taskId: transcript.taskId)
                deletedIds.insert(id)
            } catch {
                failCount += 1
            }
        }

        withAnimation(TS.Animation.smooth) {
            transcripts.removeAll { deletedIds.contains($0.id) }
            selectedIds.subtract(deletedIds)
            if selectedIds.isEmpty { isSelecting = false }
        }

        if failCount > 0 {
            loadErrorMessage = "\(failCount) van \(idsToDelete.count) item(s) konden niet worden verwijderd."
        }
    }
}

// MARK: - TranscriptListCard

struct TranscriptListCard: View {

    let transcript: Transcript
    @State private var isHovered = false

    var hasNotule: Bool {
        !(transcript.notuleHtml ?? "").isEmpty
    }

    var body: some View {
        // Mockup row: icon tile · title/meta/preview · status chip.
        HStack(alignment: .top, spacing: TS.Spacing.sm + 2) {
            VaultIconTile(systemName: hasNotule ? "doc.text" : "waveform", size: 38)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(transcript.title)
                    .font(TS.Font.subheadlineSemibold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(2)

                Text(relativeDate)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelTertiary)

                if let preview = previewText, !preview.isEmpty {
                    Text(preview)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                if !transcript.tags.isEmpty {
                    HStack(spacing: TS.Spacing.xs) {
                        ForEach(transcript.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(TS.Font.micro)
                                .foregroundStyle(Color.brandLink)
                                .padding(.horizontal, TS.Spacing.xs + 2)
                                .padding(.vertical, 3)
                                .background {
                                    Capsule().fill(Color.brandSecondary.opacity(0.14))
                                }
                        }
                        if transcript.tags.count > 3 {
                            Text("+\(transcript.tags.count - 3)")
                                .font(TS.Font.micro)
                                .foregroundStyle(Color.labelTertiary)
                        }
                    }
                    .padding(.top, 3)
                }
            }

            Spacer(minLength: TS.Spacing.sm)

            VaultChip(text: hasNotule ? "Afgerond" : "Transcript",
                      tone: hasNotule ? .ok : .neutral)
                .padding(.top, 2)
        }
        .padding(TS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovered = $0 }
        .modernCard(isHovered: isHovered)
    }

    private var relativeDate: String {
        let interval = Date().timeIntervalSince(transcript.date)
        if interval < 3600 {
            let minutes = max(Int(interval / 60), 1)
            return "\(minutes) \(minutes == 1 ? "minuut" : "minuten") geleden"
        } else if interval < 86400 {
            let hr = Int(interval / 3600)
            return "\(hr) uur geleden"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "nl_NL")
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: transcript.date)
        }
    }

    private var previewText: String? {
        if let notule = transcript.notuleHtml, !notule.isEmpty {
            return notule
                // Strip <style>/<script> blocks incl. content — their text isn't between
                // angle brackets, so plain tag-stripping would leak CSS/JS into the preview.
                .replacingOccurrences(of: "<(style|script)[^>]*>[\\s\\S]*?</\\1>", with: " ",
                                      options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return transcript.rawTranscription
    }
}

// MARK: - TranscriptCardMenu

struct TranscriptCardMenu: View {

    let transcript: Transcript
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        Menu {
            Button {
                // NavigationLink handles open — this is a contextual shortcut
            } label: {
                Label("Openen", systemImage: "arrow.up.right.square")
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(TS.Spacing.xs)
        .accessibilityLabel("Meer acties")
        .accessibilityLabel("Meer opties")
        .confirmationDialog(
            "Transcriptie verwijderen?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Verwijderen", role: .destructive) { onDelete() }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Deze transcriptie wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.")
        }
    }
}

// MARK: - TranscriptDetailView

struct TranscriptDetailView: View {

    // MARK: Input

    let transcript: Transcript

    // MARK: Dependencies

    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: State — document

    @State private var fullTranscript: Transcript
    @State private var selectedTab: DetailTab = .notule

    enum DetailTab { case notule, raw }

    // MARK: State — title editing

    @State private var showTitleEditAlert = false
    @State private var isEditingTitle = false
    @State private var pendingTitle = ""

    // MARK: State — tags

    @State private var showAddTagField = false
    @State private var newTagText = ""

    // MARK: State — regeneration

    @State private var isRegenerating = false
    @State private var regeneratingMessage = ""
    @State private var showProfileSheet = false
    @State private var profileSheetMode: ProfileSheetMode = .regenerate

    enum ProfileSheetMode { case regenerate, retranscribe }

    // MARK: State — retranscription

    @State private var isRetranscribing = false
    @State private var retranscribeMessage = ""

    // MARK: State — editing notulen

    @State private var isEditingNotule = false
    @State private var editedHTML = ""

    // MARK: State — errors

    @State private var errorMessage: String? = nil
    #if os(macOS)
    @State private var printWebView: WKWebView?
    #endif

    // MARK: Init

    init(transcript: Transcript) {
        self.transcript = transcript
        self._fullTranscript = State(initialValue: transcript)
    }

    // MARK: State — loading

    @State private var isLoadingDetail = true

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Progress / error banners
            progressBanners
                .padding(.horizontal, TS.Spacing.md)
                .padding(.top, TS.Spacing.sm)

            // Compact toolbar: tabs left, actions right
            headerBar
                .padding(.top, TS.Spacing.sm)
                .background(Color.surfacePrimary)
                .overlay(alignment: .bottom) { Divider() }

            // Content fills remaining space
            if isLoadingDetail {
                VStack(spacing: TS.Spacing.sm) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Laden...")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    documentHeader
                    Divider()
                    contentArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Notulen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { detailToolbar }
        .alert("Titel bewerken", isPresented: $showTitleEditAlert) {
            TextField("Titel", text: $pendingTitle)
            Button("Opslaan") {
                Task { await saveTitle() }
            }
            Button("Annuleren", role: .cancel) {}
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSelectionSheet(mode: profileSheetMode) { profile, usePremium in
                showProfileSheet = false
                if profileSheetMode == .regenerate {
                    Task { await startRegenerate(profileId: profile.id, usePremium: usePremium) }
                } else {
                    Task { await startRetranscribe(profileId: profile.id) }
                }
            }
            .environment(recordingVM)
        }
        .task {
            // Local records already carry full content (raw + notule) — no server fetch.
            if isLocalTranscript(transcript.taskId) {
                fullTranscript = transcript
                let hasNotule = !(transcript.notuleHtml ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasRaw = !(transcript.rawTranscription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !hasNotule && hasRaw { selectedTab = .raw }
                isLoadingDetail = false
                return
            }
            isLoadingDetail = true
            do {
                fullTranscript = try await APIService.shared.getTranscript(taskId: transcript.taskId)
                logger.info("Detail fetch success for \(transcript.taskId): notuleHtml=\(fullTranscript.notuleHtml != nil), rawTranscription=\(fullTranscript.rawTranscription != nil)")

                // If notule_html is empty, try fetching linked notes separately
                let hasNotule = !(fullTranscript.notuleHtml ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !hasNotule {
                    if let html = try? await APIService.shared.getTranscriptNotes(taskId: transcript.taskId),
                       !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        fullTranscript.notuleHtml = html
                        logger.info("Loaded notule from /notes endpoint for \(transcript.taskId)")
                    }
                }

                // Auto-select appropriate tab
                let finalHasNotule = !(fullTranscript.notuleHtml ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let finalHasRaw = !(fullTranscript.rawTranscription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !finalHasNotule && finalHasRaw {
                    selectedTab = .raw
                }
            } catch {
                logger.error("Detail fetch failed for \(transcript.taskId): \(error)")
                errorMessage = error.localizedDescription
            }
            isLoadingDetail = false
        }
    }

    // MARK: - Header bar (tabs left, actions right — compact toolbar like Windows)

    private var headerBar: some View {
        HStack(alignment: .center, spacing: TS.Spacing.sm) {
            // Tab toggle (left side)
            compactTabToggle

            Spacer(minLength: TS.Spacing.sm)

            // Action buttons on the right
            actionButtons
        }
        .padding(.horizontal, TS.Spacing.md)
        .padding(.bottom, TS.Spacing.xs)
    }

    @ViewBuilder
    private var compactTabToggle: some View {
        let hasNotule = !(fullTranscript.notuleHtml ?? "").isEmpty
        let hasRaw = !(fullTranscript.rawTranscription ?? "").isEmpty

        if hasNotule && hasRaw {
            HStack(spacing: 0) {
                compactTabButton(.notule, label: "Notule")
                compactTabButton(.raw, label: "Transcriptie")
            }
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: TS.Radius.xs))
            .overlay {
                RoundedRectangle(cornerRadius: TS.Radius.xs)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            }
        }
    }

    private func compactTabButton(_ tab: DetailTab, label: String) -> some View {
        let isActive = selectedTab == tab
        return Button {
            withAnimation(TS.Animation.quick) { selectedTab = tab }
        } label: {
            Text(label)
                .font(TS.Font.captionSemibold)
                .foregroundStyle(isActive ? .white : Color.labelSecondary)
                .padding(.horizontal, TS.Spacing.md)
                .padding(.vertical, TS.Spacing.xs + 2)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: TS.Radius.xs - 1)
                            .fill(Color.brandSecondary)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress banners

    @ViewBuilder
    private var progressBanners: some View {
        if isRegenerating {
            progressBanner(
                message: regeneratingMessage.isEmpty
                    ? "Notule wordt geregenereerd..."
                    : regeneratingMessage,
                color: Color.brandPrimary
            )
        }
        if isRetranscribing {
            progressBanner(
                message: retranscribeMessage.isEmpty
                    ? "Opnieuw transcriberen..."
                    : retranscribeMessage,
                color: Color.brandSecondary
            )
        }
        if let err = errorMessage {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.statusError)
                Text(err)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.statusError)
                Spacer()
                Button {
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foutmelding sluiten")
            }
            .padding(TS.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                    .fill(Color.statusError.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                            .stroke(Color.statusError.opacity(0.25), lineWidth: 1)
                    }
            }
        }
    }

    private func progressBanner(message: String, color: Color) -> some View {
        return HStack(spacing: TS.Spacing.sm) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(color)
            Text(message)
                .font(TS.Font.footnoteMedium)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .stroke(color.opacity(0.20), lineWidth: 1)
                }
        }
    }

    // MARK: - Tags section

    private var tagsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TS.Spacing.xs) {
                ForEach(fullTranscript.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(TS.Font.captionMedium)
                            .foregroundStyle(Color.brandSecondary)
                        Button {
                            Task { await removeTag(tag) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.brandSecondary.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color.accentBgSecondary)
                            .overlay { Capsule().stroke(Color.brandSecondary.opacity(0.20), lineWidth: 1) }
                    }
                }

                if showAddTagField {
                    HStack(spacing: 4) {
                        TextField("Tag...", text: $newTagText)
                            .font(TS.Font.captionMedium)
                            .textFieldStyle(.plain)
                            .frame(width: 80)
                            .onSubmit { Task { await confirmAddTag() } }

                        Button {
                            Task { await confirmAddTag() }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.brandAccent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tag toevoegen")

                        Button {
                            newTagText = ""
                            showAddTagField = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.labelTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Annuleren")
                    }
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color.surfaceSecondary)
                            .overlay { Capsule().stroke(Color.brandPrimary.opacity(0.3), lineWidth: 1) }
                    }
                } else {
                    Button {
                        withAnimation(TS.Animation.smooth) {
                            showAddTagField = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                            .frame(width: 24, height: 24)
                            .background {
                                Circle().fill(Color.surfaceTertiary)
                                    .overlay { Circle().stroke(Color.borderPrimary, lineWidth: 1) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tag toevoegen")
                }
            }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: TS.Spacing.xs) {
            // Regenerate (AI action — prominent)
            if isRegenerating {
                HStack(spacing: TS.Spacing.xs) {
                    ProgressView().scaleEffect(0.65).tint(Color.brandPrimary)
                    Text("Genereren...")
                        .font(TS.Font.captionSemibold)
                        .foregroundStyle(Color.brandPrimary)
                }
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, TS.Spacing.xs + 2)
                .background { Capsule().fill(Color.accentBgPrimary) }
            } else if !isEditingNotule {
                Button {
                    profileSheetMode = .regenerate
                    showProfileSheet = true
                } label: {
                    HStack(spacing: TS.Spacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Regenereer")
                            .font(TS.Font.captionSemibold)
                    }
                    .foregroundStyle(Color.brandPrimary)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs + 2)
                    .background {
                        Capsule().fill(Color.accentBgPrimary)
                            .overlay { Capsule().stroke(Color.brandPrimary.opacity(0.20), lineWidth: 1) }
                    }
                }
                .buttonStyle(.plain)
            }

            // Edit notule
            if !isEditingNotule, let html = fullTranscript.notuleHtml, !html.isEmpty {
                detailIconButton(icon: "pencil", label: "Bewerken") {
                    editedHTML = html
                    withAnimation(TS.Animation.smooth) {
                        isEditingNotule = true
                        selectedTab = .notule
                    }
                }
            }

            // Generate title from notule content
            detailIconButton(icon: "sparkles", label: "Titel") {
                Task { await generateTitle() }
            }
            .disabled((fullTranscript.notuleHtml ?? "").isEmpty)

            // Export menu
            Menu {
                Button { shareContent() } label: {
                    Label("Delen...", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button { exportAsPDF() } label: {
                    Label("PDF", systemImage: "doc.richtext")
                }
                Button { exportAsMarkdown() } label: {
                    Label("Markdown", systemImage: "doc.plaintext")
                }
                Button { exportToObsidian() } label: {
                    Label("Exporteer naar Obsidian", systemImage: "tray.and.arrow.down")
                }
                Button { exportAsTXT() } label: {
                    Label("Platte tekst", systemImage: "doc.text")
                }
                Divider()
                Button { copyContent() } label: {
                    Label("Kopieer tekst", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 30, height: 30)
                    .background {
                        Circle().fill(Color.surfaceSecondary)
                            .overlay { Circle().stroke(Color.borderPrimary, lineWidth: 1) }
                    }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func detailIconButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(Color.surfaceSecondary)
                        .overlay { Circle().stroke(Color.borderPrimary, lineWidth: 1) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Content area

    // MARK: - Document Header

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            // Accent line
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.4)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
                .padding(.bottom, TS.Spacing.xs)

            // Inline editable title
            if isEditingTitle {
                HStack(spacing: TS.Spacing.sm) {
                    TextField("Titel", text: $pendingTitle, axis: .vertical)
                        .font(TS.Font.title3Bold)
                        .foregroundStyle(Color.labelPrimary)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .onSubmit {
                            Task { await saveTitle() }
                            isEditingTitle = false
                        }

                    Button {
                        Task { await saveTitle() }
                        isEditingTitle = false
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.statusSuccess)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Titel opslaan")

                    Button {
                        isEditingTitle = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bewerken annuleren")
                }
                .padding(.vertical, 4)
                .padding(.horizontal, TS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: TS.Radius.xs)
                        .stroke(Color.brandPrimary, lineWidth: 2)
                )
            } else {
                HStack(alignment: .top, spacing: TS.Spacing.xs) {
                    Text(fullTranscript.title.isEmpty ? "Naamloze opname" : fullTranscript.title)
                        .font(TS.Font.title3Bold)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(3)

                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.labelTertiary)
                        .padding(.top, 5)
                }
                .onTapGesture {
                    pendingTitle = fullTranscript.title
                    isEditingTitle = true
                }
                #if os(macOS)
                .onHover { hovering in
                    if hovering {
                        NSCursor.iBeam.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                #endif
            }

            // Metadata row
            HStack(spacing: TS.Spacing.xs) {
                Text(fullTranscript.date, style: .date)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelTertiary)

                if let duration = fullTranscript.duration, duration > 0 {
                    Text("·")
                        .foregroundStyle(Color.labelTertiary)
                    Text(formatDuration(duration))
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                }

                if let profileName = fullTranscript.profileName, !profileName.isEmpty {
                    Text("·")
                        .foregroundStyle(Color.labelTertiary)
                    Text(profileName)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            // Tags
            if !fullTranscript.tags.isEmpty {
                HStack(spacing: TS.Spacing.xs) {
                    ForEach(fullTranscript.tags, id: \.self) { tag in
                        Text(tag)
                            .font(TS.Font.micro)
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentBgPrimary)
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, TS.Spacing.lg)
        .padding(.vertical, TS.Spacing.md)
        .background(Color.surfacePrimary)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins) min \(secs) sec"
        }
        return "\(secs) sec"
    }

    @ViewBuilder
    private var contentArea: some View {
        let hasNotule = !(fullTranscript.notuleHtml ?? "").isEmpty
        let hasRaw = !(fullTranscript.rawTranscription ?? "").isEmpty

        if !hasNotule && !hasRaw {
            VStack(spacing: TS.Spacing.md) {
                Spacer()
                if let error = errorMessage {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.statusWarning)
                    Text("Laden mislukt")
                        .font(TS.Font.callout)
                        .foregroundStyle(Color.labelSecondary)
                    Text(error)
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.labelTertiary)
                    Text("Geen notulen beschikbaar")
                        .font(TS.Font.callout)
                        .foregroundStyle(Color.labelSecondary)
                    Button {
                        profileSheetMode = .regenerate
                        showProfileSheet = true
                    } label: {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "sparkles")
                            Text("Notulen genereren")
                        }
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TS.Spacing.lg)
                        .padding(.vertical, TS.Spacing.sm)
                        .background(Color.brandPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedTab == .notule, let html = fullTranscript.notuleHtml, !html.isEmpty {
            htmlContentView(html)
        } else if selectedTab == .raw || fullTranscript.notuleHtml == nil || fullTranscript.notuleHtml!.isEmpty {
            rawTranscriptView
        }
    }

    private func htmlContentView(_ html: String) -> some View {
        VStack(spacing: 0) {
            if isEditingNotule {
                FormattingToolbar(webView: editableWebViewRef)
                    .padding(.horizontal, TS.Spacing.md)
                    .padding(.vertical, TS.Spacing.xs)
            }

            EditableHTMLWebView(
                htmlContent: html,
                editedHTML: $editedHTML,
                isEditing: isEditingNotule,
                isDarkMode: colorScheme == .dark,
                onWebViewReady: { ref in
                    Task { @MainActor in editableWebViewRef = ref }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isEditingNotule {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color.brandPrimary.opacity(0.3), lineWidth: 2)
                }
            }

            if isEditingNotule {
                editingActionBar
                    .padding(.horizontal, TS.Spacing.md)
                    .padding(.vertical, TS.Spacing.sm)
                    .background(Color.surfacePrimary)
                    .overlay(alignment: .top) { Divider() }
            }
        }
    }

    private var editingActionBar: some View {
        HStack(spacing: TS.Spacing.sm) {
            Button {
                withAnimation(TS.Animation.smooth) {
                    isEditingNotule = false
                    editedHTML = ""
                }
            } label: {
                Text("Annuleren")
                    .font(TS.Font.footnoteSemibold)
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            Button {
                Task { await saveNotuleEdits() }
            } label: {
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Opslaan")
                        .font(TS.Font.footnoteSemibold)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(editedHTML.isEmpty)
        }
        .padding(.top, TS.Spacing.sm)
    }

    @State private var editableWebViewRef: WKWebView? = nil

    @ViewBuilder
    private var rawTranscriptView: some View {
        if let raw = fullTranscript.rawTranscription, !raw.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: TS.Spacing.md) {
                    HStack(alignment: .center) {
                        Label("Ruwe transcriptie", systemImage: "waveform")
                            .font(TS.Font.captionSemibold)
                            .foregroundStyle(Color.labelTertiary)
                        Spacer()
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(raw, forType: .string)
                            #else
                            UIPasteboard.general.string = raw
                            #endif
                        } label: {
                            HStack(spacing: TS.Spacing.xs) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Kopieer")
                                    .font(TS.Font.captionSemibold)
                            }
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.horizontal, TS.Spacing.sm)
                            .padding(.vertical, TS.Spacing.xs)
                            .background {
                                Capsule().fill(Color.accentBgPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Text(raw)
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(Color.labelPrimary)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, TS.Spacing.lg)
                .padding(.vertical, TS.Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: TS.Spacing.sm) {
                Spacer()
                Image(systemName: "waveform.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.labelTertiary)
                Text("Geen ruwe transcriptie beschikbaar")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        // Intentionally empty — all actions are in the header bar.
        // NavigationStack provides the back button automatically.
        ToolbarItem(placement: .primaryAction) {
            EmptyView()
        }
    }

    // MARK: - Actions

    private func saveTitle() async {
        let newTitle = pendingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != fullTranscript.title else { return }
        let original = fullTranscript.title
        fullTranscript.title = newTitle
        if isLocalTranscript(fullTranscript.taskId) {
            LocalTranscriptStore.shared.updateTitle(taskId: fullTranscript.taskId, title: newTitle)
            return
        }
        do {
            try await APIService.shared.updateTranscriptTitle(taskId: fullTranscript.taskId, title: newTitle)
        } catch {
            fullTranscript.title = original
            errorMessage = error.localizedDescription
        }
    }

    private static let sectionWords: Set<String> = [
        "besluiten", "kernargumenten", "notulen", "samenvatting",
        "actiepunten", "agendapunten", "conclusie", "inleiding",
        "toelichting", "bijlagen", "vervolgstappen"
    ]

    private func generateTitle() async {
        guard let html = fullTranscript.notuleHtml, !html.isEmpty else { return }

        // Extract text from HTML tags using regex
        func extractTexts(tag: String) -> [String] {
            let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
            let range = NSRange(html.startIndex..., in: html)
            return regex.matches(in: html, range: range).compactMap { match in
                guard let textRange = Range(match.range(at: 1), in: html) else { return nil }
                // Strip nested tags
                let raw = String(html[textRange])
                let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return stripped.isEmpty ? nil : stripped
            }
        }

        var candidates: [String] = []

        // 1. h4 subtitles (handleiding-profiel puts real title here)
        candidates.append(contentsOf: extractTexts(tag: "h4").filter { $0.count > 5 && $0.count < 120 })

        // 2. h1 headings (skip h2/h3 — those are section headings)
        candidates.append(contentsOf: extractTexts(tag: "h1").filter { $0.count > 3 && $0.count < 120 })

        // 3. First bold/strong text
        candidates.append(contentsOf: extractTexts(tag: "strong").filter { $0.count > 5 && $0.count < 120 })
        candidates.append(contentsOf: extractTexts(tag: "b").filter { $0.count > 5 && $0.count < 120 })

        // 4. First non-trivial paragraph
        for text in extractTexts(tag: "p") where text.count > 10 && text.count < 120 {
            candidates.append(text.count > 80 ? String(text.prefix(77)) + "..." : text)
        }

        // Filter section words and find first candidate different from current title
        let currentLower = fullTranscript.title.lowercased()
        let newTitle = candidates.first { candidate in
            let lower = candidate.lowercased()
            return lower != currentLower && !Self.sectionWords.contains(lower)
        }

        if let newTitle {
            let original = fullTranscript.title
            fullTranscript.title = newTitle
            if isLocalTranscript(fullTranscript.taskId) {
                LocalTranscriptStore.shared.updateTitle(taskId: fullTranscript.taskId, title: newTitle)
                return
            }
            do {
                try await APIService.shared.updateTranscriptTitle(taskId: fullTranscript.taskId, title: newTitle)
            } catch {
                fullTranscript.title = original
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeTag(_ tag: String) async {
        let original = fullTranscript.tags
        fullTranscript.tags.removeAll { $0 == tag }
        if isLocalTranscript(fullTranscript.taskId) {
            LocalTranscriptStore.shared.updateTags(taskId: fullTranscript.taskId, tags: fullTranscript.tags)
            return
        }
        do {
            try await APIService.shared.updateTranscriptTags(taskId: fullTranscript.taskId, tags: fullTranscript.tags)
        } catch {
            fullTranscript.tags = original
            errorMessage = error.localizedDescription
        }
    }

    private func confirmAddTag() async {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !fullTranscript.tags.contains(tag) else {
            newTagText = ""
            showAddTagField = false
            return
        }
        let original = fullTranscript.tags
        fullTranscript.tags.append(tag)
        newTagText = ""
        showAddTagField = false
        if isLocalTranscript(fullTranscript.taskId) {
            LocalTranscriptStore.shared.updateTags(taskId: fullTranscript.taskId, tags: fullTranscript.tags)
            return
        }
        do {
            try await APIService.shared.updateTranscriptTags(taskId: fullTranscript.taskId, tags: fullTranscript.tags)
        } catch {
            fullTranscript.tags = original
            errorMessage = error.localizedDescription
        }
    }

    private func saveNotuleEdits() async {
        let html = editedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !html.isEmpty else { return }
        let original = fullTranscript.notuleHtml
        fullTranscript.notuleHtml = html
        withAnimation(TS.Animation.smooth) {
            isEditingNotule = false
        }
        if isLocalTranscript(fullTranscript.taskId) {
            LocalTranscriptStore.shared.updateNotule(taskId: fullTranscript.taskId, html: html)
            editedHTML = ""
            return
        }
        do {
            try await APIService.shared.updateNotuleHTML(taskId: fullTranscript.taskId, html: html)
            logger.info("Notule saved for \(fullTranscript.taskId)")
        } catch {
            fullTranscript.notuleHtml = original
            errorMessage = "Opslaan mislukt: \(error.localizedDescription)"
            logger.error("Save notule failed: \(error)")
        }
        editedHTML = ""
    }

    private func startRegenerate(profileId: String, usePremium: Bool = false) async {
        isRegenerating = true
        regeneratingMessage = "Notule wordt lokaal geregenereerd..."

        // Local records regenerate entirely on-device from the stored transcription.
        if isLocalTranscript(fullTranscript.taskId) {
            defer { isRegenerating = false; regeneratingMessage = "" }
            do {
                let result = try await recordingVM.regenerateNotuleLocally(
                    taskId: fullTranscript.taskId, profileId: profileId
                )
                fullTranscript.notuleHtml = result.html
                fullTranscript.title = result.title
                selectedTab = .notule
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        regeneratingMessage = usePremium
            ? "Notule wordt geregenereerd met premium model..."
            : "Notule wordt geregenereerd..."
        do {
            let task = try await APIService.shared.regenerateNotule(
                taskId: fullTranscript.taskId,
                profileId: profileId,
                usePremium: usePremium
            )
            // Poll every 4 seconds, max 60 iterations (4 minutes)
            for iteration in 0..<60 {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                let updated = try await APIService.shared.getTaskStatus(taskId: task.taskId)
                let progress = Int((updated.status.progress) * 100)
                regeneratingMessage = "\(updated.status.displayName)... \(progress)%"

                if updated.status == .completed {
                    if let html = updated.notuleHtml {
                        fullTranscript.notuleHtml = html
                        selectedTab = .notule
                    }
                    break
                } else if updated.status == .error {
                    errorMessage = updated.errorMessage ?? "Generatie mislukt"
                    break
                }
                _ = iteration // suppress warning
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isRegenerating = false
        regeneratingMessage = ""
    }

    private func startRetranscribe(profileId: String) async {
        isRetranscribing = true
        retranscribeMessage = "Controleren op lokale audio..."

        let hasLocal = recordingVM.hasLocalAudio(for: fullTranscript.id)
        guard hasLocal else {
            retranscribeMessage = ""
            isRetranscribing = false
            errorMessage = "Geen lokale audio gevonden voor hertranscriptie"
            return
        }

        // Retranscription requires RecordingViewModel.retranscribe() — planned for v1.1
        retranscribeMessage = ""
        errorMessage = "Hertranscriptie is nog niet beschikbaar"

        isRetranscribing = false
        retranscribeMessage = ""
    }

    private func copyContent() {
        let content: String
        if selectedTab == .notule, let html = fullTranscript.notuleHtml {
            content = html
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            content = fullTranscript.rawTranscription ?? ""
        }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #else
        UIPasteboard.general.string = content
        #endif
    }

    private func exportAsPDF() {
        guard let html = fullTranscript.notuleHtml ?? fullTranscript.rawTranscription else { return }

        let styledHTML = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
        body { font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif; font-size: 11.5pt; line-height: 1.65; color: #2c2c30; margin: 0; padding: 28pt 36pt; }
        h1 { font-size: 18pt; font-weight: 700; color: #7830D8; margin-bottom: 14pt; padding-bottom: 8pt; border-bottom: 1.5pt solid rgba(120,48,216,0.15); }
        h2 { font-size: 14pt; font-weight: 650; margin-top: 20pt; margin-bottom: 8pt; }
        h3 { font-size: 12pt; font-weight: 600; color: #555; margin-top: 16pt; margin-bottom: 6pt; }
        p { margin: 7pt 0; }
        ul, ol { margin: 7pt 0; padding-left: 22pt; }
        li { margin: 4pt 0; }
        strong { font-weight: 600; }
        table { border-collapse: collapse; width: 100%; margin: 14pt 0; }
        th, td { border: 1px solid #e0e0e0; padding: 7pt 10pt; text-align: left; font-size: 10.5pt; }
        th { background: #f8f8fa; font-weight: 600; font-size: 9.5pt; text-transform: uppercase; letter-spacing: 0.4pt; color: #666; }
        blockquote { border-left: 2.5pt solid #7830D8; margin: 12pt 0; padding: 8pt 16pt; background: #f8f5fe; }
        </style>
        </head><body>\(html)</body></html>
        """

        #if os(macOS)
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 595, height: 842)
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        printWebView = webView
        webView.loadHTMLString(styledHTML, baseURL: nil)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            let op = webView.printOperation(with: printInfo)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.run()
            printWebView = nil
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fullTranscript.title).html")
        do {
            try styledHTML.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Exporteren mislukt: \(error.localizedDescription)"
            return
        }
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
    }

    private func exportAsTXT() {
        let html = fullTranscript.notuleHtml ?? fullTranscript.rawTranscription ?? ""
        let stripped = html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(fullTranscript.title).txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try stripped.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Exporteren mislukt: \(error.localizedDescription)"
            }
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fullTranscript.title).txt")
        do {
            try stripped.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Exporteren mislukt: \(error.localizedDescription)"
            return
        }
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
    }

    private func exportAsMarkdown() {
        let html = fullTranscript.notuleHtml ?? fullTranscript.rawTranscription ?? ""
        let md = htmlToMarkdown(html)

        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(fullTranscript.title).md"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try md.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Exporteren mislukt: \(error.localizedDescription)"
            }
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fullTranscript.title).md")
        do {
            try md.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Exporteren mislukt: \(error.localizedDescription)"
            return
        }
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
    }

    private func exportToObsidian() {
        Task { @MainActor in
            do {
                if let record = LocalTranscriptStore.shared.record(forTaskId: fullTranscript.taskId) {
                    try await ObsidianService().export(record)
                } else {
                    let html = fullTranscript.notuleHtml ?? ""
                    guard !html.isEmpty else {
                        errorMessage = "Geen notule om te exporteren."
                        return
                    }
                    try await ObsidianService().export(
                        title: fullTranscript.title, html: html, date: fullTranscript.date,
                        participants: [], profileName: fullTranscript.profileName, tags: fullTranscript.tags
                    )
                }
                errorMessage = nil
            } catch {
                errorMessage = "Obsidian-export mislukt: \(error.localizedDescription)"
            }
        }
    }

    private func shareContent() {
        let text = fullTranscript.rawTranscription
            ?? (fullTranscript.notuleHtml ?? "")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        #if os(macOS)
        let picker = NSSharingServicePicker(items: [text])
        picker.show(relativeTo: .zero, of: NSApp.keyWindow?.contentView ?? NSView(), preferredEdge: .minY)
        #else
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
    }
}

// MARK: - ProfileSelectionSheet

private struct ProfileSelectionSheet: View {

    @Environment(RecordingViewModel.self) var recordingVM
    @Environment(\.dismiss) private var dismiss

    let mode: TranscriptDetailView.ProfileSheetMode
    let onSelect: (Profile, Bool) -> Void

    @State private var usePremium = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(recordingVM.availableProfiles) { profile in
                        Button {
                            onSelect(profile, usePremium)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name)
                                    .font(TS.Font.bodyMedium)
                                    .foregroundStyle(Color.labelPrimary)
                                if let prompt = profile.description ?? profile.notulePrompt, !prompt.isEmpty {
                                    Text(prompt)
                                        .font(TS.Font.caption)
                                        .foregroundStyle(Color.labelSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Kies een profiel")
                }

                Section {
                    Toggle(isOn: $usePremium) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Premium model")
                                .font(TS.Font.bodyMedium)
                                .foregroundStyle(Color.labelPrimary)
                            Text("Claude — betere kwaliteit, langzamer")
                                .font(TS.Font.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                    .tint(Color.brandPrimary)
                }
            }
            .navigationTitle(
                mode == .regenerate
                ? "Notule regenereren"
                : "Hertranscriberen"
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
            }
            .task {
                if recordingVM.availableProfiles.isEmpty {
                    await recordingVM.reloadProfiles()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TranscriptsView(transcriptsNavPath: .constant(NavigationPath()))
        .environment(RecordingViewModel())
}
