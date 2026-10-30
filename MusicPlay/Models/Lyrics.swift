import Foundation

struct LyricLine: Identifiable, Hashable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
}

struct Lyrics: Equatable, Sendable {
    var lines: [LyricLine]
    var plainText: String?
    var source: String

    var isTimed: Bool { !lines.isEmpty }

    var sourceLabel: String {
        switch source {
        case "KRC": return "KRC 歌词"
        case "LRC": return "LRC 歌词"
        case "内嵌": return "内嵌歌词"
        default: return source
        }
    }

    func activeIndex(at time: TimeInterval) -> Int? {
        guard isTimed else { return nil }
        let target = time + 0.05
        var low = 0
        var high = lines.count - 1
        var found: Int?

        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= target {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return found ?? 0
    }
}
