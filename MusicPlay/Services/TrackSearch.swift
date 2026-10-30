import Foundation

// 搜索除了字面匹配，还支持全拼、首字母（jzl）和无空格全拼（zhoujielun）。
@MainActor
enum TrackSearch {
    private static var haystackCache: [String: String] = [:]

    static func matches(_ track: Track, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        if track.title.localizedCaseInsensitiveContains(trimmed)
            || track.artist.localizedCaseInsensitiveContains(trimmed)
            || track.album.localizedCaseInsensitiveContains(trimmed) {
            return true
        }

        let needle = normalize(trimmed)
        guard !needle.isEmpty else { return false }
        return searchableText(for: track).contains(needle)
    }

    private static func searchableText(for track: Track) -> String {
        let key = "\(track.title)\u{1}\(track.artist)\u{1}\(track.album)"
        if let cached = haystackCache[key] { return cached }

        var pieces: [String] = []
        for field in [track.title, track.artist, track.album] where !field.isEmpty {
            var folded = normalize(field)
            pieces.append(folded)

            if let latin = field.applyingTransform(.toLatin, reverse: false) {
                folded = normalize(latin)
                pieces.append(folded)
                pieces.append(folded.replacingOccurrences(of: " ", with: ""))
                let initials = folded
                    .split(whereSeparator: { $0.isWhitespace })
                    .compactMap(\.first)
                    .map(String.init)
                    .joined()
                pieces.append(initials)
            }
        }

        let haystack = pieces.joined(separator: "\n")
        haystackCache[key] = haystack
        return haystack
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US")
            )
            .lowercased()
    }
}
