import AVFoundation
import Foundation

struct LoadedMetadata: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval = 0
}

enum MetadataLoader {
    static func load(for url: URL) async -> LoadedMetadata {
        let asset = AVURLAsset(url: url)
        var metadata = LoadedMetadata()

        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                metadata.duration = seconds
            }
        }

        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    metadata.title = try? await item.load(.stringValue)
                case .commonKeyArtist:
                    metadata.artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName:
                    metadata.album = try? await item.load(.stringValue)
                default:
                    break
                }
            }
        }

        return metadata
    }

    static func artworkData(for url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue) {
                return data
            }
        }
        return nil
    }
}
