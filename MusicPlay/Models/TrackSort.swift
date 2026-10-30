import Foundation

enum TrackSortOption: String, CaseIterable, Identifiable {
    case title
    case artist
    case album
    case duration
    case dateAdded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "歌曲名"
        case .artist: return "歌手"
        case .album: return "专辑"
        case .duration: return "时长"
        case .dateAdded: return "添加时间"
        }
    }

    var supportsInitialIndex: Bool {
        switch self {
        case .title, .artist, .album: return true
        case .duration, .dateAdded: return false
        }
    }

    var preferredAscending: Bool {
        self == .dateAdded ? false : true
    }
}

struct TrackSort: Equatable {
    var option: TrackSortOption = .title
    var ascending: Bool = true

    static let `default` = TrackSort()
}

struct TrackSection: Identifiable {
    let id: String
    let tracks: [Track]
}

enum TrackSortStorage {
    static let optionKey = "librarySortOption"
    static let ascendingKey = "librarySortAscending"
}

@MainActor
enum TrackSorter {
    private static var creationDates: [String: Date] = [:]
    private static var initialCache: [Character: String] = [:]
    private static var sortKeyCache: [String: String] = [:]

    static func sorted(_ tracks: [Track], by sort: TrackSort) -> [Track] {
        if sort.option == .dateAdded {
            for track in tracks where creationDates[track.url.path] == nil {
                creationDates[track.url.path] = creationDate(of: track.url)
            }
        }

        return tracks.sorted { lhs, rhs in
            if sort.option.supportsInitialIndex {
                let lhsRank = letterRank(initialLetter(for: lhs, option: sort.option))
                let rhsRank = letterRank(initialLetter(for: rhs, option: sort.option))
                if lhsRank != rhsRank {
                    if lhsRank == 26 { return false }
                    if rhsRank == 26 { return true }
                    return sort.ascending ? lhsRank < rhsRank : lhsRank > rhsRank
                }
            }

            let order = compare(lhs, rhs, option: sort.option)
            if order == .orderedSame {
                if sort.option != .title {
                    let titleOrder = sortKey(lhs.title).localizedStandardCompare(sortKey(rhs.title))
                    if titleOrder != .orderedSame {
                        return sort.ascending ? titleOrder == .orderedAscending : titleOrder == .orderedDescending
                    }
                }
                return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
            }
            return sort.ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    static func sections(_ tracks: [Track], by sort: TrackSort) -> [TrackSection] {
        guard sort.option.supportsInitialIndex else {
            return [TrackSection(id: sort.option.rawValue, tracks: sorted(tracks, by: sort))]
        }

        let ordered = sorted(tracks, by: sort)
        var buckets: [String: [Track]] = [:]
        var letters: [String] = []

        for track in ordered {
            let letter = initialLetter(for: track, option: sort.option)
            if buckets[letter] == nil {
                letters.append(letter)
            }
            buckets[letter, default: []].append(track)
        }

        if let hashIndex = letters.firstIndex(of: "#") {
            letters.remove(at: hashIndex)
            letters.append("#")
        }

        return letters.map { letter in
            TrackSection(id: letter, tracks: buckets[letter] ?? [])
        }
    }

    private static func compare(_ lhs: Track, _ rhs: Track, option: TrackSortOption) -> ComparisonResult {
        switch option {
        case .title:
            return sortKey(lhs.title).localizedStandardCompare(sortKey(rhs.title))
        case .artist:
            return sortKey(normalizedArtist(lhs)).localizedStandardCompare(sortKey(normalizedArtist(rhs)))
        case .album:
            return sortKey(normalizedAlbum(lhs)).localizedStandardCompare(sortKey(normalizedAlbum(rhs)))
        case .duration:
            if lhs.duration == rhs.duration { return .orderedSame }
            return lhs.duration < rhs.duration ? .orderedAscending : .orderedDescending
        case .dateAdded:
            let lhsDate = creationDates[lhs.url.path] ?? creationDate(of: lhs.url)
            let rhsDate = creationDates[rhs.url.path] ?? creationDate(of: rhs.url)
            if lhsDate == rhsDate { return .orderedSame }
            return lhsDate < rhsDate ? .orderedAscending : .orderedDescending
        }
    }

    private static func normalizedArtist(_ track: Track) -> String {
        track.artist.isEmpty ? "未知艺人" : track.artist
    }

    private static func normalizedAlbum(_ track: Track) -> String {
        track.album.isEmpty ? "未知专辑" : track.album
    }

    private static func creationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }

    private static func sortKey(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let cached = sortKeyCache[trimmed] { return cached }

        let latin = trimmed
            .applyingTransform(.toLatin, reverse: false)?
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US")
            ) ?? trimmed
        sortKeyCache[trimmed] = latin
        return latin
    }

    private static func initialLetter(for track: Track, option: TrackSortOption) -> String {
        switch option {
        case .title: return initialLetter(of: track.title)
        case .artist: return track.artist.isEmpty ? "#" : initialLetter(of: track.artist)
        case .album: return track.album.isEmpty ? "#" : initialLetter(of: track.album)
        case .duration, .dateAdded: return "#"
        }
    }

    private static func letterRank(_ letter: String) -> Int {
        guard let scalar = letter.uppercased().unicodeScalars.first,
              scalar.value >= 65, scalar.value <= 90 else { return 26 }
        return Int(scalar.value - 65)
    }

    private static func initialLetter(of text: String) -> String {
        guard let character = text.first(where: { !$0.isWhitespace }) else { return "#" }
        if let cached = initialCache[character] { return cached }

        let letter: String
        if character.isASCII && character.isLetter {
            letter = String(character).uppercased()
        } else {
            let latin = String(character)
                .applyingTransform(.toLatin, reverse: false)?
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US")) ?? ""
            if let first = latin.uppercased().first, first.isASCII, first.isLetter {
                letter = String(first)
            } else {
                letter = "#"
            }
        }

        initialCache[character] = letter
        return letter
    }
}
