import SwiftUI
import CloudKit
import Network
import UIKit
import AuthenticationServices

@MainActor @Observable
final class AppStore {
    var archive = Archive()
    var ready = false
    var syncing = false
    var online = true
    var error: String?
    var syncMessage: String?
    var signedOut = UserDefaults.standard.bool(forKey: "signedOut")
    var accountDeleted = false
    var photoRevision = UUID()
    var blockedAuthors: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "blockedAuthors") ?? [])
    var hiddenContent: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenContent") ?? [])
    var selectedGroup: GroupID?
    var activeUpload: UUID?
    var loadingAssets: Set<String> = []
    let disk: DiskStore
    let cloud = CloudService()
    let media: MediaService
    let root: URL
    private var diskTask: Task<Void, Never>?
    private var assetTasks: [String: Task<URL, Error>] = [:]
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
    var groupVlogs: [Vlog] { group.map { visibleVlogs(in: $0.id) } ?? [] }
    func visibleVlogs(in group: GroupID) -> [Vlog] { archive.vlogs.filter { $0.group == group && !isBlocked($0.authorID) && !hiddenContent.contains(group.key + "/" + $0.id) }.sorted { ($0.vlogDay ?? $0.createdAt) > ($1.vlogDay ?? $1.createdAt) } }
    func isBlocked(_ user: String) -> Bool { blockedAuthors.contains(user) }
    func toggleBlock(_ user: String) { if blockedAuthors.contains(user) { blockedAuthors.remove(user) } else { blockedAuthors.insert(user) }; UserDefaults.standard.set(Array(blockedAuthors), forKey: "blockedAuthors") }
    func hide(_ id: String, group: GroupID) { hiddenContent.insert(group.key + "/" + id); UserDefaults.standard.set(Array(hiddenContent), forKey: "hiddenContent") }
    var profilePhotoURL: URL? { archive.hasProfilePhoto == true ? root.appendingPathComponent("ProfilePhoto.jpg") : nil }
    func groupPhotoURL(_ group: GroupID) -> URL { let key = Data(group.key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_"); return root.appendingPathComponent("GroupPhotos/" + key + ".jpg") }
    func connectApple(user: String, displayName: String) async {
        error = nil
        if !fixture {
            do { let iCloudUser = try await cloud.identity(); if let original = archive.accountID, original != iCloudUser { throw VlohError.message("Use the iCloud account linked to this Vloh profile.") }; archive.accountID = iCloudUser }
            catch { self.error = error.localizedDescription; return }
        }
        guard archive.appleUserID == nil || archive.appleUserID == user else { error = "Use the Apple account already linked to this Vloh profile."; return }
        archive.appleUserID = user
        let value = displayName.isEmpty ? name : displayName
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter a display name to finish creating your account."; return }
        await saveName(value)
        if error == nil { signedOut = false; UserDefaults.standard.set(false, forKey: "signedOut") }
    }
    func signOut() { signedOut = true; UserDefaults.standard.set(true, forKey: "signedOut") }
    func saveProfilePhoto(_ data: Data) async throws {
        let url = root.appendingPathComponent("ProfilePhoto.jpg")
        try await PhotoService.save(data, to: url)
        if !fixture {
            try await cloud.saveProfile(name: name, appleUser: archive.appleUserID, photo: url)
            for group in archive.groups { try await cloud.join(group: group.id, user: user, name: name, photo: url) }
        }
        archive.hasProfilePhoto = true; photoRevision = UUID(); try await persist()
    }
    func leaveGroup(_ group: GroupID) async {
        guard activeUpload == nil else { error = "Wait for your upload to finish first."; return }
        do { if !fixture { try await cloud.leave(group) }; archive.groups.removeAll { $0.id == group }; archive.members.removeAll { $0.group == group }; archive.vlogs.removeAll { $0.group == group }; archive.replies.removeAll { $0.group == group }; selectedGroup = archive.groups.first?.id; try await persist() }
        catch { self.error = error.localizedDescription }
    }
    func deleteAccount() async {
        guard activeUpload == nil, !syncing else { error = "Wait for uploads and refresh to finish, then try again."; return }
        do {
            if !fixture { try await cloud.deleteAccount(user: user) }
            for draft in archive.drafts { await media.cleanup(draft) }
            for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: file) }
            archive = Archive(); selectedGroup = nil; blockedAuthors = []; hiddenContent = []; accountDeleted = true
            UserDefaults.standard.removeObject(forKey: "blockedAuthors"); UserDefaults.standard.removeObject(forKey: "hiddenContent")
            try await persist()
        } catch { self.error = error.localizedDescription }
    }
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
        await recoverCaptures()
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
        guard ready, !fixture, storageHealthy, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let account = try await cloud.identity()
            if let previous = archive.accountID, previous != account {
                throw VlohError.message("Your iCloud account changed. Switch back to the original account to protect your saved drafts.")
            }
            archive.accountID = account
            if let profile = try? await cloud.profile(destination: root.appendingPathComponent("ProfilePhoto.jpg")) {
                archive.name = profile.0; archive.appleUserID = profile.1; archive.hasProfilePhoto = profile.2
            }
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
    func recordingDraft(day: Date? = nil) async -> UUID? {
        guard let group else { error = "Create or join a group first."; return nil }
        let days = VlogCalendar.availableDays(for: user, group: group, members: archive.members, now: .now)
        let preferred = archive.drafts.first { draft in draft.group == group.id && draft.canEdit && !draft.clips.isEmpty && draft.vlogDay.map { days.contains($0) && VlogCalendar.window(for: $0, in: group).contains(.now) } == true }?.vlogDay
        let currentWindow = days.first { VlogCalendar.window(for: $0, in: group).contains(.now) }
        guard let chosen = day ?? preferred ?? currentWindow ?? days.first else { error = "It's someone else's vlog day. Check your group's schedule for your next turn."; return nil }
        guard days.contains(VlogCalendar.day(chosen, in: group)) else { error = "Choose one of your scheduled days."; return nil }
        if let draft = archive.drafts.first(where: { $0.group == group.id && $0.canEdit && $0.vlogDay.map { VlogCalendar.key($0, in: group) == VlogCalendar.key(chosen, in: group) } == true }) { return draft.id }
        return await newDraft(day: chosen)
    }
    func newDraft(day: Date? = nil) async -> UUID? {
        guard let group else { error = "Create or join a group first."; return nil }
        let draft = Draft(group: group.id, vlogDay: day)
        archive.drafts.append(draft)
        do { try await persist(); return draft.id }
        catch { archive.drafts.removeAll { $0.id == draft.id }; self.error = error.localizedDescription; return nil }
    }
    func update(_ draft: Draft) async throws {
        guard let index = archive.drafts.firstIndex(where: { $0.id == draft.id }), archive.drafts[index].canEdit else { return }
        archive.drafts[index] = draft
        try await persist()
    }
    func updateUpload(_ draft: Draft) async throws {
        guard activeUpload == draft.id,
              let index = archive.drafts.firstIndex(where: { $0.id == draft.id }) else {
            throw VlohError.message("This upload is no longer active.")
        }
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
        guard ContentPolicy.allows(archive.drafts[index].caption) else { error = "Edit the caption to follow the community rules."; return }
        guard let target = archive.groups.first(where: { $0.id == archive.drafts[index].group }) else { error = "This group is unavailable."; return }
        do { try VlogCalendar.validate(archive.drafts[index], group: target, members: archive.members, user: user, now: .now) }
        catch { self.error = error.localizedDescription; return }
        if archive.vlogs.contains(where: { $0.group == target.id && $0.vlogDay.map { VlogCalendar.key($0, in: target) == VlogCalendar.key(archive.drafts[index].vlogDay!, in: target) } == true }) { error = "This day already has its vlog."; return }
        archive.drafts[index].phase = .queued; archive.drafts[index].error = nil
        do { try await persist(); startQueue() } catch { self.error = error.localizedDescription }
    }
    func startQueue() {
        guard !fixture, !signedOut, storageHealthy, online, !user.isEmpty, uploadTask == nil else { return }
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
                    current.phase = .preparing; try await updateUpload(current)
                    let export = try await media.export(current)
                    current.exportedFile = export.video
                    current.phase = .queued; try await updateUpload(current)
                }
                try Task.checkCancellation()
                current.phase = .uploading; try await updateUpload(current)
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
        #if DEBUG
        if fixture, let url = Bundle.main.url(forResource: "Preview", withExtension: "mp4"), !poster { return url }
        #endif
        guard !fixture else { throw VlohError.message("Preview image isn't included in this fixture.") }
        let key = destination.lastPathComponent
        if let task = assetTasks[key] { return try await task.value }
        let cloud = self.cloud
        let task = Task { try await cloud.asset(vlog, key: poster ? "poster" : "video", destination: destination) }
        assetTasks[key] = task
        defer { assetTasks[key] = nil }
        let url = try await task.value
        try await media.purgeCache(keeping: url)
        return url
    }
    func preloadRecentVideos() async {
        guard online else { return }
        for vlog in groupVlogs.prefix(3) {
            guard !Task.isCancelled, online, activeUpload == nil else { return }
            _ = try? await file(for: vlog)
        }
    }
    func recoverCaptures() async {
        let folder = root.appendingPathComponent("PendingCapture")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for url in files {
            guard let id = UUID(uuidString: String(url.lastPathComponent.prefix(36))), let index = archive.drafts.firstIndex(where: { $0.id == id && $0.canEdit }) else { continue }
            do {
                if archive.drafts[index].clips.contains(where: { $0.sourceCapture == url.lastPathComponent }) { try FileManager.default.removeItem(at: url); continue }
                let clip = try await media.importClip(from: url)
                archive.drafts[index].clips.append(clip); archive.drafts[index].invalidateExport()
                try await persist(); try FileManager.default.removeItem(at: url)
            } catch { syncMessage = "An interrupted recording is kept on this iPhone. " + error.localizedDescription }
        }
    }
    func send(text: String, vlog: Vlog? = nil) async -> Bool {
        guard let groupID = vlog?.group ?? group?.id, !name.isEmpty, !user.isEmpty else { error = "Connect to your group before replying."; return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000 else { return false }
        guard ContentPolicy.allows(trimmed) else { error = "That message contains abusive language. Edit it before sending."; return false }
        do {
            if fixture { archive.replies.append(Reply(id: UUID().uuidString, group: groupID, vlogID: vlog?.id, authorID: user, authorName: name, text: trimmed, createdAt: .now)) }
            else { try await cloud.reply(group: groupID, vlogID: vlog?.id, author: user, name: name, text: trimmed); await refresh() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func react(_ vlog: Vlog, emoji: String) async {
        do { if !fixture { try await cloud.react(vlog: vlog, author: user, emoji: emoji); await refresh() } }
        catch { self.error = error.localizedDescription }
    }
    func deleteReply(_ reply: Reply) async {
        guard reply.authorID == user || !reply.group.shared else { return }
        do { if !fixture { try await cloud.deleteReply(reply) }; archive.replies.removeAll { $0.group == reply.group && $0.id == reply.id }; try await persist() } catch { self.error = error.localizedDescription }
    }
    func delete(_ vlog: Vlog) async {
        guard vlog.authorID == user || !vlog.group.shared else { return }
        do { if !fixture { try await cloud.delete(vlog) }; archive.vlogs.removeAll { $0.id == vlog.id && $0.group == vlog.group }; try await persist() }
        catch { self.error = error.localizedDescription }
    }
    func saveName(_ name: String) async {
        archive.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        do {
            try await persist()
            if !fixture, !user.isEmpty { try await cloud.saveProfile(name: self.name, appleUser: archive.appleUserID, photo: profilePhotoURL); for group in archive.groups { try await cloud.join(group: group.id, user: user, name: self.name, photo: profilePhotoURL) }; await refresh() }
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
        let group = VlohGroup(id: id, name: "The buddies", createdAt: Calendar.current.startOfDay(for: .now), rotation: true, timeZone: "America/Los_Angeles")
        archive.groups = [group]; selectedGroup = id
        archive.members = [Member(id: "max", group: id, name: "Max", joinedAt: .distantPast), Member(id: "sam", group: id, name: "Sam", joinedAt: Date(timeIntervalSince1970: 1))]
        archive.vlogs = [Vlog(id: "preview", group: id, authorID: "sam", authorName: "Sam", caption: "A little bit of today", createdAt: .now, duration: 83)]
        archive.drafts = [Draft(group: id, caption: "Weekend adventures", vlogDay: VlogCalendar.day(.now, in: group))]
    }
    #endif
}
