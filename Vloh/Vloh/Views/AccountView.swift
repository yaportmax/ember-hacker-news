import SwiftUI
import PhotosUI
import AuthenticationServices

struct AccountView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var deleting = false
    @State private var error: String?
    @State private var photoRevision = UUID()
    var body: some View {
        Form {
            Section {
                HStack(spacing: 20) { ProfileImage(name: store.name, url: store.profilePhotoURL, size: 80).id(photoRevision); PhotosPicker(selection: $photo, matching: .images) { Text("Change profile photo") }.disabled(busy) }
                TextField("Display name", text: $name).textContentType(.nickname)
                Button(busy ? "Saving…" : "Save profile") { busy = true; Task { await store.saveName(name); busy = false } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == store.name)
            }
            Section("Sign-in") {
                if store.archive.appleUserID != nil { Label("Connected with Apple", systemImage: "checkmark.shield") }
                else {
                    SignInWithAppleButton(.signUp, onRequest: { request in request.requestedScopes = [.fullName, .email] }, onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                            let display = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) } ?? name
                            busy = true; Task { await store.connectApple(user: credential.user, displayName: display); name = store.name; busy = false }
                        case .failure(let failure): if (failure as? ASAuthorizationError)?.code != .canceled { error = failure.localizedDescription }
                        }
                    }).frame(height: 48).disabled(busy)
                }
                Text("Your Vloh profile and private groups use iCloud. Use the same iCloud account on each device. Apple manages your sign-in; Vloh has no password to store.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Your data") {
                NavigationLink("Privacy policy") { PolicyView(kind: .privacy) }
                NavigationLink("Community rules") { PolicyView(kind: .community) }
                Button("Delete Vloh account and data", role: .destructive) { deleting = true }.disabled(busy || store.activeUpload != nil)
                Text("Deletes your profile, local drafts, and your posts in joined groups. Groups you own and their contents are deleted for everyone. Copies other members exported remain on their devices. Your Apple account is unaffected.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Notice(text: error) }
        }.navigationTitle("Your account").navigationBarTitleDisplayMode(.inline)
        .onAppear { name = store.name }
        .onChange(of: photo) { _, item in
            guard let item else { return }; busy = true
            Task { do { guard let data = try await item.loadTransferable(type: Data.self) else { throw VlohError.message("Couldn't open that photo.") }; try await store.saveProfilePhoto(data); photoRevision = UUID() } catch { error = error.localizedDescription }; busy = false; photo = nil }
        }
        .confirmationDialog("Delete your Vloh account and all owned groups permanently?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete account and data", role: .destructive) { busy = true; Task { await store.deleteAccount(); busy = false; name = store.name; photoRevision = UUID() } }
        }
    }
}
