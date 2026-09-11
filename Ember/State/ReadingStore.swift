import Foundation
import Observation

@MainActor @Observable
final class ReadingStore {
    private(set) var archive: ReadingArchive
    var error: String?
    private(set) var needsRecovery = false
    @ObservationIgnored private let writer: ArchiveWriter
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    init(directory: URL) {
        url = directory.appendingPathComponent("reading-library.json")
        writer = ArchiveWriter(url: url)
        do { archive = try ArchiveFile.read(at: url) }
        catch {
            archive = ReadingArchive()
            needsRecovery = true
            self.error = "Your saved data couldn’t be read. Ember has kept the original file and paused saving. You can recover in Settings."
        }
    }

    var bookmarks: [SavedStory] { archive.bookmarks }
    var history: [SavedStory] { archive.history }
    var blockedUsers: [String] { archive.blockedUsers.sorted() }
    func isSaved(_ id: Int) -> Bool { archive.bookmarks.contains { $0.id == id } }
    func isRead(_ id: Int) -> Bool { archive.history.contains { $0.id == id } }
    func isBlocked(_ user: String?) -> Bool { user.map { archive.blockedUsers.contains($0) } ?? false }
    func isHidden(_ item: HNItem) -> Bool { archive.hiddenStories.contains(item.id) || isBlocked(item.by) }

    func toggleBookmark(_ item: HNItem) { change { $0.toggleBookmark(item) } }
    func record(_ item: HNItem) { change { $0.record(item) } }
    func block(_ user: String) { change { $0.blockedUsers.insert(user) } }
    func unblock(_ user: String) { change { $0.blockedUsers.remove(user) } }
    func hide(_ id: Int) { change { $0.hiddenStories.insert(id) } }
    func restoreHidden() { change { $0.hiddenStories.removeAll() } }
    func clearHistory() { change { $0.history.removeAll() } }
    func removeBookmark(_ id: Int) { change { $0.bookmarks.removeAll { $0.id == id } } }
    func clearBookmarks() { change { $0.bookmarks.removeAll() } }

    func flush() async { await writeTask?.value }

    func retrySave() {
        guard !needsRecovery else { return }
        save()
    }

    func recover() {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let backup = url.deletingLastPathComponent().appendingPathComponent("reading-library-recovery-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: url, to: backup)
            }
            needsRecovery = false
            save()
        } catch { self.error = "The original file couldn’t be backed up. Nothing was changed. \(error.localizedDescription)" }
    }

    private func change(_ body: (inout ReadingArchive) -> Void) {
        guard !needsRecovery else {
            error = "Saving is paused to protect your original data. Open Settings to recover."
            return
        }
        body(&archive)
        save()
    }

    private func save() {
        revision += 1
        let current = revision
        let snapshot = archive
        let previous = writeTask
        writeTask = Task { [weak self, writer] in
            // Queue writes in mutation order, including across suspension points.
            await previous?.value
            do {
                try await writer.write(snapshot, revision: current)
                if self?.revision == current { self?.error = nil }
            } catch {
                self?.error = "Your changes couldn’t be saved to this device. \(error.localizedDescription)"
            }
        }
    }
}
