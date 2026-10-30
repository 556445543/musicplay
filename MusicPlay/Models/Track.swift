import Foundation

struct Track: Identifiable, Hashable, Codable {
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval

    var id: String { url.path }

    // iOS 覆盖安装会更换 App 数据容器 UUID，收藏/最近播放/歌词偏移必须存相对 Documents 的路径。
    var stableID: String {
        guard let range = url.path.range(of: "/Documents/") else { return url.path }
        return String(url.path[range.upperBound...])
    }

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
