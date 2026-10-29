import Foundation

struct Track: Identifiable, Hashable, Codable {
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval

    var id: String { url.path }

    init(url: URL, title: String? = nil, artist: String = "", album: String = "", duration: TimeInterval = 0) {
        self.url = url
        let fallback = url.deletingPathExtension().lastPathComponent
        self.title = title.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf", "flac",
    ]

    func isInside(folder: URL) -> Bool {
        let base = folder.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == base { return true }
        return path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}
