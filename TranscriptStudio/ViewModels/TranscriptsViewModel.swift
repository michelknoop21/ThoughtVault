// TranscriptsViewModel.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Manages the list of saved transcripts with pagination, search, filtering and sorting.

import Foundation
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "TranscriptsViewModel")

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

@Observable
final class TranscriptsViewModel {

    // MARK: - Published State

    var transcripts: [Transcript] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var searchQuery: String = ""
    var sortOrder: SortOrder = .newestFirst
    var selectedDateFilter: DateFilter = .all
    var selectedTags: Set<String> = []
    var page: Int = 1
    var hasMore: Bool = true

    // MARK: - Private Constants

    private let pageSize = 20

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

    /// Loads the first page of transcripts, replacing any existing results.
    @MainActor
    func loadTranscripts() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        page = 1
        hasMore = true

        do {
            let response = try await APIService.shared.getTranscripts(
                page: 1,
                limit: pageSize,
                search: searchQuery.isEmpty ? nil : searchQuery,
                sortBy: sortOrder.apiValue
            )
            transcripts = response.items
            hasMore = response.items.count >= pageSize && (response.total.map { $0 > response.items.count } ?? true)
            logger.info("Loaded \(response.items.count) transcripts (total: \(response.total ?? -1))")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to load transcripts: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Loads the next page of transcripts and appends them to the existing list.
    @MainActor
    func loadMore() async {
        guard !isLoading, hasMore else { return }

        isLoading = true
        let nextPage = page + 1

        do {
            let response = try await APIService.shared.getTranscripts(
                page: nextPage,
                limit: pageSize,
                search: searchQuery.isEmpty ? nil : searchQuery,
                sortBy: sortOrder.apiValue
            )

            let newItems = response.items.filter { incoming in
                !transcripts.contains { $0.id == incoming.id }
            }
            transcripts.append(contentsOf: newItems)
            page = nextPage
            hasMore = response.items.count >= pageSize &&
                      (response.total.map { $0 > transcripts.count } ?? true)

            logger.info("Loaded page \(nextPage): +\(newItems.count) transcripts")
        } catch {
            // Non-fatal — keep existing transcripts, surface error briefly
            errorMessage = error.localizedDescription
            logger.error("Failed to load page \(nextPage): \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Delete

    /// Deletes a transcript by id from both the server and the local list.
    @MainActor
    func deleteTranscript(id: String) async {
        do {
            try await APIService.shared.deleteTranscript(id: id)
            transcripts.removeAll { $0.id == id }
            logger.info("Deleted transcript \(id)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to delete transcript \(id): \(error.localizedDescription)")
        }
    }

    // MARK: - Reload Helpers

    /// Resets all filters and reloads from page 1.
    @MainActor
    func reset() async {
        searchQuery = ""
        sortOrder = .newestFirst
        selectedDateFilter = .all
        selectedTags = []
        await loadTranscripts()
    }
}
