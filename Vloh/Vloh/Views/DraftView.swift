import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

struct DraftsView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: DraftPresentation?
    @State private var deleting: Draft?
    var body: some View {
        List {
            if store.archive.drafts.isEmpty { ContentUnavailableView("A day in the making", systemImage: "square.and.pencil", description: Text("Start recording from Today. Your clips stay here until you're ready to share.")) }
            ForEach(store.archive.drafts.sorted { $0.createdAt > $1.createdAt }) { draft in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        editing = DraftPresentation(id: draft.id, draft: draft)
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: "video.badge.ellipsis").font(.title2).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.caption.isEmpty ? "Your day" : draft.caption).font(.headline)
                                Text("\(draft.clips.count) clips · \(Duration.seconds(draft.totalDuration).formatted(.time(pattern: .minuteSecond)))").font(.subheadline).foregroundStyle(.secondary)
                                Text(store.archive.groups.first { $0.id == draft.group }?.name ?? "Group unavailable").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain).disabled(!draft.canEdit)
                    if draft.phase != .draft { UploadRow(draft: draft) }
                }
                .swipeActions { if draft.canEdit { Button("Delete", role: .destructive) { deleting = draft } } }
            }
        }
        .navigationTitle("Drafts")
        .sheet(item: $editing) { DraftView(initial: $0.draft) }
        .confirmationDialog("Delete this draft and its clips?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete draft", role: .destructive) { if let deleting { Task { await store.removeDraft(deleting) } }; deleting = nil }
        }
    }
}
struct DraftView: View {
    let initial: Draft
    @State private var draft: Draft
    @State private var selection: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var importing = false
    @State private var saving = false
    @State private var error: String?
    @State private var preview: URL?
    @State private var trimming: Clip?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    init(initial: Draft) { self.initial = initial; _draft = State(initialValue: initial) }
    private var busy: Bool { importing || saving }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("A caption for your day", text: $draft.caption, axis: .vertical).lineLimit(2...4)
                        .onChange(of: draft.caption) { _, value in if value.count > 500 { draft.caption = String(value.prefix(500)) } }
                    Label("\(draft.clips.count) clips · \(Duration.seconds(draft.totalDuration).formatted(.time(pattern: .minuteSecond)))", systemImage: "film.stack").font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Button { Task { await openCamera() } } label: { Label("Record", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.borderedProminent)
                        PhotosPicker(selection: $selection, maxSelectionCount: max(1, Limits.clips - draft.clips.count), matching: .videos) {
                            Label("Import", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.bordered)
                    }.disabled(busy || draft.clips.count >= Limits.clips)
                    if importing { ProgressView("Saving clips to your draft…") }
                } footer: { Text("Add moments throughout your day. Up to 10 minutes total. Your draft saves on this iPhone.") }
                if !draft.clips.isEmpty {
                    Section("Your clips") {
                        ForEach(Array(draft.clips.enumerated()), id: \.element.id) { index, clip in
                            HStack {
                                Button { Task { preview = await store.media.clipURL(clip) } } label: {
                                    Label("Clip \(index + 1)", systemImage: "play.circle").frame(minHeight: 44)
                                }.buttonStyle(.borderless)
                                Spacer()
                                Text(Duration.seconds(clip.length).formatted(.time(pattern: .minuteSecond))).font(.caption.monospacedDigit())
                                Button { trimming = clip } label: { Image(systemName: "scissors").frame(minWidth: 44, minHeight: 44) }.buttonStyle(.borderless).accessibilityLabel("Trim clip \(index + 1)")
                            }
                        }
                        .onMove { draft.clips.move(fromOffsets: $0, toOffset: $1); draft.invalidateExport() }
                        .onDelete { draft.clips.remove(atOffsets: $0); draft.invalidateExport() }
                    }
                } else {
                    ContentUnavailableView("What's your day looking like?", systemImage: "camera", description: Text("Record a moment or add a clip from Photos."))
                }
                if let error { Notice(text: error) }
                Section {
                    Button {
                        saving = true
                        Task {
                            do { try await store.update(draft); await store.publish(draft.id); if store.error == nil { dismiss() } }
                            catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    } label: { Label(saving ? "Saving…" : "Share with your group", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderedProminent).disabled(busy || draft.clips.isEmpty || draft.totalDuration > Limits.vlogSeconds)
                    .accessibilityIdentifier("share-vlog")
                }
            }.disabled(saving)
            .navigationTitle("Your day").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { Task { do { try await store.update(draft); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(busy) }
                ToolbarItem(placement: .primaryAction) { EditButton().disabled(busy) }
            }
            .interactiveDismissDisabled(busy)
            .onChange(of: draft) { _, value in Task { do { try await store.update(value) } catch { self.error = error.localizedDescription } } }
            .onChange(of: selection) { _, items in Task { await importMovies(items) } }
            .fullScreenCover(isPresented: $camera) { CameraView { url in Task { await addClip(url) } }.ignoresSafeArea() }
            .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                if let preview { NavigationStack { FilePlayer(url: preview).navigationTitle("Clip preview").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.preview = nil } } } } }
            }
            .sheet(item: $trimming) { clip in TrimView(clip: clip) { value in
                if let index = draft.clips.firstIndex(where: { $0.id == value.id }) { draft.clips[index] = value; draft.invalidateExport() }
            } }
        }
    }
    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error = "The camera is available on a physical iPhone. You can import videos here."; return }
        let video = await AVCaptureDevice.requestAccess(for: .video)
        let audio = await AVCaptureDevice.requestAccess(for: .audio)
        guard video && audio else { error = "Allow Camera and Microphone for Vloh in iPhone Settings to record. You can still import videos."; return }
        camera = true
    }
    private func importMovies(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, !importing else { return }
        importing = true; defer { importing = false; selection = [] }
        for item in items {
            do {
                guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else { throw VlohError.message("Couldn't open this clip. Try a different video.") }
                defer { try? FileManager.default.removeItem(at: movie.url) }
                try await append(movie.url)
            } catch { self.error = error.localizedDescription }
        }
    }
    private func addClip(_ url: URL) async {
        importing = true; defer { importing = false }
        do { try await append(url) } catch { self.error = error.localizedDescription }
    }
    private func append(_ url: URL) async throws {
        guard draft.clips.count < Limits.clips else { throw VlohError.message("This draft already has 40 clips.") }
        let clip = try await store.media.importClip(from: url)
        draft.clips.append(clip); draft.invalidateExport()
        try await store.update(draft)
        if draft.totalDuration > Limits.vlogSeconds { error = "Your vlog is over 10 minutes. Trim or remove a clip before sharing." }
    }
}
struct TrimView: View {
    @State var clip: Clip
    let onSave: (Clip) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let url { FilePlayer(url: url) }
                VStack(alignment: .leading) {
                    Text("Start: \(clip.start, specifier: "%.1f") seconds")
                    Slider(value: $clip.start, in: 0...max(0, clip.end - 0.1), step: 0.1).accessibilityLabel("Clip start")
                    Text("End: \(clip.end, specifier: "%.1f") seconds")
                    Slider(value: $clip.end, in: min(clip.duration, clip.start + 0.1)...clip.duration, step: 0.1).accessibilityLabel("Clip end")
                }.padding()
                Spacer()
            }.navigationTitle("Trim clip").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(clip); dismiss() }.disabled(clip.length <= 0) }
                }.task { url = await store.media.clipURL(clip) }
        }
    }
}
