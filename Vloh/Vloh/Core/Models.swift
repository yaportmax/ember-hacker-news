import Foundation

struct GroupID: Codable, Hashable, Sendable {
    var zone: String
    var owner: String
    var shared: Bool
    var key: String { "\(owner)/\(zone)" }
}
struct VlohGroup: Codable, Identifiable, Equatable, Sendable {
    var id: GroupID
    var name: String
    var createdAt: Date
    var rotation: Bool
    var timeZone: String
}
struct Member: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var group: GroupID
    var name: String
    var joinedAt: Date
}
struct Clip: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var filename: String
    var duration: Double
    var start: Double = 0
    var end: Double
    var length: Double { max(0, min(duration, end) - max(0, start)) }
}
enum UploadPhase: String, Codable, Sendable {
    case draft, queued, preparing, uploading, failed
    var title: String {
        switch self {
        case .draft: "Draft"
        case .queued: "Waiting to upload"
        case .preparing: "Preparing video"
        case .uploading: "Uploading"
        case .failed: "Upload paused"
        }
    }
}
struct Draft: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var group: GroupID
    var caption: String = ""
    var createdAt: Date = .now
    var clips: [Clip] = []
    var phase: UploadPhase = .draft
    var exportedFile: String?
    var error: String?
    var totalDuration: Double { clips.reduce(0) { $0 + $1.length } }
    var canEdit: Bool { phase == .draft || phase == .failed }
    mutating func invalidateExport() { exportedFile = nil; phase = .draft; error = nil }
}
struct Vlog: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var group: GroupID
    var authorID: String
    var authorName: String
    var caption: String
    var createdAt: Date
    var duration: Double
}
struct Reply: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var group: GroupID
    var vlogID: String?
    var authorID: String
    var authorName: String
    var text: String
    var createdAt: Date
}
struct Reaction: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var group: GroupID
    var vlogID: String
    var authorID: String
    var emoji: String
}
struct Archive: Codable, Sendable {
    var version = 1
    var accountID: String?
    var name = ""
    var groups: [VlohGroup] = []
    var members: [Member] = []
    var vlogs: [Vlog] = []
    var replies: [Reply] = []
    var reactions: [Reaction] = []
    var drafts: [Draft] = []
    var seen: Set<String> = []
}
enum VlohError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}
enum Rotation {
    static func member(for group: VlohGroup, members: [Member], date: Date) -> Member? {
        guard group.rotation else { return nil }
        let people = members.filter { $0.group == group.id }.sorted {
            $0.joinedAt == $1.joinedAt ? $0.id < $1.id : $0.joinedAt < $1.joinedAt
        }
        guard !people.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: group.timeZone) ?? TimeZone(secondsFromGMT: 0)!
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: group.createdAt), to: calendar.startOfDay(for: date)).day ?? 0
        return people[((days % people.count) + people.count) % people.count]
    }
}
enum Limits {
    static let vlogSeconds: Double = 600
    static let clips = 40
    static let videoBytes = 200 * 1_024 * 1_024
    static let cacheBytes = 500 * 1_024 * 1_024
}
