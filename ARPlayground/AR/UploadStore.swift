import Foundation

/// A user-uploaded 3D model file, persisted in the app's Documents directory so
/// it survives relaunches and shows up in the Upload palette.
struct UploadedModel: Identifiable, Hashable {
    let id: UUID
    let name: String   // original file name, shown in the UI
    let url: URL       // stable on-disk location inside the app sandbox
}

/// Persists imported model files into `Documents/Uploads` and lists them back.
///
/// Files are stored as `<uuid>__<originalName>` so each upload has a stable id
/// across launches (the id is parsed back out of the file name), which lets us
/// cache loaded templates per upload and clone them on placement.
enum UploadStore {

    private static let folderName = "Uploads"
    private static let separator = "__"

    /// Extensions RealityKit's `Entity(contentsOf:)` can actually load.
    private static let loadableExtensions: Set<String> = ["usdz", "usd", "usdc", "usda", "reality"]

    /// Whether a picked file is in a format RealityKit can load directly.
    static func canLoad(_ url: URL) -> Bool {
        loadableExtensions.contains(url.pathExtension.lowercased())
    }

    static func directory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// All previously uploaded models, newest first.
    static func list() -> [UploadedModel] {
        guard let dir = try? directory(),
              let items = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { return [] }

        return items
            .filter { loadableExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { modified($0) > modified($1) }
            .map { model(for: $0) }
    }

    /// Copy a picked file into the store. Must be called while the picker's
    /// security-scoped URL is still valid (we scope it here, synchronously).
    static func add(from pickedURL: URL) throws -> UploadedModel {
        let dir = try directory()
        let needsStop = pickedURL.startAccessingSecurityScopedResource()
        defer { if needsStop { pickedURL.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let safeName = pickedURL.lastPathComponent
        let dest = dir.appendingPathComponent("\(id.uuidString)\(separator)\(safeName)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: pickedURL, to: dest)
        return UploadedModel(id: id, name: safeName, url: dest)
    }

    static func remove(_ upload: UploadedModel) {
        try? FileManager.default.removeItem(at: upload.url)
    }

    // MARK: Helpers

    private static func model(for url: URL) -> UploadedModel {
        let file = url.lastPathComponent
        let parts = file.components(separatedBy: separator)
        if parts.count >= 2, let id = UUID(uuidString: parts[0]) {
            let name = parts.dropFirst().joined(separator: separator)
            return UploadedModel(id: id, name: name, url: url)
        }
        // A file we didn't name (shouldn't normally happen) — synthesize an id.
        return UploadedModel(id: UUID(), name: file, url: url)
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}
