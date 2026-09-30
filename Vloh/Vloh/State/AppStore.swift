import SwiftUI
import CloudKit
import Network
import UIKit

@MainActor @Observable
final class AppStore {
    var archive = Archive()
    var ready = false
    var syncing = false
    var online = true
    var error: String?
    var syncMessage: String?
    var selectedGroup: GroupID?
    var activeUpload: UUID?
    var loadingAssets: Set<String> = []
    let disk: DiskStore
    let cloud = CloudService()
    let media: MediaService
    let root: URL
    private var diskTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private var fixture = false
    private var storageHealthy = true
    init() {
        let manager = FileManager.default
        root = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vloh", isDirectory: true)
        let cache = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Vloh", isDirectory: true)
        disk = DiskStore(root: root); media = MediaService(root: root, cache: cache)
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.online = connected
                if connected, self?.ready == true { self?.startQueue() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "vloh.network"))
    }
    var group: VlohGroup? { archive.groups.first { $0.id == selectedGroup } ?? archive.groups.first }
    var name: String { archive.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var user: String { archive.accountID ?? "" }
    var groupVlogs: [Vlog] { archive.vlogs.filter { $0.group == group?.id }.sorted { $0.createdAt > $1.createdAt } }
    func boot() async {
        guard !ready else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { fixture = true; seedFixture(); ready = true; return }
        #endif
        do { archive = try await disk.load() }
        catch { storageHealthy = false; self.error = error.localizedDescription; ready = true; return }
        // An interrupted process cannot remain stuck at "uploading" after relaunch.
        for index in archive.drafts.indices where archive.drafts[index].phase == .preparing || archive.drafts[index].phase == .uploading { archive.drafts[index].phase = .queued }
        selectedGroup = archive.groups.first?.id
        ready = true
        await refresh()
        startQueue()
    }
    func persist() async throws {
        guard storageHealthy else { throw VlohError.message("Saved data is protected. Contact support before making changes.") }
        guard !fixture else { return }
        let snapshot = archive
        let previous = diskTask
        let disk = self.disk
        let task = Task { if let previous { await previous.value }; try await disk.save(snapshot) }
        diskTask = Task { _ = try? await task.value }
        try await task.value
    }
    func save() { Task { do { try await persist() } catch { self.error = error.localizedDescription } } }
    func refresh() async {
        guard !fixture, storageHealthy, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let account = try await cloud.identity()
            if let previous = archive.accountID, previous != account {
                throw VlohError.message("Your iCloud account changed. Switch back to the original account to protect your saved drafts.")
            }
            archive.accountID = account
            let snapshot = try await cloud.snapshot()
            archive.groups = snapshot.groups.sorted { $0.createdAt < $1.createdAt }
            archive.members = snapshot.members; archive.vlogs = snapshot.vlogs
            archive.replies = snapshot.replies; archive.reactions = snapshot.reactions
            if let selectedGroup, !archive.groups.contains(where: { $0.id == selectedGroup }) { self.selectedGroup = archive.groups.first?.id }
            for group in archive.groups where !name.isEmpty && !archive.members.contains(where: { $0.group == group.id && $0.id == account }) {
                try await cloud.join(group: group.id, user: account, name: name)
            }
            syncMessage = nil
            try await persist()
        } catch { syncMessage = error.localizedDescription }
    }
    func createGroup(name: String, rotation: Bool) async {
        guard !self.name.isEmpty else { error = "Add your name in Settings first."; return }
        do {
            let group: VlohGroup
            if fixture { group = VlohGroup(id: GroupID(zone: UUID().uuidString, owner: "test", shared: false), name: name, createdAt: .now, rotation: rotation, timeZone: "UTC") }
            else {
                let account = try await cloud.identity()
                archive.accountID = account
                group = try await cloud.createGroup(name: name, rotation: rotation)
                try await cloud.join(group: group.id, user: account, name: self.name)
            }
            archive.groups.append(group); selectedGroup = group.id
            try await persist(); await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func newDraft() async -> UUID? {
        guard let group else { error = "Create or join a group first."; return nil }
        let draft = Draft(group: group.id)
        archive.drafts.append(draft)
        do { try await persist(); return draft.id }
        catch { archive.drafts.removeAll { $0.id == draft.id }; self.error = error.localizedDescription; return nil }
    }
    func update(_ draft: Draft) async throws {
        guard let index = archive.drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        archive.drafts[index] = draft
        try await persist()
    }
    func removeDraft(_ draft: Draft) async {
        guard activeUpload != draft.id else { return }
        let old = archive.drafts
        archive.drafts.removeAll { $0.id == draft.id }
        do { try await persist(); await media.cleanup(draft) }
        catch { archive.drafts = old; self.error = error.localizedDescription }
    }
    func publish(_ id: UUID) async {
        guard let index = archive.drafts.firstIndex(where: { $0.id == id }), !archive.drafts[index].clips.isEmpty else { return }
        guard !name.isEmpty, !user.isEmpty else { error = "Add your name and connect to iCloud before posting."; return }
        archive.drafts[index].phase = .queued; archive.drafts[index].error = nil
        do { try await persist(); startQueue() } catch { self.error = error.localizedDescription }
    }
    func startQueue() {
        guard !fixture, storageHealthy, online, !user.isEmpty, uploadTask == nil else { return }
        uploadTask = Task { await runQueue(); uploadTask = nil }
    }
    private func runQueue() async {
        do {
            guard try await cloud.identity() == user else { throw VlohError.message("Switch back to your original iCloud account to upload these drafts.") }
        } catch { syncMessage = error.localizedDescription; return }
        while online, let draft = archive.drafts.first(where: { $0.phase == .queued }) {
            activeUpload = draft.id
            let background = UIApplication.shared.beginBackgroundTask(withName: "Vloh upload") { [weak self] in
                Task { @MainActor in self?.uploadTask?.cancel() }
            }
            do {
                var current = draft
                if current.exportedFile == nil {
                    current.phase = .preparing; try await update(current)
                    let export = try await media.export(current)
                    current.exportedFile = export.video
                    current.phase = .queued; try await update(current)
                }
                try Task.checkCancellation()
                current.phase = .uploading; try await update(current)
                guard let file = current.exportedFile else { throw VlohError.message("Your draft needs to be exported again.") }
                let video = await media.exportURL(file)
                let poster = await media.exportURL(file + ".jpg")
                let vlog = try await cloud.post(current, author: user, name: name, video: video, poster: poster)
                if !archive.vlogs.contains(where: { $0.id == vlog.id && $0.group == vlog.group }) { archive.vlogs.append(vlog) }
                let savedDrafts = archive.drafts
                archive.drafts.removeAll { $0.id == draft.id }
                do { try await persist() } catch { archive.drafts = savedDrafts; throw error }
                await media.cleanup(current)
            } catch {
                if let index = archive.drafts.firstIndex(where: { $0.id == draft.id }) {
                    archive.drafts[index].phase = .failed
                    archive.drafts[index].error = error is CancellationError ? "Upload paused when Vloh went to the background. Tap Retry when you're ready." : error.localizedDescription
                    try? await persist()
                }
            }
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            activeUpload = nil
            if Task.isCancelled { return }
        }
    }
    func file(for vlog: Vlog, poster: Bool = false) async throws -> URL {
        let destination = await media.cachedURL(vlog, poster: poster)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        guard !fixture else { throw VlohError.message("Preview videos are not included in the test fixture.") }
        let url = try await cloud.asset(vlog, key: poster ? "poster" : "video", destination: destination)
        try await media.purgeCache(keeping: url)
        return url
    }
    func send(text: String, vlog: Vlog? = nil) async -> Bool {
        guard let group, !name.isEmpty else { error = "Add your name before replying."; return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000 else { return false }
        do {
            if fixture { archive.replies.append(Reply(id: UUID().uuidString, group: group.id, vlogID: vlog?.id, authorID: user, authorName: name, text: trimmed, createdAt: .now)) }
            else { try await cloud.reply(group: group.id, vlogID: vlog?.id, author: user, name: name, text: trimmed); await refresh() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func react(_ vlog: Vlog, emoji: String) async {
        do { if !fixture { try await cloud.react(vlog: vlog, author: user, emoji: emoji); await refresh() } }
        catch { self.error = error.localizedDescription }
    }
    func delete(_ vlog: Vlog) async {
        guard vlog.authorID == user else { return }
        do { if !fixture { try await cloud.delete(vlog) }; archive.vlogs.removeAll { $0.id == vlog.id && $0.group == vlog.group }; try await persist() }
        catch { self.error = error.localizedDescription }
    }
    func saveName(_ name: String) async {
        archive.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        do {
            try await persist()
            if !fixture, !user.isEmpty { for group in archive.groups { try await cloud.join(group: group.id, user: user, name: self.name) }; await refresh() }
        } catch { self.error = error.localizedDescription }
    }
    func accept(_ metadata: CKShare.Metadata) async {
        do { try await cloud.accept(metadata); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    #if DEBUG
    private func seedFixture() {
        archive.name = "Max"; archive.accountID = "max"
        let id = GroupID(zone: "friends", owner: "test", shared: false)
        let group = VlohGroup(id: id, name: "The buddies", createdAt: Date(timeIntervalSince1970: 1_700_000_000), rotation: true, timeZone: "America/Los_Angeles")
        archive.groups = [group]; selectedGroup = id
        archive.members = [Member(id: "max", group: id, name: "Max", joinedAt: .distantPast), Member(id: "sam", group: id, name: "Sam", joinedAt: Date(timeIntervalSince1970: 1))]
        archive.vlogs = [Vlog(id: "preview", group: id, authorID: "sam", authorName: "Sam", caption: "A little bit of today", createdAt: .now, duration: 83)]
        archive.drafts = [Draft(group: id, caption: "Weekend adventures")]
    }
    #endif
}
