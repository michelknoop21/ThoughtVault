// TasksViewModel.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Manages active backend tasks with auto-refresh, cancel, and delete support.

import Foundation
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "TasksViewModel")

@MainActor
@Observable
final class TasksViewModel {

    // MARK: - Published State

    var activeTasks: [TranscriptTask] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Private

    private var refreshTimer: Task<Void, Never>?

    // MARK: - Load

    /// Fetch active tasks from the backend.
    func loadActiveTasks() async {
        // Local mode tracks active tasks in RecordingViewModel, not the server.
        guard !ProcessingMode.isLocalMode else { return }
        isLoading = true
        errorMessage = nil
        do {
            activeTasks = try await APIService.shared.getActiveTasks()
            logger.info("Loaded \(self.activeTasks.count) active tasks")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to load active tasks: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Cancel

    /// Cancel an in-progress task and refresh the list.
    func cancelTask(_ taskId: String) async {
        do {
            try await APIService.shared.cancelTask(taskId: taskId)
            logger.info("Cancelled task \(taskId)")
            await loadActiveTasks()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to cancel task \(taskId): \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    /// Delete a task and remove it from the local list.
    func deleteTask(_ taskId: String) async {
        do {
            try await APIService.shared.deleteTask(taskId: taskId)
            activeTasks.removeAll { $0.taskId == taskId }
            logger.info("Deleted task \(taskId)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to delete task \(taskId): \(error.localizedDescription)")
        }
    }

    // MARK: - Auto-Refresh

    /// Start auto-refresh polling every 10 seconds.
    func startAutoRefresh() {
        // No backend polling in local mode.
        guard !ProcessingMode.isLocalMode else { return }
        stopAutoRefresh()
        refreshTimer = Task {
            while !Task.isCancelled {
                await loadActiveTasks()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// Stop the auto-refresh timer.
    func stopAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }
}
