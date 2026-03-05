// TranscriptsView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Full transcript library with search, filters, bulk-delete, tag management,
// and a complete detail view with inline editing, regeneration, retranscription,
// and export capabilities.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - TranscriptsView

struct TranscriptsView: View {

    // MARK: Dependencies

    @Environment(RecordingViewModel.self) var recordingVM

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

    // MARK: State — navigation

    @State private var selectedTranscript: Transcript? = nil

    // MARK: Enums

    enum DateFilter: String, CaseIterable, Identifiable {
        case all    = "Alles"
        case today  = "Vandaag"
        case week   = "Week"
        case month  = "Maand"
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
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            result = result.filter { $0.date >= weekAgo }
        case .month:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
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
        NavigationStack {
            ZStack {
                backgroundBlobs
                VStack(spacing: 0) {
                    searchBar
                    filtersRow
                    tagFilterRow
                    mainContent
                }
            }
            .navigationTitle("Transcripties")
            .toolbar { toolbarContent }
            .navigationDestination(item: $selectedTranscript) { transcript in
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
        }
        .task { await loadTranscripts() }
    }

    // MARK: - Background blobs

    private var backgroundBlobs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.brandSecondary.opacity(0.08), Color.clear],
                        center: .center, startRadius: 0, endRadius: 220
                    ))
                    .frame(width: 440, height: 440)
                    .offset(x: geo.size.width * 0.6, y: 60)
                    .blur(radius: 55)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
                        .fill(isSelected ? Color.brandPrimary : Color.surfaceSecondary)
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
        ScrollView {
            LazyVStack(spacing: TS.Spacing.sm) {
                offlineQueueBanner
                errorBanner
                activeProcessingSection
                errorTasksSection

                if isLoading && transcripts.isEmpty {
                    ProgressView("Laden...")
                        .padding(TS.Spacing.xl)
                } else if filteredTranscripts.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredTranscripts) { transcript in
                        transcriptCardRow(transcript)
                    }
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
        }
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
                .foregroundStyle(Color.labelTertiary)
            Text(searchText.isEmpty ? "Geen transcripties" : "Geen resultaten")
                .font(TS.Font.calloutSemibold)
                .foregroundStyle(Color.labelSecondary)
            if !searchText.isEmpty {
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
            NavigationLink(value: transcript) {
                TranscriptListCard(transcript: transcript)
                    .contentShape(RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    Task { await deleteTranscript(transcript) }
                } label: {
                    Label("Verwijderen", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    selectedTranscript = transcript
                } label: {
                    Label("Openen", systemImage: "arrow.up.right.square")
                }
                Divider()
                Button(role: .destructive) {
                    Task { await deleteTranscript(transcript) }
                } label: {
                    Label("Verwijderen", systemImage: "trash")
                }
            }

            // Selection overlay
            if isSelecting {
                selectionOverlay(for: transcript)
            } else {
                TranscriptCardMenu(
                    transcript: transcript,
                    onDelete: {
                        Task { await deleteTranscript(transcript) }
                    }
                )
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
                .foregroundStyle(isSelected ? Color.brandPrimary : Color.labelTertiary)
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
                Button {
                    withAnimation(TS.Animation.smooth) {
                        isSelecting = true
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadTranscripts() async {
        isLoading = true
        loadErrorMessage = nil
        do {
            let response = try await APIService.shared.getTranscripts(
                page: 1,
                limit: 100,
                sortBy: sortNewest ? "newest" : "oldest"
            )
            transcripts = response.items
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteTranscript(_ transcript: Transcript) async {
        do {
            try await APIService.shared.deleteTranscript(id: transcript.id)
            withAnimation(TS.Animation.smooth) {
                transcripts.removeAll { $0.id == transcript.id }
            }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func bulkDelete() async {
        let idsToDelete = selectedIds
        for id in idsToDelete {
            try? await APIService.shared.deleteTranscript(id: id)
        }
        withAnimation(TS.Animation.smooth) {
            transcripts.removeAll { idsToDelete.contains($0.id) }
            selectedIds.removeAll()
            isSelecting = false
        }
    }
}

// MARK: - TranscriptListCard

struct TranscriptListCard: View {

    let transcript: Transcript
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            HStack {
                Text(transcript.title)
                    .font(TS.Font.subheadlineSemibold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                Spacer(minLength: TS.Spacing.xl)
            }

            Text(formattedDate)
                .font(TS.Font.captionMonospaced)
                .foregroundStyle(Color.labelTertiary)

            if let preview = previewText, !preview.isEmpty {
                Text(preview)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }

            if !transcript.tags.isEmpty {
                HStack(spacing: TS.Spacing.xs) {
                    ForEach(transcript.tags.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(TS.Font.micro)
                            .foregroundStyle(Color.brandSecondary)
                            .padding(.horizontal, TS.Spacing.xs)
                            .padding(.vertical, 3)
                            .background {
                                Capsule().fill(Color.accentBgSecondary)
                            }
                    }
                    if transcript.tags.count > 4 {
                        Text("+\(transcript.tags.count - 4)")
                            .font(TS.Font.micro)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
            }
        }
        .padding(TS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovered = $0 }
        .modernCard(isHovered: isHovered)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: transcript.date)
    }

    private var previewText: String? {
        if let notule = transcript.notuleHtml, !notule.isEmpty {
            return notule
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
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

    // MARK: State — document

    @State private var fullTranscript: Transcript
    @State private var selectedTab: DetailTab = .notule

    enum DetailTab { case notule, raw }

    // MARK: State — title editing

    @State private var showTitleEditAlert = false
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

    // MARK: State — errors

    @State private var errorMessage: String? = nil

    // MARK: Init

    init(transcript: Transcript) {
        self.transcript = transcript
        self._fullTranscript = State(initialValue: transcript)
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: TS.Spacing.md) {
                    progressBanners
                    titleSection
                    tagsSection
                    actionButtons
                    tabBar
                    contentArea
                }
                .padding(.horizontal, TS.Spacing.md)
                .padding(.vertical, TS.Spacing.md)
            }
        }
        .navigationTitle(fullTranscript.title)
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
            ProfileSelectionSheet(mode: profileSheetMode) { profile in
                showProfileSheet = false
                if profileSheetMode == .regenerate {
                    Task { await startRegenerate(profileId: profile.id) }
                } else {
                    Task { await startRetranscribe(profileId: profile.id) }
                }
            }
            .environment(recordingVM)
        }
        .task {
            do {
                fullTranscript = try await APIService.shared.getTranscript(id: transcript.id)
            } catch {
                // fallback to passed-in value silently
            }
        }
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

    // MARK: - Title section

    @ViewBuilder private var titleSection: some View {
        HStack(alignment: .top) {
            Text(fullTranscript.title)
                .font(TS.Font.title3Bold)
                .foregroundStyle(Color.labelPrimary)

            Spacer()

            Button {
                pendingTitle = fullTranscript.title
                showTitleEditAlert = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 30, height: 30)
                    .background {
                        Circle().fill(Color.surfaceSecondary)
                    }
            }
            .buttonStyle(.plain)
        }

        Text(formattedDate)
            .font(TS.Font.captionMonospaced)
            .foregroundStyle(Color.labelTertiary)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: fullTranscript.date)
    }

    // MARK: - Tags section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.xs) {
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
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.brandSecondary.opacity(0.70))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(Color.accentBgSecondary)
                                .overlay { Capsule().stroke(Color.brandSecondary.opacity(0.25), lineWidth: 1) }
                        }
                    }

                    if showAddTagField {
                        HStack(spacing: 4) {
                            TextField("Nieuw tag", text: $newTagText)
                                .font(TS.Font.captionMedium)
                                .textFieldStyle(.plain)
                                .frame(width: 90)
                                .onSubmit { Task { await confirmAddTag() } }

                            Button {
                                Task { await confirmAddTag() }
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.brandAccent)
                            }
                            .buttonStyle(.plain)

                            Button {
                                newTagText = ""
                                showAddTagField = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.labelTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(Color.surfaceSecondary)
                                .overlay { Capsule().stroke(Color.borderPrimary, lineWidth: 1) }
                        }
                    } else {
                        Button {
                            withAnimation(TS.Animation.smooth) {
                                showAddTagField = true
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Tag")
                                    .font(TS.Font.captionMedium)
                            }
                            .foregroundStyle(Color.labelSecondary)
                            .padding(.horizontal, TS.Spacing.sm)
                            .padding(.vertical, 5)
                            .background {
                                Capsule().fill(Color.surfaceTertiary)
                                    .overlay { Capsule().stroke(Color.borderPrimary, lineWidth: 1) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TS.Spacing.sm) {
                actionPill(
                    icon: "sparkles",
                    label: "Regenereer",
                    color: Color.brandPrimary,
                    isLoading: isRegenerating
                ) {
                    profileSheetMode = .regenerate
                    showProfileSheet = true
                }

                actionPill(
                    icon: "waveform",
                    label: "Hertranscribeer",
                    color: Color.brandSecondary,
                    isLoading: isRetranscribing
                ) {
                    profileSheetMode = .retranscribe
                    showProfileSheet = true
                }

                actionPill(
                    icon: "doc.on.doc",
                    label: "Kopieer",
                    color: Color.brandAccent
                ) {
                    copyContent()
                }

                exportMenu
            }
            .padding(.horizontal, 1)
        }
    }

    private func actionPill(
        icon: String,
        label: String,
        color: Color,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TS.Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(color)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(label)
                    .font(TS.Font.captionSemibold)
            }
            .foregroundStyle(color)
            .padding(.horizontal, TS.Spacing.sm)
            .padding(.vertical, TS.Spacing.xs + 2)
            .background {
                Capsule()
                    .fill(color.opacity(0.10))
                    .overlay { Capsule().stroke(color.opacity(0.25), lineWidth: 1) }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var exportMenu: some View {
        Menu {
            Button {
                exportAs(.txt)
            } label: {
                Label("Exporteer als TXT", systemImage: "doc.text")
            }
            Button {
                exportAs(.pdf)
            } label: {
                Label("Exporteer als PDF", systemImage: "doc.richtext")
            }
            Button {
                exportAs(.word)
            } label: {
                Label("Exporteer als Word", systemImage: "doc.fill")
            }
            Divider()
            Button {
                shareContent()
            } label: {
                Label("Delen...", systemImage: "square.and.arrow.up")
            }
        } label: {
            HStack(spacing: TS.Spacing.xs) {
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 13, weight: .semibold))
                Text("Exporteer")
                    .font(TS.Font.captionSemibold)
            }
            .foregroundStyle(Color.brandOrange)
            .padding(.horizontal, TS.Spacing.sm)
            .padding(.vertical, TS.Spacing.xs + 2)
            .background {
                Capsule()
                    .fill(Color.brandOrange.opacity(0.10))
                    .overlay { Capsule().stroke(Color.brandOrange.opacity(0.25), lineWidth: 1) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        let hasNotule = !(fullTranscript.notuleHtml ?? "").isEmpty
        let hasRaw = !(fullTranscript.rawTranscription ?? "").isEmpty

        return Group {
            if hasNotule && hasRaw {
                HStack(spacing: 0) {
                    tabBarButton(.notule, label: "Notule")
                    tabBarButton(.raw, label: "Transcriptie")
                }
                .background {
                    RoundedRectangle(cornerRadius: TS.Radius.xs, style: .continuous)
                        .fill(Color.surfaceSecondary)
                }
            }
        }
    }

    private func tabBarButton(_ tab: DetailTab, label: String) -> some View {
        let isActive = selectedTab == tab
        return Button {
            withAnimation(TS.Animation.quick) {
                selectedTab = tab
            }
        } label: {
            Text(label)
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(isActive ? Color.brandPrimary : Color.labelSecondary)
                .padding(.horizontal, TS.Spacing.md)
                .padding(.vertical, TS.Spacing.xs + 2)
                .overlay(alignment: .bottom) {
                    if isActive {
                        Rectangle()
                            .fill(Color.brandPrimary)
                            .frame(height: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        let hasNotule = !(fullTranscript.notuleHtml ?? "").isEmpty
        let hasRaw = !(fullTranscript.rawTranscription ?? "").isEmpty

        if !hasNotule && !hasRaw {
            VStack(spacing: TS.Spacing.sm) {
                Image(systemName: "doc.text")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.labelTertiary)
                Text("Geen inhoud beschikbaar")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
                Text("ID: \(fullTranscript.id)")
                    .font(TS.Font.captionMonospaced)
                    .foregroundStyle(Color.labelTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(TS.Spacing.xl)
            .modernCard()
        } else if selectedTab == .notule, let html = fullTranscript.notuleHtml, !html.isEmpty {
            htmlContentView(html)
        } else if selectedTab == .raw || fullTranscript.notuleHtml == nil || fullTranscript.notuleHtml!.isEmpty {
            rawTranscriptView
        }
    }

    private func htmlContentView(_ html: String) -> some View {
        // Strip HTML to plain text for display. A WebView would be ideal but
        // for reconstruction we render stripped text with proper formatting.
        let plain = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "</h[1-6]>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<li>", with: "• ")
            .replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ScrollView {
            Text(plain)
                .font(TS.Font.body)
                .foregroundStyle(Color.labelPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(TS.Spacing.md)
        }
        .frame(maxHeight: 500)
        .modernCard()
    }

    @ViewBuilder
    private var rawTranscriptView: some View {
        if let raw = fullTranscript.rawTranscription, !raw.isEmpty {
            ScrollView {
                Text(raw)
                    .font(TS.Font.bodyMonospaced)
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TS.Spacing.md)
            }
            .frame(maxHeight: 500)
            .modernCard()
        } else {
            Text("Geen ruwe transcriptie beschikbaar")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelTertiary)
                .padding(TS.Spacing.md)
                .modernCard()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                copyContent()
            } label: {
                Image(systemName: "doc.on.doc")
            }
        }
    }

    // MARK: - Actions

    private func saveTitle() async {
        let newTitle = pendingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != fullTranscript.title else { return }
        let original = fullTranscript.title
        fullTranscript.title = newTitle
        do {
            try await APIService.shared.updateTranscriptTitle(id: fullTranscript.id, title: newTitle)
        } catch {
            fullTranscript.title = original
            errorMessage = error.localizedDescription
        }
    }

    private func removeTag(_ tag: String) async {
        let original = fullTranscript.tags
        fullTranscript.tags.removeAll { $0 == tag }
        do {
            try await APIService.shared.updateTranscriptTags(id: fullTranscript.id, tags: fullTranscript.tags)
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
        do {
            try await APIService.shared.updateTranscriptTags(id: fullTranscript.id, tags: fullTranscript.tags)
        } catch {
            fullTranscript.tags = original
            errorMessage = error.localizedDescription
        }
    }

    private func startRegenerate(profileId: String) async {
        isRegenerating = true
        regeneratingMessage = "Notule wordt geregenereerd..."
        do {
            let task = try await APIService.shared.regenerateNotule(
                transcriptId: fullTranscript.id,
                profileId: profileId
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

        // TODO: Implement retranscription when RecordingViewModel.retranscribe() is available
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

    private enum ExportFormat { case txt, pdf, word }

    private func exportAs(_ format: ExportFormat) {
        // Export implementation — delegates to platform share sheet
        let content = fullTranscript.rawTranscription
            ?? fullTranscript.notuleHtml
                .flatMap { $0.isEmpty ? nil : $0 }
                .map {
                    $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                }
            ?? ""

        let ext: String
        switch format {
        case .txt:  ext = "txt"
        case .pdf:  ext = "pdf"
        case .word: ext = "docx"
        }

        let filename = "\(fullTranscript.title).\(ext)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)

        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = []
        panel.begin { response in
            if response == .OK, let destination = panel.url {
                try? FileManager.default.copyItem(at: tempURL, to: destination)
            }
        }
        #else
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
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
    let onSelect: (Profile) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(recordingVM.availableProfiles) { profile in
                        Button {
                            onSelect(profile)
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
        }
    }
}

// MARK: - Preview

#Preview {
    TranscriptsView()
        .environment(RecordingViewModel())
}
