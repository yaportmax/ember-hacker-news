import Foundation

enum VlogCalendar {
    static func calendar(for group: VlohGroup) -> Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: group.timeZone) ?? TimeZone(secondsFromGMT: 0)!; return calendar }
    static func day(_ date: Date, in group: VlohGroup) -> Date { calendar(for: group).startOfDay(for: date) }
    static func key(_ date: Date, in group: VlohGroup) -> String {
        let parts = calendar(for: group).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func window(for date: Date, in group: VlohGroup) -> DateInterval {
        let calendar = calendar(for: group), start = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: calendar.date(bySettingHour: 2, minute: 0, second: 0, of: start)!, end: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: next)!)
    }
    static func canPost(day date: Date, now: Date, in group: VlohGroup) -> Bool {
        let calendar = calendar(for: group), first = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 2, to: first)!
        return now >= first && now < end
    }
    static func permits(_ clip: Clip, day: Date, in group: VlohGroup) -> Bool {
        guard let filmed = clip.filmedAt else { return false }
        let window = window(for: day, in: group)
        let start = filmed.addingTimeInterval(clip.start), end = filmed.addingTimeInterval(clip.end)
        return start >= window.start && start < window.end && end <= window.end && clip.length > 0
    }
    static func availableDays(for user: String, group: VlohGroup, members: [Member], now: Date) -> [Date] {
        let calendar = calendar(for: group), today = calendar.startOfDay(for: now)
        return [today, calendar.date(byAdding: .day, value: -1, to: today)!].filter { $0 >= calendar.startOfDay(for: group.createdAt) && Rotation.member(for: group, members: members, date: $0)?.id == user }
    }
    static func validate(_ draft: Draft, group: VlohGroup, members: [Member], user: String, now: Date) throws {
        guard let date = draft.vlogDay else { throw VlohError.message("Choose the scheduled day for this vlog.") }
        guard canPost(day: date, now: now, in: group) else { throw VlohError.message("Post your vlog on its scheduled day or the following day.") }
        guard Rotation.member(for: group, members: members, date: date)?.id == user else { throw VlohError.message("Only the person scheduled for this day can post its vlog.") }
        guard !draft.clips.isEmpty, draft.clips.allSatisfy({ permits($0, day: date, in: group) }) else { throw VlohError.message("Use clips filmed from 2 AM on your vlog day through 8 AM the next day. Clips without an original filming date can't be used.") }
    }
}
