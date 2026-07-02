// TranscriptsViewModel.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// Manages the list of saved transcripts with pagination, search, filtering and sorting.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "TranscriptsViewModel")

// MARK: - Sort Order

enum SortOrder: String, CaseIterable, Identifiable {
    case newestFirst = "newest_first"
    case oldestFirst = "oldest_first"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newestFirst: return NSLocalizedString("sort.newestFirst", value: "Nieuwste eerst", comment: "Sort: newest first")
        case .oldestFirst: return NSLocalizedString("sort.oldestFirst", value: "Oudste eerst", comment: "Sort: oldest first")
        }
    }

    /// Maps to the API sort_by parameter value.
    var apiValue: String {
        switch self {
        case .newestFirst: return "desc"
        case .oldestFirst: return "asc"
        }
    }
}

// MARK: - Date Filter

enum DateFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case month

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:   return NSLocalizedString("filter.all",   value: "Alles",      comment: "Date filter: all")
        case .today: return NSLocalizedString("filter.today", value: "Vandaag",    comment: "Date filter: today")
        case .week:  return NSLocalizedString("filter.week",  value: "Deze week",  comment: "Date filter: this week")
        case .month: return NSLocalizedString("filter.month", value: "Deze maand", comment: "Date filter: this month")
        }
    }

    /// Returns the earliest `Date` that qualifies for this filter, or `nil` for `.all`.
    var startDate: Date? {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .all:   return nil
        case .today: return calendar.startOfDay(for: now)
        case .week:  return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
        case .month: return calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        }
    }
}

// MARK: - TranscriptsViewModel

@MainActor @Observable
final class TranscriptsViewModel {

    // MARK: - Published State

    var transcripts: [Transcript] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var searchQuery: String = ""
    var sortOrder: SortOrder = .newestFirst
    var selectedDateFilter: DateFilter = .all
    var selectedTags: Set<String> = []

    // MARK: - Derived Properties

    /// All unique tags across all loaded transcripts.
    var availableTags: [String] {
        let allTags = transcripts.flatMap { $0.tags }
        return Array(Set(allTags)).sorted()
    }

    /// Transcripts filtered locally by search query, date filter, and selected tags.
    var filteredTranscripts: [Transcript] {
        var result = transcripts

        // Apply search filter
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter { transcript in
                transcript.title.localizedCaseInsensitiveContains(trimmed)
                || (transcript.rawTranscription?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || transcript.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
        }

        // Apply date filter
        if let startDate = selectedDateFilter.startDate {
            result = result.filter { $0.date >= startDate }
        }

        // Apply tag filter
        if !selectedTags.isEmpty {
            result = result.filter { transcript in
                !selectedTags.isDisjoint(with: Set(transcript.tags))
            }
        }

        // Apply sort order (transcripts from the server are already sorted, but
        // local filtering may disturb the order after additional pages load).
        result.sort { a, b in
            switch sortOrder {
            case .newestFirst: return a.date > b.date
            case .oldestFirst: return a.date < b.date
            }
        }

        return result
    }

    // MARK: - Load

    /// Loads transcripts from the local SwiftData store and, when reachable, merges in
    /// server-side transcripts. Local records always work offline (no server required).
    func loadTranscripts() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        // Local records first — these are always available, even with the server off.
        let localTranscripts = LocalTranscriptStore.shared.allTranscripts()

        // Best-effort server fetch; never let a server failure hide local history.
        var serverTranscripts: [Transcript] = []
        do {
            let response = try await APIService.shared.getTranscripts(
                search: searchQuery.isEmpty ? nil : searchQuery
            )
            serverTranscripts = response.items
            logger.info("Loaded \(response.items.count) server transcripts")
        } catch {
            logger.info("Server transcripts unavailable, showing local only: \(error.localizedDescription)")
        }

        // Merge, preferring local records on taskId collisions.
        let localTaskIds = Set(localTranscripts.map(\.taskId))
        transcripts = localTranscripts + serverTranscripts.filter { !localTaskIds.contains($0.taskId) }

        isLoading = false
    }

    // MARK: - Delete

    /// Deletes a transcript by id. Local records are removed from the SwiftData store;
    /// records that also exist server-side are deleted there too (best-effort).
    func deleteTranscript(id: String) async {
        guard let transcript = transcripts.first(where: { $0.id == id }) else { return }

        let localRecord = LocalTranscriptStore.shared.record(forTaskId: transcript.taskId)
        if localRecord != nil {
            LocalTranscriptStore.shared.delete(taskId: transcript.taskId)
        }

        // Only hit the server for records that did not originate locally.
        if localRecord == nil {
            do {
                try await APIService.shared.deleteTranscript(taskId: transcript.taskId)
                logger.info("Deleted server transcript \(transcript.taskId)")
            } catch {
                errorMessage = error.localizedDescription
                logger.error("Failed to delete transcript \(transcript.taskId): \(error.localizedDescription)")
                return
            }
        }

        transcripts.removeAll { $0.id == id }
    }

    // MARK: - Reload Helpers

    /// Resets all filters and reloads from page 1.
    func reset() async {
        searchQuery = ""
        sortOrder = .newestFirst
        selectedDateFilter = .all
        selectedTags = []
        await loadTranscripts()
    }
}
