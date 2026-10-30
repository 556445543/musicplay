import CryptoKit
import Foundation

extension Notification.Name {
    static let artworkUpdated = Notification.Name("MusicPlay.artworkUpdated")
}

// 老 MP3 大多没有内嵌封面，缺失时按 艺人+专辑 去 iTunes 搜索一次并缓存到本地。
@MainActor
final class OnlineArtworkStore {
    static let shared = OnlineArtworkStore()

    private struct Index: Codable {
        var tracks: [String: String] = [:]
        var misses: Set<String> = []
    }

    private struct ITunesResult: Decodable {
        let trackName: String?
        let collectionName: String?
        let artistName: String?
        let artworkUrl100: String?
    }

    private struct ITunesResponse: Decodable {
        let resultCount: Int
        let results: [ITunesResult]
    }

    private enum SearchOutcome {
        case results([ITunesResult])
        case empty
        case failed
    }

    private enum LookupOutcome {
        case found(URL)
        case notFound
        case unavailable
    }

    private let directory: URL
    private let indexURL: URL
    private var index = Index()
    private var isRunning = false

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicPlay", isDirectory: true)
        directory = support.appendingPathComponent("Artwork", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode(Index.self, from: data) {
            index = decoded
            let migrated = Dictionary(
                decoded.tracks.map { (Self.stableKey($0.key), $0.value) },
                uniquingKeysWith: { existing, _ in existing }
            )
            if migrated != decoded.tracks {
                index.tracks = migrated
                persist()
            }
        }
    }

    // 覆盖安装会换掉 iOS 的 App 数据目录 UUID，绝对路径存进索引后重装即全部失效。
    private static func stableKey(_ path: String) -> String {
        guard let range = path.range(of: "/Documents/") else { return path }
        return String(path[range.upperBound...])
    }

    func diskData(for trackPath: String) async -> Data? {
        guard let name = index.tracks[Self.stableKey(trackPath)] else { return nil }
        let fileURL = directory.appendingPathComponent(name)
        return await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: fileURL)
        }.value
    }

    func start(tracks: [Track]) {
        guard !tracks.isEmpty, !isRunning else { return }
        isRunning = true
        Task {
            await enrich(tracks: tracks)
            isRunning = false
        }
    }

    func enrich(tracks: [Track]) async {
        var groups: [String: [Track]] = [:]
        var order: [String] = []
        for track in tracks {
            let key = Self.albumKey(for: track)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(track)
        }

        for key in order {
            guard !Task.isCancelled else { return }
            guard let group = groups[key], let lead = group.first else { continue }
            if group.contains(where: { index.tracks[Self.stableKey($0.url.path)] != nil }) { continue }
            if index.misses.contains(key) { continue }

            switch await lookup(for: lead) {
            case .found(let artworkURL):
                if let data = await download(artworkURL), PlatformImage(data: data) != nil {
                    store(data, key: key, tracks: group)
                } else {
                    index.misses.insert(key)
                    persist()
                }
            case .notFound:
                index.misses.insert(key)
                persist()
            case .unavailable:
                return
            }

            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    // MARK: - Matching

    private static func albumKey(for track: Track) -> String {
        let base = track.album.isEmpty
            ? "\(track.artist)|\(track.title)"
            : "\(track.artist)|\(track.album)"
        return normalized(base)
    }

    private func lookup(for track: Track) async -> LookupOutcome {
        let entities = track.album.isEmpty ? ["song"] : ["album", "song"]
        var networkFailed = false

        for entity in entities {
            for term in Self.searchTerms(for: track, entity: entity) {
                let countries = Self.containsCJK(term) ? ["tw", "us"] : ["us", "tw"]

                for country in countries {
                    switch await search(term: term, entity: entity, country: country) {
                    case .failed:
                        networkFailed = true
                    case .empty:
                        continue
                    case .results(let results):
                        if let artwork = bestMatch(in: results, for: track) {
                            return .found(artwork)
                        }
                    }
                }
            }
        }

        return networkFailed ? .unavailable : .notFound
    }

    private static func searchTerms(for track: Track, entity: String) -> [String] {
        let parts = entity == "album"
            ? [track.artist, track.album]
            : [track.artist, track.title]
        let term = parts
            .map { sanitized($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !term.isEmpty else { return [] }

        var terms = [term]
        if let latin = latinOnly(term), latin != term {
            terms.append(latin)
        }
        return terms
    }

    // 老文件的标签常混着网址、音轨号和中文译名，直接拼进搜索词会让 iTunes 一条都搜不到。
    private static func sanitized(_ text: String) -> String {
        var value = text
        let domain = "(?i)(https?://)?(www\\.)?[a-z0-9-]+\\.(com|net|org|cn|cc|tv)(/\\S*)?"
        if let regex = try? NSRegularExpression(pattern: domain) {
            value = regex.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: " "
            )
        }
        if let regex = try? NSRegularExpression(pattern: "^\\s*\\d{1,3}\\s*[.\\-_、]?\\s*") {
            value = regex.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: ""
            )
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " -_·.、,，"))
    }

    private static func latinOnly(_ text: String) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                    scalars.append(scalar)
                }
            } else if (0x00C0...0x024F).contains(scalar.value) {
                scalars.append(scalar)
            }
        }
        let value = String(scalars)
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard value.count >= 3, value.contains(where: { $0.isLetter }) else { return nil }
        return value
    }

    private func bestMatch(in results: [ITunesResult], for track: Track) -> URL? {
        var best: (score: Double, url: URL)?

        for result in results {
            guard let artworkText = result.artworkUrl100,
                  let artworkURL = Self.largeArtworkURL(artworkText) else { continue }

            let artistScore = track.artist.isEmpty
                ? 1
                : Self.similarity(result.artistName ?? "", track.artist)

            var nameScore = Self.similarity(result.trackName ?? "", track.title)
            if !track.album.isEmpty {
                nameScore = max(nameScore, Self.similarity(result.collectionName ?? "", track.album))
            }

            guard nameScore >= 0.6, artistScore >= 0.3 || nameScore >= 0.9 else { continue }

            // 没有艺人信息时无法交叉验证，要求结果艺人出现在标题里，否则很容易配到同名的无关专辑。
            if track.artist.isEmpty {
                let artistInTitle = Self.similarity(result.artistName ?? "", track.title) >= 0.35
                guard artistInTitle || nameScore >= 0.95, nameScore >= 0.8 else { continue }
            }

            let score = nameScore * 0.65 + artistScore * 0.35
            if best == nil || score > best!.score {
                best = (score, artworkURL)
            }
        }

        return best?.url
    }

    private static func largeArtworkURL(_ text: String) -> URL? {
        let larger = text.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: larger)
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    private static let hansTransform = StringTransform("Traditional-Simplified")

    private static func normalized(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        let simplified = folded.applyingTransform(hansTransform, reverse: false) ?? folded
        return String(simplified.unicodeScalars.filter {
            $0.properties.isAlphabetic || $0.properties.numericType != nil
        })
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }
        if left.count >= 2, right.count >= 2, left.contains(right) || right.contains(left) {
            return 0.85
        }

        let leftBigrams = bigrams(left)
        let rightBigrams = bigrams(right)
        guard !leftBigrams.isEmpty, !rightBigrams.isEmpty else { return 0 }

        var remaining = rightBigrams
        var overlap = 0
        for bigram in leftBigrams {
            if let index = remaining.firstIndex(of: bigram) {
                overlap += 1
                remaining.remove(at: index)
            }
        }
        return 2 * Double(overlap) / Double(leftBigrams.count + rightBigrams.count)
    }

    private static func bigrams(_ text: String) -> [String] {
        let characters = Array(text)
        guard characters.count >= 2 else { return characters.map(String.init) }
        return (0..<(characters.count - 1)).map { String(characters[$0...($0 + 1)]) }
    }

    // MARK: - Networking

    private func search(term: String, entity: String, country: String) async -> SearchOutcome {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "media", value: "music"),
        ]
        guard let url = components?.url else { return .failed }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        for attempt in 0..<2 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failed }

                if http.statusCode == 403 || http.statusCode == 429, attempt == 0 {
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    continue
                }
                guard http.statusCode == 200 else { return .failed }
                guard let decoded = try? JSONDecoder().decode(ITunesResponse.self, from: data) else {
                    return .failed
                }
                return decoded.results.isEmpty ? .empty : .results(decoded.results)
            } catch {
                return .failed
            }
        }

        return .failed
    }

    private func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else {
            return nil
        }
        return data
    }

    // MARK: - Storage

    private func store(_ data: Data, key: String, tracks group: [Track]) {
        let fileName = Self.fileName(for: key)
        guard (try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)) != nil else {
            return
        }

        for track in group {
            index.tracks[Self.stableKey(track.url.path)] = fileName
            ArtworkCache.shared.invalidate(track.url)
            NotificationCenter.default.post(name: .artworkUpdated, object: track.id)
        }
        persist()
    }

    private static func fileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
