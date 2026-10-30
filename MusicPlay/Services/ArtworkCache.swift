import Foundation
import ImageIO

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
    private var keysByPath: [String: Set<String>] = [:]

    private init() {
        images.countLimit = 400
    }

    func artwork(for url: URL, maxPixelSize: Int = 1024) async -> PlatformImage? {
        let path = url.path
        let key = cacheKey(path: path, maxPixelSize: maxPixelSize)
        if let image = images.object(forKey: key as NSString) {
            return image
        }
        if knownMisses.contains(path) {
            return nil
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<PlatformImage?, Never> {
            let data: Data?
            if let embedded = await MetadataLoader.artworkData(for: url) {
                data = embedded
            } else {
                data = await OnlineArtworkStore.shared.diskData(for: path)
            }
            guard let data else { return nil }
            return await Self.downsample(data, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            images.setObject(image, forKey: key as NSString)
            keysByPath[path, default: []].insert(key)
        } else {
            knownMisses.insert(path)
        }
        return image
    }

    func invalidate(_ url: URL) {
        let path = url.path
        for key in keysByPath[path] ?? [] {
            images.removeObject(forKey: key as NSString)
        }
        keysByPath[path] = nil
        knownMisses.remove(path)
        let staleKeys = inFlight.keys.filter { $0.hasPrefix("\(path)#") }
        for key in staleKeys {
            inFlight[key] = nil
        }
    }

    private func cacheKey(path: String, maxPixelSize: Int) -> String {
        "\(path)#\(maxPixelSize)"
    }

    // 行内封面在滚动时大量出现，解码和缩放都必须离开主线程，只保留缩略图尺寸。
    private nonisolated static func downsample(_ data: Data, maxPixelSize: Int) async -> PlatformImage? {
        await Task.detached(priority: .userInitiated) {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                #if os(macOS)
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                #else
                return UIImage(cgImage: cgImage)
                #endif
            }
            return PlatformImage(data: data)
        }.value
    }
}
