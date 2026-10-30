import Foundation

// 收藏与最近播放都存在稳定的 Track.stableID 上，覆盖安装后仍能对上文件。
@MainActor
final class LibraryActivityStore: ObservableObject {
    static let shared = LibraryActivityStore()

    struct RecentEntry: Identifiable, Codable, Equatable {
        let id: String
        var playedAt: Date
    }

    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var recentEntries: [RecentEntry] = []

    private struct StoredState: Codable {
        var favoriteIDs: Set<String> = []
        var recentEntries: [RecentEntry] = []
    }

    private let fileURL: URL
    private static let maxRecentCount = 100

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicPlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("activity.json")

        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(StoredState.self, from: data) else { return }
        favoriteIDs = state.favoriteIDs
        recentEntries = state.recentEntries
    }

    var recentTrackIDs: [String] {
        recentEntries.map(\.id)
    }

    func isFavorite(_ track: Track) -> Bool {
        favoriteIDs.contains(track.stableID)
    }

    func toggleFavorite(_ track: Track) {
        let id = track.stableID
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        persist()
    }

    func recordPlay(_ track: Track) {
        let id = track.stableID
        recentEntries.removeAll { $0.id == id }
        recentEntries.insert(RecentEntry(id: id, playedAt: Date()), at: 0)
        if recentEntries.count > Self.maxRecentCount {
            recentEntries.removeLast(recentEntries.count - Self.maxRecentCount)
        }
        persist()
    }

    private func persist() {
        let state = StoredState(favoriteIDs: favoriteIDs, recentEntries: recentEntries)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
