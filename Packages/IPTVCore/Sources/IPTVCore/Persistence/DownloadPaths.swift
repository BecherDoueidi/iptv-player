import Foundation

/// Downloaded media lives in `Application Support`, never `Caches` — the OS can
/// silently evict `Caches` under storage pressure, which would delete a video the
/// user explicitly chose to keep offline.
enum DownloadPaths {
    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
