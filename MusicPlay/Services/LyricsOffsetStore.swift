import Foundation

// 老歌歌词时间轴常有偏差，按歌曲记录 ±0.5s 的手动偏移。
@MainActor
final class LyricsOffsetStore: ObservableObject {
    static let shared = LyricsOffsetStore()

    @Published private(set) var offsets: [String: Double] = [:]

    private static let storageKey = "lyricsOffsets"
    private static let limit = 10.0

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return }
        offsets = decoded
    }

    func offset(for track: Track?) -> Double {
        guard let track else { return 0 }
        return offsets[track.stableID] ?? 0
    }

    func adjust(for track: Track?, by delta: Double) {
        guard let track else { return }
        let current = offsets[track.stableID] ?? 0
        let updated = ((current + delta) * 10).rounded() / 10
        setOffset(min(max(updated, -Self.limit), Self.limit), for: track)
    }

    func reset(for track: Track?) {
        guard let track else { return }
        setOffset(0, for: track)
    }

    private func setOffset(_ value: Double, for track: Track) {
        if value == 0 {
            offsets[track.stableID] = nil
        } else {
            offsets[track.stableID] = value
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(offsets) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

func lyricsOffsetLabel(_ offset: Double) -> String {
    if abs(offset) < 0.05 { return "±0s" }
    let sign = offset > 0 ? "+" : "−"
    return String(format: "%@%.1fs", sign, abs(offset))
}
