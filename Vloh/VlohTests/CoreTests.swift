import XCTest
#if SWIFT_PACKAGE
@testable import VlohCore
#else
@testable import Vloh
#endif

final class CoreTests: XCTestCase {
    let id = GroupID(zone: "group", owner: "owner", shared: false)
    #if !SWIFT_PACKAGE
    @MainActor func testQueuedDraftRejectsStaleEditButPersistsUploadProgress() async throws {
        let store = AppStore()
        await store.boot()
        var draft = Draft(group: id, caption: "Queued", phase: .queued)
        store.archive.drafts = [draft]
        var staleEdit = draft
        staleEdit.phase = .draft; staleEdit.caption = "Stale editor"
        try await store.update(staleEdit)
        XCTAssertEqual(store.archive.drafts.first, draft)

        store.activeUpload = draft.id
        draft.phase = .preparing
        try await store.updateUpload(draft)
        XCTAssertEqual(store.archive.drafts.first?.phase, .preparing)
        draft.exportedFile = "completed.mp4"; draft.phase = .uploading
        try await store.updateUpload(draft)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = DiskStore(root: root)
        try await disk.save(store.archive)
        let restored = try await disk.load()
        XCTAssertEqual(restored.drafts.first?.exportedFile, "completed.mp4")
        XCTAssertEqual(restored.drafts.first?.phase, .uploading)

        store.activeUpload = nil
        do { try await store.updateUpload(draft); XCTFail("Inactive uploader must not replace a draft") } catch { }
    }
    #endif
    func testTrimCannotProduceNegativeDuration() {
        let clip = Clip(filename: "a.mov", duration: 10, start: 9, end: 2)
        XCTAssertEqual(clip.length, 0)
        XCTAssertEqual(Clip(filename: "a.mov", duration: 10, start: -1, end: 99).length, 10)
    }
    func testDraftExportInvalidatedByEdit() {
        var draft = Draft(group: id, phase: .failed, exportedFile: "previous.mp4", error: "offline")
        draft.invalidateExport()
        XCTAssertNil(draft.exportedFile); XCTAssertEqual(draft.phase, .draft); XCTAssertNil(draft.error)
    }
    func testRotationUsesGroupDayAcrossTimeZones() {
        let start = ISO8601DateFormatter().date(from: "2026-09-30T07:00:00Z")!
        let group = VlohGroup(id: id, name: "Friends", createdAt: start, rotation: true, timeZone: "America/Los_Angeles")
        let members = [Member(id: "a", group: id, name: "A", joinedAt: start), Member(id: "b", group: id, name: "B", joinedAt: start.addingTimeInterval(1))]
        XCTAssertEqual(Rotation.member(for: group, members: members, date: start.addingTimeInterval(23 * 3600))?.id, "a")
        XCTAssertEqual(Rotation.member(for: group, members: members, date: start.addingTimeInterval(24 * 3600))?.id, "b")
        var disabled = group; disabled.rotation = false
        XCTAssertNil(Rotation.member(for: disabled, members: members, date: start))
    }
    func testCorruptArchiveIsPreservedAndSavingBlocked() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = Data("not valid json".utf8)
        try original.write(to: root.appendingPathComponent("state.json"))
        let disk = DiskStore(root: root)
        do { _ = try await disk.load(); XCTFail("Must reject corrupt state") } catch { }
        do { try await disk.save(Archive()); XCTFail("Must protect original") } catch { }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("state.json")), original)
    }
    func testArchiveRoundTripPreservesDraftClipsAndQueue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = DiskStore(root: root)
        var archive = Archive()
        archive.drafts = [Draft(group: id, clips: [Clip(filename: "clip.mov", duration: 12, end: 12)], phase: .queued)]
        try await disk.save(archive)
        let result = try await disk.load()
        XCTAssertEqual(result.drafts, archive.drafts)
        XCTAssertEqual(result.drafts.first?.totalDuration, 12)
    }
}
