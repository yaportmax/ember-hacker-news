import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var saving = false
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Form {
            Section("You") {
                TextField("Your name", text: $name).textContentType(.givenName)
                Button(saving ? "Saving…" : "Save name") { saving = true; Task { await store.saveName(name); saving = false } }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == store.name)
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
            }
            if let group = store.group {
                Section("\(group.name) · Members") {
                    ForEach(store.archive.members.filter { $0.group == group.id }.sorted { $0.joinedAt < $1.joinedAt }) { member in HStack { Avatar(name: member.name); Text(member.name); if member.id == store.user { Text("You").foregroundStyle(.secondary) } } }
                }
            }
            Section("Connection") {
                Label(store.online ? "Connected" : "Offline", systemImage: store.online ? "wifi" : "wifi.slash")
                if let message = store.syncMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Button(store.syncing ? "Refreshing…" : "Refresh group data") { Task { await store.refresh() } }.disabled(store.syncing)
                Button("Open iPhone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section("Your privacy") {
                Text("Vloh stores your group's videos and messages in Apple's iCloud. Only people invited to your group can access them. Drafts stay on this iPhone until you post.")
                Text("Invited members can download or export videos. Sharing a group gives members permission to contribute to its shared space.")
                Text("No ads or analytics. Vloh never reads your contacts or photo library; you choose the clips to import.")
            }
            Section("Vloh") {
                LabeledContent("Version", value: "1.0.0")
                Text("Small moments. Your people.").foregroundStyle(.secondary)
                Link("Support and feedback", destination: URL(string: "https://github.com/yaportmax/ember-hacker-news/issues")!)
            }
        }.navigationTitle("Settings").onAppear { name = store.name }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}
