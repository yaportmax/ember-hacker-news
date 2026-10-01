import SwiftUI

struct ScheduleView: View {
    let group: VlohGroup
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            Section {
                Text("One person. One vlog. Each day.").font(.headline)
                Text("Post on your scheduled day or the following day. Use clips filmed from 2 AM on your day to 8 AM the next morning. Times follow \(group.timeZone).").font(.subheadline).foregroundStyle(.secondary)
            }
            Section("The next two weeks") {
                ForEach(0..<14, id: \.self) { offset in
                    let calendar = VlogCalendar.calendar(for: group)
                    let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!
                    let member = Rotation.member(for: group, members: store.archive.members, date: date)
                    HStack {
                        VStack(alignment: .leading) { Text(date.formatted(.dateTime.weekday(.wide).timeZone(calendar.timeZone))).font(.headline); Text(date.formatted(.dateTime.month(.abbreviated).day().timeZone(calendar.timeZone))).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if let member { Avatar(name: member.name); Text(member.id == store.user ? "You" : member.name).fontWeight(member.id == store.user ? .semibold : .regular) }
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle("Vlog schedule").navigationBarTitleDisplayMode(.inline)
    }
}
