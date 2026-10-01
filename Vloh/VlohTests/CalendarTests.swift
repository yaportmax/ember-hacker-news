import XCTest
#if canImport(VlohCore)
@testable import VlohCore
#else
@testable import Vloh
#endif

final class CalendarTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var group: VlohGroup { VlohGroup(id: GroupID(zone: "test", owner: "test", shared: false), name: "Friends", createdAt: date("2026-09-30T07:00:00Z"), rotation: true, timeZone: "America/Los_Angeles") }
    func testFilmWindowAndNextDayDeadline() throws {
        let day = date("2026-09-30T07:00:00Z")
        let interval = VlogCalendar.window(for: day, in: group)
        XCTAssertEqual(interval.start, date("2026-09-30T09:00:00Z"))
        XCTAssertEqual(interval.end, date("2026-10-01T15:00:00Z"))
        XCTAssertTrue(VlogCalendar.canPost(day: day, now: date("2026-10-02T06:59:59Z"), in: group))
        XCTAssertFalse(VlogCalendar.canPost(day: day, now: date("2026-10-02T07:00:00Z"), in: group))
        XCTAssertFalse(VlogCalendar.canPost(day: day, now: date("2026-09-30T06:59:59Z"), in: group))
        XCTAssertTrue(VlogCalendar.permits(Clip(filename: "x", duration: 20, end: 20, filmedAt: interval.start), day: day, in: group))
        XCTAssertFalse(VlogCalendar.permits(Clip(filename: "x", duration: 20, end: 20, filmedAt: interval.end.addingTimeInterval(-10)), day: day, in: group))
        XCTAssertFalse(VlogCalendar.permits(Clip(filename: "x", duration: 20, end: 20), day: day, in: group))
        XCTAssertTrue(VlogCalendar.permits(Clip(filename: "x", duration: 20, start: 10, end: 20, filmedAt: interval.start.addingTimeInterval(-10)), day: day, in: group))
    }
    func testDSTUsesLocalCalendarDays() {
        let day = date("2026-11-01T07:00:00Z")
        let window = VlogCalendar.window(for: day, in: group)
        XCTAssertEqual(window.start, date("2026-11-01T10:00:00Z"))
        XCTAssertEqual(window.end, date("2026-11-02T16:00:00Z"))
    }
    func testNewMemberDoesNotChangeCurrentOrder() {
        var group = group
        let today = date("2026-09-30T07:00:00Z"), tomorrow = date("2026-10-01T07:00:00Z")
        group.orders = [VlogOrder(effectiveDay: today, members: ["max"]), VlogOrder(effectiveDay: tomorrow, members: ["sam", "max"])]
        let members = [Member(id: "max", group: group.id, name: "Max", joinedAt: .distantPast), Member(id: "sam", group: group.id, name: "Sam", joinedAt: today)]
        XCTAssertEqual(Rotation.member(for: group, members: members, date: today)?.id, "max")
        XCTAssertEqual(Rotation.member(for: group, members: members, date: tomorrow)?.id, "sam")
    }
    func testDepartedMemberDoesNotReassignToday() {
        var group = group
        let today = date("2026-09-30T07:00:00Z")
        group.orders = [VlogOrder(effectiveDay: today, members: ["sam", "max"])]
        let members = [Member(id: "max", group: group.id, name: "Max", joinedAt: .distantPast)]
        XCTAssertNil(Rotation.member(for: group, members: members, date: today))
        XCTAssertEqual(Rotation.member(for: group, members: members, date: date("2026-10-01T07:00:00Z"))?.id, "max")
    }
    func testNewMemberDoesNotEnterAnExistingCycle() {
        var group = group
        let first = date("2026-09-30T07:00:00Z")
        group.orders = [VlogOrder(effectiveDay: first, members: ["max", "sam"])]
        let members = [Member(id: "max", group: group.id, name: "Max", joinedAt: .distantPast), Member(id: "sam", group: group.id, name: "Sam", joinedAt: first), Member(id: "other", group: group.id, name: "New friend", joinedAt: first.addingTimeInterval(1))]
        XCTAssertEqual(Rotation.member(for: group, members: members, date: date("2026-10-02T07:00:00Z"))?.id, "max")
    }
    func testLegacyVlogConsumesItsDayOnlyInItsGroup() {
        let day = date("2026-09-30T07:00:00Z")
        let vlog = Vlog(id: "legacy", group: group.id, authorID: "max", authorName: "Max", caption: "", createdAt: date("2026-09-30T21:00:00Z"), duration: 10)
        XCTAssertTrue(VlogCalendar.hasVlog([vlog], on: day, in: group))
        XCTAssertFalse(VlogCalendar.hasVlog([vlog], on: date("2026-10-01T07:00:00Z"), in: group))
        var other = group; other.id.zone = "other"
        XCTAssertFalse(VlogCalendar.hasVlog([vlog], on: day, in: other))
    }
    func testOnlyScheduledMemberAndOrderChangeKeepsYesterday() throws {
        var group = group
        let members = [Member(id: "max", group: group.id, name: "Max", joinedAt: .distantPast), Member(id: "sam", group: group.id, name: "Sam", joinedAt: .now)]
        let today = date("2026-09-30T07:00:00Z"), tomorrow = date("2026-10-01T07:00:00Z")
        group.orders = [VlogOrder(effectiveDay: tomorrow, members: ["sam", "max"])]
        XCTAssertEqual(Rotation.member(for: group, members: members, date: today)?.id, "max")
        XCTAssertEqual(Rotation.member(for: group, members: members, date: tomorrow)?.id, "sam")
        let clip = Clip(filename: "x", duration: 20, end: 20, filmedAt: date("2026-09-30T15:00:00Z"))
        let draft = Draft(group: group.id, clips: [clip], vlogDay: today)
        XCTAssertNoThrow(try VlogCalendar.validate(draft, group: group, members: members, user: "max", now: date("2026-10-01T18:00:00Z")))
        XCTAssertThrowsError(try VlogCalendar.validate(draft, group: group, members: members, user: "sam", now: date("2026-10-01T18:00:00Z")))
    }
}
