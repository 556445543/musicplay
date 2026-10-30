import AVFoundation
import Foundation

@MainActor
final class LyricsLibrary: ObservableObject {
    private var index: [String: URL] = [:]
    private var indexedFolders: [URL] = []
    private var indexGeneration = 0
    private var indexTask: Task<Void, Never>?

    private var parsedCache: [String: Lyrics] = [:]
    private var failedPaths: Set<String> = []
    private var embeddedCache: [String: Lyrics] = [:]
    private var embeddedChecked: Set<String> = []

    func updateFolders(_ folders: [URL]) {
        let normalized = folders
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
        guard normalized != indexedFolders else { return }
        rebuildIndex(in: normalized)
    }

    // 同一批文件夹里新增了歌词文件（例如导入歌曲时一起复制的 KRC/LRC）
    func refreshIndex() {
        guard !indexedFolders.isEmpty else { return }
        rebuildIndex(in: indexedFolders)
    }

    private func rebuildIndex(in folders: [URL]) {
        indexedFolders = folders
        index = [:]
        indexGeneration += 1
        let generation = indexGeneration

        indexTask = Task { [weak self] in
            let map = await Task.detached(priority: .utility) {
                Self.buildIndex(in: folders)
            }.value
            guard let self, !Task.isCancelled, self.indexGeneration == generation else { return }
            self.index = map
        }
    }

    func lyrics(for track: Track) async -> Lyrics? {
        await indexTask?.value

        if let url = lyricURL(for: track) {
            if let cached = parsedCache[url.path] {
                return cached
            }
            if !failedPaths.contains(url.path) {
                let parsed = await Task.detached(priority: .userInitiated) {
                    LyricsParser.parseFile(at: url)
                }.value
                if let parsed {
                    parsedCache[url.path] = parsed
                    return parsed
                }
                failedPaths.insert(url.path)
            }
        }

        return await embeddedLyrics(for: track)
    }

    // MARK: - Index

    nonisolated private static func buildIndex(in folders: [URL]) -> [String: URL] {
        var map: [String: URL] = [:]
        let fileManager = FileManager.default

        for folder in folders {
            guard let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                guard ext == "krc" || ext == "lrc" else { continue }

                let key = normalize(fileURL.deletingPathExtension().lastPathComponent)
                guard !key.isEmpty else { continue }

                if let existing = map[key] {
                    if ext == "krc", existing.pathExtension.lowercased() == "lrc" {
                        map[key] = fileURL
                    }
                } else {
                    map[key] = fileURL
                }
            }
        }

        return map
    }

    private func lyricURL(for track: Track) -> URL? {
        let keys = candidateKeys(for: track)

        for key in keys {
            if let url = index[key] {
                return url
            }
        }

        var bestScore: Int?
        var bestURLs: Set<URL> = []

        for (key, url) in index where key.count >= 4 {
            for candidate in keys where candidate.count >= 4 {
                guard key.contains(candidate) || candidate.contains(key) else { continue }
                let score = abs(key.count - candidate.count)
                if bestScore == nil || score < bestScore! {
                    bestScore = score
                    bestURLs = [url]
                } else if score == bestScore {
                    bestURLs.insert(url)
                }
                break
            }
        }

        return bestURLs.count == 1 ? bestURLs.first : nil
    }

    private func candidateKeys(for track: Track) -> [String] {
        let stem = track.url.deletingPathExtension().lastPathComponent
        var keys = [Self.normalize(stem)]

        if !track.title.isEmpty {
            keys.append(Self.normalize(track.title))
            if !track.artist.isEmpty {
                keys.append(Self.normalize(track.artist + track.title))
            }
        }

        var seen = Set<String>()
        return keys.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    nonisolated private static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars where scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    // MARK: - Embedded lyrics

    private func embeddedLyrics(for track: Track) async -> Lyrics? {
        if let cached = embeddedCache[track.id] {
            return cached
        }
        if embeddedChecked.contains(track.id) {
            return nil
        }

        let loaded = await Self.loadEmbedded(url: track.url)
        embeddedChecked.insert(track.id)
        if let loaded {
            embeddedCache[track.id] = loaded
        }
        return loaded
    }

    nonisolated private static func loadEmbedded(url: URL) async -> Lyrics? {
        let asset = AVURLAsset(url: url)
        guard let formats = try? await asset.load(.availableMetadataFormats) else { return nil }

        for format in formats {
            guard let items = try? await asset.loadMetadata(for: format) else { continue }
            for item in items {
                let identifier = item.identifier?.rawValue.lowercased() ?? ""
                guard identifier.contains("uslt"),
                      let value = try? await item.load(.stringValue),
                      !value.isEmpty else { continue }

                if let lyrics = LyricsParser.parse(text: value, source: "内嵌") {
                    return lyrics
                }
            }
        }

        return nil
    }
}
