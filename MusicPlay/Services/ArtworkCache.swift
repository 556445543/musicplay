import Foundation

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()

    private let images = NSCache<NSString, PlatformImage>()
    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]
    private var knownMisses: Set<String> = []

    private init() {
        images.countLimit = 200
    }

    func artwork(for url: URL) async -> PlatformImage? {
        let key = url.path
        if let image = images.object(forKey: key as NSString) {
            return image
        }
        if knownMisses.contains(key) {
            return nil
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<PlatformImage?, Never> {
            guard let data = await MetadataLoader.artworkData(for: url) else { return nil }
            return PlatformImage(data: data)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            images.setObject(image, forKey: key as NSString)
        } else {
            knownMisses.insert(key)
        }
        return image
    }
}
