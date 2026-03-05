import Foundation
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "OfflineQueue")

// MARK: - OfflineQueue

/// A persistent queue of failed upload items that should be retried when connectivity returns.
///
/// Items are stored in a JSON file in the app's Documents directory so they survive app restarts.
/// Audio file URLs are exposed via `queuedAudioURLs` to protect them from the 7-day cleanup.
@Observable
final class OfflineQueue: @unchecked Sendable {

    static let shared = OfflineQueue()

    // MARK: - Observable State

    private(set) var items: [QueuedItem] = []

    /// Set of audio file URLs currently queued, used to protect them from cleanup.
    var queuedAudioURLs: Set<URL> {
        var urls = Set<URL>()
        for item in items {
            if case .audio(let url, _) = item {
                urls.insert(url)
            }
        }
        return urls
    }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    // MARK: - Private

    private static let fileName = "offline_queue.json"

    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(Self.fileName)
    }

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Queue Operations

    /// Adds an item to the end of the queue and persists it.
    func enqueue(_ item: QueuedItem) {
        items.append(item)
        persist()
        logger.info("OfflineQueue: enqueued item — total \(self.items.count)")
    }

    /// Removes and returns the first item in the queue, or nil if empty.
    @discardableResult
    func dequeue() -> QueuedItem? {
        guard !items.isEmpty else { return nil }
        let item = items.removeFirst()
        persist()
        logger.info("OfflineQueue: dequeued item — remaining \(self.items.count)")
        return item
    }

    /// Removes a specific item from the queue by identity (Codable equality).
    func removeItem(_ item: QueuedItem) {
        guard let index = indexOfItem(item) else { return }
        items.remove(at: index)
        persist()
        logger.info("OfflineQueue: removed item — remaining \(self.items.count)")
    }

    /// Replaces an item with an updated copy (e.g., with incremented retry count).
    func replaceItem(_ old: QueuedItem, with new: QueuedItem) {
        guard let index = indexOfItem(old) else { return }
        items[index] = new
        persist()
    }

    /// Clears all items from the queue.
    func clear() {
        items.removeAll()
        persist()
        logger.info("OfflineQueue: cleared all items")
    }

    // MARK: - Identity Helpers

    private func indexOfItem(_ item: QueuedItem) -> Int? {
        // Find by encoding and comparing JSON representation
        guard let targetData = try? JSONEncoder().encode(item) else { return nil }
        return items.firstIndex { candidate in
            guard let candidateData = try? JSONEncoder().encode(candidate) else { return false }
            return candidateData == targetData
        }
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            logger.error("OfflineQueue: failed to persist — \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            logger.info("OfflineQueue: no persisted queue found, starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: storageURL)
            items = try JSONDecoder().decode([QueuedItem].self, from: data)
            logger.info("OfflineQueue: loaded \(self.items.count) persisted item(s)")
        } catch {
            logger.error("OfflineQueue: failed to load persisted queue — \(error.localizedDescription)")
            // Corrupt file: reset to empty
            items = []
            try? FileManager.default.removeItem(at: storageURL)
        }
    }
}
