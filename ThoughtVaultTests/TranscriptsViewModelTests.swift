// TranscriptsViewModelTests.swift
// ThoughtVaultTests
// nl.prezent.ThoughtVault

import Testing
import Foundation
@testable import ThoughtVault

@Suite("TranscriptsViewModel Tests")
struct TranscriptsViewModelTests {

    // MARK: - Filtering

    @Test("filteredTranscripts returns all when search is empty")
    @MainActor
    func filteredTranscriptsEmptySearch() {
        let vm = TranscriptsViewModel()
        vm.transcripts = [
            Transcript(id: "1", title: "Vergadering A", tags: ["werk"]),
            Transcript(id: "2", title: "Gesprek B", tags: ["privé"]),
            Transcript(id: "3", title: "Notitie C", tags: [])
        ]
        vm.searchText = ""

        #expect(vm.filteredTranscripts.count == 3)
    }

    @Test("filteredTranscripts filters by search text (case-insensitive)")
    @MainActor
    func filteredTranscriptsBySearchText() {
        let vm = TranscriptsViewModel()
        vm.transcripts = [
            Transcript(id: "1", title: "Vergadering Maandag", tags: []),
            Transcript(id: "2", title: "Sprint Planning", tags: []),
            Transcript(id: "3", title: "vergadering dinsdag", tags: [])
        ]
        vm.searchText = "vergadering"

        let results = vm.filteredTranscripts
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.title.lowercased().contains("vergadering") })
    }

    @Test("filteredTranscripts filters by selected tag")
    @MainActor
    func filteredTranscriptsByTag() {
        let vm = TranscriptsViewModel()
        vm.transcripts = [
            Transcript(id: "1", title: "A", tags: ["werk", "urgent"]),
            Transcript(id: "2", title: "B", tags: ["privé"]),
            Transcript(id: "3", title: "C", tags: ["werk"])
        ]
        vm.selectedTag = "werk"

        let results = vm.filteredTranscripts
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.tags.contains("werk") })
    }

    @Test("filteredTranscripts filters by both search and tag")
    @MainActor
    func filteredTranscriptsBySearchAndTag() {
        let vm = TranscriptsViewModel()
        vm.transcripts = [
            Transcript(id: "1", title: "Vergadering werk", tags: ["werk"]),
            Transcript(id: "2", title: "Vergadering privé", tags: ["privé"]),
            Transcript(id: "3", title: "Planning werk", tags: ["werk"])
        ]
        vm.searchText = "vergadering"
        vm.selectedTag = "werk"

        let results = vm.filteredTranscripts
        #expect(results.count == 1)
        #expect(results[0].id == "1")
    }

    @Test("filteredTranscripts returns empty when no match")
    @MainActor
    func filteredTranscriptsNoMatch() {
        let vm = TranscriptsViewModel()
        vm.transcripts = [
            Transcript(id: "1", title: "Vergadering", tags: ["werk"])
        ]
        vm.searchText = "xxxxxxx"

        #expect(vm.filteredTranscripts.isEmpty)
    }

    // MARK: - Available Tags

    @Test("availableTags returns unique sorted tags from all transcripts")
    @MainActor
    func availableTagsUniqueSorted() {
        let vm = TranscriptsViewModel()
        vm.transcripts = [
            Transcript(id: "1", title: "A", tags: ["werk", "urgent"]),
            Transcript(id: "2", title: "B", tags: ["privé", "werk"]),
            Transcript(id: "3", title: "C", tags: ["sprint"])
        ]

        let tags = vm.availableTags
        // Should be unique
        #expect(Set(tags).count == tags.count)
        // Should be sorted
        #expect(tags == tags.sorted())
        // Should contain all unique tags
        #expect(tags.contains("werk"))
        #expect(tags.contains("urgent"))
        #expect(tags.contains("privé"))
        #expect(tags.contains("sprint"))
        #expect(tags.count == 4)
    }

    @Test("availableTags returns empty array when no transcripts")
    @MainActor
    func availableTagsEmpty() {
        let vm = TranscriptsViewModel()
        vm.transcripts = []
        #expect(vm.availableTags.isEmpty)
    }

    // MARK: - Sorting

    @Test("filteredTranscripts sorted by date descending by default")
    @MainActor
    func filteredTranscriptsSortedByDateDesc() {
        let vm = TranscriptsViewModel()
        let now = Date()
        vm.transcripts = [
            Transcript(id: "old", title: "Old", date: now.addingTimeInterval(-86400)),
            Transcript(id: "new", title: "New", date: now),
            Transcript(id: "mid", title: "Mid", date: now.addingTimeInterval(-3600))
        ]

        let results = vm.filteredTranscripts
        // Newest first
        #expect(results[0].id == "new")
        #expect(results[1].id == "mid")
        #expect(results[2].id == "old")
    }

    // MARK: - Local Deletion

    @Test("deleteLocally removes transcript from array")
    @MainActor
    func deleteLocallyRemovesTranscript() {
        let vm = TranscriptsViewModel()
        vm.transcripts = [
            Transcript(id: "1", title: "First"),
            Transcript(id: "2", title: "Second"),
            Transcript(id: "3", title: "Third")
        ]

        vm.deleteLocally(id: "2")

        #expect(vm.transcripts.count == 2)
        #expect(!vm.transcripts.contains(where: { $0.id == "2" }))
    }

    @Test("deleteLocally is a no-op for unknown ID")
    @MainActor
    func deleteLocallyUnknownId() {
        let vm = TranscriptsViewModel()
        vm.transcripts = [
            Transcript(id: "1", title: "Only")
        ]

        vm.deleteLocally(id: "unknown-id")

        #expect(vm.transcripts.count == 1)
    }

    // MARK: - Pagination State

    @Test("Initial state has correct defaults")
    @MainActor
    func initialStateDefaults() {
        let vm = TranscriptsViewModel()

        #expect(vm.transcripts.isEmpty)
        #expect(vm.searchText.isEmpty)
        #expect(vm.selectedTag == nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }
}
