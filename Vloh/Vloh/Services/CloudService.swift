import CloudKit
import Foundation

struct CloudSnapshot: Sendable {
    var groups: [VlohGroup] = []
    var members: [Member] = []
    var vlogs: [Vlog] = []
    var replies: [Reply] = []
    var reactions: [Reaction] = []
}
// CK objects stay on this actor. Callbacks only mutate a locked accumulator.
actor CloudService {
    lazy var container = CKContainer(identifier: "iCloud.com.maxyaport.vloh")
    func identity() async throws -> String {
        guard try await container.accountStatus() == .available else {
            throw VlohError.message("Sign in to iCloud in iPhone Settings to share with your friends.")
        }
        return try await container.userRecordID().recordName
    }
    private func database(_ id: GroupID) -> CKDatabase { id.shared ? container.sharedCloudDatabase : container.privateCloudDatabase }
    private func zoneID(_ id: GroupID) -> CKRecordZone.ID { CKRecordZone.ID(zoneName: id.zone, ownerName: id.owner) }
    private func recordID(_ name: String, _ group: GroupID) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zoneID(group)) }
    func createGroup(name: String, rotation: Bool) async throws -> VlohGroup {
        let zone = CKRecordZone(zoneName: "vloh-" + UUID().uuidString)
        _ = try await container.privateCloudDatabase.save(zone)
        let id = GroupID(zone: zone.zoneID.zoneName, owner: zone.zoneID.ownerName, shared: false)
        let group = VlohGroup(id: id, name: name, createdAt: .now, rotation: rotation, timeZone: TimeZone.current.identifier)
        let record = CKRecord(recordType: "VlohGroup", recordID: recordID("group", id))
        record["name"] = name as CKRecordValue
        record["createdAt"] = group.createdAt as CKRecordValue
        record["rotation"] = (rotation ? 1 : 0) as CKRecordValue
        record["timeZone"] = group.timeZone as CKRecordValue
        _ = try await database(id).save(record)
        return group
    }
    func join(group: GroupID, user: String, name: String, photo: URL? = nil) async throws {
        let id = recordID("member-" + user, group)
        let record: CKRecord
        do { record = try await database(group).record(for: id) }
        catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "VlohMember", recordID: id) }
        record["user"] = user as CKRecordValue
        record["name"] = name as CKRecordValue
        if let photo { record["photo"] = CKAsset(fileURL: photo) }
        if record["joinedAt"] == nil { record["joinedAt"] = Date.now as CKRecordValue }
        _ = try await database(group).save(record)
    }
    func post(_ draft: Draft, author: String, name: String, video: URL, poster: URL) async throws -> Vlog {
        let records = try await records(in: zoneID(draft.group), database: database(draft.group))
        guard let groupRecord = records.first(where: { $0.recordType == "VlohGroup" }) else { throw VlohError.message("This group is unavailable.") }
        let group = decodeGroup(groupRecord, draft.group)
        let members = records.filter { $0.recordType == "VlohMember" }.map { Member(id: $0["user"] as? String ?? "", group: draft.group, name: $0["name"] as? String ?? "Friend", joinedAt: $0["joinedAt"] as? Date ?? .distantPast) }
        try VlogCalendar.validate(draft, group: group, members: members, user: author, now: .now)
        let id = recordID("day-" + VlogCalendar.key(draft.vlogDay!, in: group), draft.group)
        // One atomic record ID per group/day also makes retries idempotent.
        do {
            let existing = try await database(draft.group).record(for: id)
            guard existing["author"] as? String == author, existing["draftID"] as? String == draft.id.uuidString else { throw VlohError.message("This day already has its vlog.") }
            return vlog(existing, draft.group)
        } catch let error as CKError where error.code == .unknownItem { }
        let record = CKRecord(recordType: "VlohVlog", recordID: id)
        record["author"] = author as CKRecordValue; record["authorName"] = name as CKRecordValue
        record["caption"] = draft.caption as CKRecordValue; record["createdAt"] = Date.now as CKRecordValue
        record["vlogDay"] = draft.vlogDay! as CKRecordValue
        record["draftID"] = draft.id.uuidString as CKRecordValue
        record["duration"] = draft.totalDuration as CKRecordValue
        record["video"] = CKAsset(fileURL: video); record["poster"] = CKAsset(fileURL: poster)
        do { return vlog(try await database(draft.group).save(record), draft.group) }
        catch let error as CKError where error.code == .serverRecordChanged {
            guard let server = error.serverRecord else { throw error }
            guard server["draftID"] as? String == draft.id.uuidString else { throw VlohError.message("This day already has its vlog.") }
            return vlog(server, draft.group)
        }
    }
    func reply(group: GroupID, vlogID: String?, author: String, name: String, text: String) async throws {
        let record = CKRecord(recordType: "VlohReply", recordID: recordID(UUID().uuidString, group))
        record["vlog"] = vlogID as CKRecordValue?; record["author"] = author as CKRecordValue
        record["authorName"] = name as CKRecordValue; record["text"] = text as CKRecordValue
        record["createdAt"] = Date.now as CKRecordValue
        _ = try await database(group).save(record)
    }
    func react(vlog: Vlog, author: String, emoji: String) async throws {
        let id = recordID("reaction-\(vlog.id)-\(author)", vlog.group)
        let record: CKRecord
        do { record = try await database(vlog.group).record(for: id) }
        catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "VlohReaction", recordID: id) }
        record["vlog"] = vlog.id as CKRecordValue; record["author"] = author as CKRecordValue
        record["emoji"] = emoji as CKRecordValue
        _ = try await database(vlog.group).save(record)
    }
    func delete(_ vlog: Vlog) async throws { _ = try await database(vlog.group).deleteRecord(withID: recordID(vlog.id, vlog.group)) }
    func asset(_ vlog: Vlog, key: String, destination: URL) async throws -> URL {
        let record = try await database(vlog.group).records(for: [recordID(vlog.id, vlog.group)], desiredKeys: [key])
        guard let result = record[recordID(vlog.id, vlog.group)], let asset = try result.get()[key] as? CKAsset, let url = asset.fileURL else {
            throw VlohError.message("This video isn't available. Pull to refresh and try again.")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: url, to: destination) }
        return destination
    }
    func share(_ group: VlohGroup) async throws -> CKShare {
        let zone = try await container.privateCloudDatabase.recordZone(for: zoneID(group.id))
        if let share = zone.share { return try await container.privateCloudDatabase.record(for: share.recordID) as! CKShare }
        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
        share.publicPermission = .none
        return try await container.privateCloudDatabase.save(share) as! CKShare
    }
    func accept(_ metadata: CKShare.Metadata) async throws { _ = try await container.accept(metadata) }
    func snapshot() async throws -> CloudSnapshot {
        var snapshot = CloudSnapshot()
        for (db, shared) in [(container.privateCloudDatabase, false), (container.sharedCloudDatabase, true)] {
            let zones = try await db.allRecordZones().filter { $0.zoneID.zoneName.hasPrefix("vloh-") }
            for zone in zones {
                let group = GroupID(zone: zone.zoneID.zoneName, owner: zone.zoneID.ownerName, shared: shared)
                for record in try await records(in: zone.zoneID, database: db) {
                    switch record.recordType {
                    case "VlohGroup":
                        snapshot.groups.append(decodeGroup(record, group))
                    case "VlohMember":
                        snapshot.members.append(Member(id: record["user"] as? String ?? record.recordID.recordName, group: group, name: record["name"] as? String ?? "Friend", joinedAt: record["joinedAt"] as? Date ?? .distantPast))
                    case "VlohVlog": snapshot.vlogs.append(vlog(record, group))
                    case "VlohReply":
                        snapshot.replies.append(Reply(id: record.recordID.recordName, group: group, vlogID: record["vlog"] as? String, authorID: record["author"] as? String ?? "", authorName: record["authorName"] as? String ?? "Friend", text: record["text"] as? String ?? "", createdAt: record["createdAt"] as? Date ?? .distantPast))
                    case "VlohReaction":
                        snapshot.reactions.append(Reaction(id: record.recordID.recordName, group: group, vlogID: record["vlog"] as? String ?? "", authorID: record["author"] as? String ?? "", emoji: record["emoji"] as? String ?? "❤️"))
                    default: break
                    }
                }
            }
        }
        return snapshot
    }
    private func decodeGroup(_ record: CKRecord, _ id: GroupID) -> VlohGroup {
        let orders = (record["schedule"] as? Data).flatMap { try? JSONDecoder().decode([VlogOrder].self, from: $0) }
        return VlohGroup(id: id, name: record["name"] as? String ?? "Friends", createdAt: record["createdAt"] as? Date ?? .distantPast, rotation: true, timeZone: record["timeZone"] as? String ?? "UTC", orders: orders)
    }
    func updateGroup(_ group: VlohGroup, name: String?, order: [String]?, photo: URL?) async throws {
        guard !group.id.shared else { throw VlohError.message("Only the group owner can change group settings.") }
        let record = try await database(group.id).record(for: recordID("group", group.id))
        if let name { record["name"] = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)) as CKRecordValue }
        if let photo { record["photo"] = CKAsset(fileURL: photo) }
        if let order {
            var orders = (record["schedule"] as? Data).flatMap { try? JSONDecoder().decode([VlogOrder].self, from: $0) } ?? []
            let calendar = VlogCalendar.calendar(for: group)
            let effective = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
            orders.removeAll { $0.effectiveDay >= effective }; orders.append(VlogOrder(effectiveDay: effective, members: order))
            record["schedule"] = try JSONEncoder().encode(orders) as CKRecordValue
        }
        _ = try await database(group.id).save(record)
    }
    func groupPhoto(_ group: GroupID, destination: URL) async throws -> URL { try await photo(record: recordID("group", group), database: database(group), destination: destination) }
    func memberPhoto(_ user: String, group: GroupID, destination: URL) async throws -> URL { try await photo(record: recordID("member-" + user, group), database: database(group), destination: destination) }
    private func photo(record id: CKRecord.ID, database: CKDatabase, destination: URL) async throws -> URL {
        let records = try await database.records(for: [id], desiredKeys: ["photo"])
        guard let result = records[id], let asset = try result.get()["photo"] as? CKAsset, let file = asset.fileURL else { throw VlohError.message("No photo set.") }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Data(contentsOf: file); try data.write(to: destination, options: .atomic)
        return destination
    }
    func saveProfile(name: String, appleUser: String?, photo: URL?) async throws {
        let id = CKRecord.ID(recordName: "vloh-profile")
        let record: CKRecord
        do { record = try await container.privateCloudDatabase.record(for: id) } catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "VlohProfile", recordID: id) }
        record["name"] = name as CKRecordValue
        if let appleUser { record["appleUser"] = appleUser as CKRecordValue }
        if let photo { record["photo"] = CKAsset(fileURL: photo) }
        _ = try await container.privateCloudDatabase.save(record)
    }
    func profile(destination: URL) async throws -> (String, String?, Bool) {
        let record = try await container.privateCloudDatabase.record(for: CKRecord.ID(recordName: "vloh-profile"))
        var hasPhoto = false
        if let asset = record["photo"] as? CKAsset, let file = asset.fileURL { try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(contentsOf: file).write(to: destination, options: .atomic); hasPhoto = true }
        return (record["name"] as? String ?? "", record["appleUser"] as? String, hasPhoto)
    }
    func leave(_ group: GroupID) async throws { _ = try await database(group).deleteRecordZone(withID: zoneID(group)) }
    func deleteAccount(user: String) async throws {
        // Fresh zone metadata ensures deletion covers every current membership.
        for (database, shared) in [(container.privateCloudDatabase, false), (container.sharedCloudDatabase, true)] {
            for zone in try await database.allRecordZones().filter({ $0.zoneID.zoneName.hasPrefix("vloh-") }) {
                if shared {
                    let records = try await records(in: zone.zoneID, database: database)
                    for record in records where record["author"] as? String == user || record["user"] as? String == user { _ = try await database.deleteRecord(withID: record.recordID) }
                }
                _ = try await database.deleteRecordZone(withID: zone.zoneID)
            }
        }
        do { _ = try await container.privateCloudDatabase.deleteRecord(withID: CKRecord.ID(recordName: "vloh-profile")) } catch let error as CKError where error.code == .unknownItem { }
    }
    private func vlog(_ record: CKRecord, _ group: GroupID) -> Vlog {
        Vlog(id: record.recordID.recordName, group: group, authorID: record["author"] as? String ?? "", authorName: record["authorName"] as? String ?? "Friend", caption: record["caption"] as? String ?? "", createdAt: record["createdAt"] as? Date ?? .distantPast, duration: record["duration"] as? Double ?? 0, vlogDay: record["vlogDay"] as? Date)
    }
    private func records(in zone: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        let collector = RecordCollector()
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.desiredKeys = ["name", "createdAt", "rotation", "timeZone", "user", "joinedAt", "author", "authorName", "caption", "duration", "vlog", "text", "emoji", "vlogDay", "draftID", "schedule"]
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zone], configurationsByRecordZoneID: [zone: config])
        operation.fetchAllChanges = true
        return try await withCheckedThrowingContinuation { continuation in
            operation.recordWasChangedBlock = { _, result in collector.add(result) }
            operation.recordZoneFetchResultBlock = { _, result in if case .failure(let error) = result { collector.fail(error) } }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success: continuation.resume(with: collector.result())
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }
}
private final class RecordCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [CKRecord] = []
    private var error: Error?
    func add(_ result: Result<CKRecord, Error>) {
        lock.lock(); defer { lock.unlock() }
        switch result { case .success(let record): records.append(record); case .failure(let value): error = value }
    }
    func fail(_ value: Error) { lock.lock(); defer { lock.unlock() }; error = value }
    func result() -> Result<[CKRecord], Error> { lock.lock(); defer { lock.unlock() }; return error.map { .failure($0) } ?? .success(records) }
}

