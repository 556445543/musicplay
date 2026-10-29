import Combine
import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var folders: [URL] = []
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isScanning = false
    #if os(iOS)
    @Published private(set) var isImporting = false
    #endif

    private var needsRescan = false
    private let cacheURL: URL

    init() {
        let supportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicPlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        cacheURL = supportDirectory.appendingPathComponent("library.json")
        loadCache()
        #if os(iOS)
        prepareMobileLibrary()
        #endif
    }

    #if os(macOS)
    func importFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "导入"
        panel.message = "选择包含音乐文件的文件夹"
        panel.title = "导入音乐文件夹"

        if panel.runModal() == .OK {
            addFolders(panel.urls)
        }
    }
    #endif

    func addFolders(_ urls: [URL]) {
        var newFolders: [URL] = []

        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            let folder: URL
            if isDirectory.boolValue {
                folder = url
            } else if Track.supportedExtensions.contains(url.pathExtension.lowercased()) {
                folder = url.deletingLastPathComponent()
            } else {
                continue
            }

            if !folders.contains(folder), !newFolders.contains(folder) {
                newFolders.append(folder)
            }
        }

        guard !newFolders.isEmpty else { return }
        folders.append(contentsOf: newFolders)
        persist()
        Task { await refresh() }
    }

    func removeFolder(_ folder: URL) {
        folders.removeAll { $0.standardizedFileURL == folder.standardizedFileURL }
        tracks.removeAll { $0.isInside(folder: folder) }
        if isScanning {
            needsRescan = true
        }
        persist()
    }

    func refresh() async {
        guard !folders.isEmpty else {
            tracks = []
            persist()
            return
        }
        if isScanning {
            needsRescan = true
            return
        }

        isScanning = true
        defer {
            isScanning = false
            if needsRescan {
                needsRescan = false
                Task { await refresh() }
            }
        }

        let cachedByPath = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let foldersSnapshot = folders
        let discovered = await Task.detached(priority: .userInitiated) {
            Self.discoverAudioFiles(in: foldersSnapshot)
        }.value

        var scanned = discovered.map { url in
            cachedByPath[url.path] ?? Track(url: url)
        }
        scanned = scanned.filter { track in
            folders.contains { track.isInside(folder: $0) }
        }
        tracks = Self.sorted(scanned)

        let uncached = scanned.filter { cachedByPath[$0.id] == nil }
        if !uncached.isEmpty {
            let metadata = await loadMetadata(for: uncached)
            scanned = scanned.map { track in
                guard let meta = metadata[track.id] else { return track }
                var updated = track
                if let title = meta.title, !title.isEmpty { updated.title = title }
                if let artist = meta.artist, !artist.isEmpty { updated.artist = artist }
                if let album = meta.album, !album.isEmpty { updated.album = album }
                if meta.duration > 0 { updated.duration = meta.duration }
                return updated
            }
            tracks = Self.sorted(scanned.filter { track in
                folders.contains { track.isInside(folder: $0) }
            })
        }

        persist()
    }

    private func loadMetadata(for tracks: [Track]) async -> [String: LoadedMetadata] {
        var result: [String: LoadedMetadata] = [:]
        let batchSize = 6

        for start in stride(from: 0, to: tracks.count, by: batchSize) {
            let end = min(start + batchSize, tracks.count)
            let batch = Array(tracks[start..<end])
            await withTaskGroup(of: (String, LoadedMetadata).self) { group in
                for track in batch {
                    group.addTask {
                        (track.id, await MetadataLoader.load(for: track.url))
                    }
                }
                for await (id, metadata) in group {
                    result[id] = metadata
                }
            }
        }

        return result
    }

    private static func sorted(_ tracks: [Track]) -> [Track] {
        tracks.sorted { lhs, rhs in
            let order = lhs.title.localizedStandardCompare(rhs.title)
            if order == .orderedSame {
                return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
            }
            return order == .orderedAscending
        }
    }

    nonisolated private static func discoverAudioFiles(in folders: [URL]) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard Track.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
                let url = fileURL.standardizedFileURL
                if seen.insert(url.path).inserted {
                    urls.append(url)
                }
            }
        }

        return urls
    }

    private struct LibraryCache: Codable {
        var folders: [URL]
        var tracks: [Track]
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(LibraryCache.self, from: data) else { return }
        folders = cache.folders
        tracks = cache.tracks
    }

    private func persist() {
        let cache = LibraryCache(folders: folders, tracks: tracks)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    #if os(iOS)
    static var importedMusicDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
    }

    private func prepareMobileLibrary() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: Self.importedMusicDirectory, withIntermediateDirectories: true)
        folders = [documents]
        tracks = tracks.filter { $0.isInside(folder: documents) }
    }

    func importFiles(_ urls: [URL]) async -> Int {
        await importSources(urls)
    }

    func importFolder(_ url: URL) async -> Int {
        await importSources([url])
    }

    private func importSources(_ urls: [URL]) async -> Int {
        guard !isImporting, !urls.isEmpty else { return 0 }
        isImporting = true
        defer { isImporting = false }

        let destination = Self.importedMusicDirectory
        let copied = await Task.detached(priority: .userInitiated) {
            Self.copyAudio(from: urls, to: destination)
        }.value

        if copied > 0 {
            await refresh()
        }
        return copied
    }

    nonisolated private static func copyAudio(from urls: [URL], to destination: URL) -> Int {
        let fileManager = FileManager.default
        var copied = 0

        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    if copyFile(fileURL, to: destination) {
                        copied += 1
                    }
                }
            } else if copyFile(url, to: destination) {
                copied += 1
            }
        }

        return copied
    }

    nonisolated private static func copyFile(_ source: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        guard Track.supportedExtensions.contains(source.pathExtension.lowercased()) else { return false }

        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var target = destination.appendingPathComponent(source.lastPathComponent)
        var suffix = 2
        while fileManager.fileExists(atPath: target.path) {
            target = destination.appendingPathComponent("\(base) \(suffix).\(ext)")
            suffix += 1
        }

        do {
            try fileManager.copyItem(at: source, to: target)
            return true
        } catch {
            return false
        }
    }
    #endif
}
