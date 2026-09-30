import Foundation

actor DiskStore {
    let root: URL
    private var writable = true
    init(root: URL) { self.root = root }
    func load() throws -> Archive {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return Archive() }
        do {
            let result = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
            guard result.version == 1 else { throw VlohError.message("This archive needs a newer version of Vloh.") }
            return result
        } catch {
            writable = false
            throw VlohError.message("Vloh couldn't read its saved data. Your original data is preserved. Please contact support before reinstalling.")
        }
    }
    func save(_ archive: Archive) throws {
        guard writable else { throw VlohError.message("Saving is paused to protect your original data.") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: root.appendingPathComponent("state.json"), options: .atomic)
    }
}
