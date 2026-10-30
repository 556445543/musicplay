import Combine
import SwiftUI

struct ArtworkView: View {
    let url: URL?
    var size: CGFloat
    var cornerRadius: CGFloat = 6

    @Environment(\.displayScale) private var displayScale
    @State private var image: PlatformImage?

    private var maxPixelSize: Int {
        let pixels = Int((size * displayScale).rounded(.up))
        let bounded = min(max(pixels, 128), 1024)
        return (bounded + 63) / 64 * 64
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.38, green: 0.34, blue: 0.78),
                        Color(red: 0.58, green: 0.32, blue: 0.68),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            if let image {
                #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                #else
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                #endif
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .task(id: "\(url?.path ?? "")#\(maxPixelSize)") {
            guard let url else {
                image = nil
                return
            }
            let loaded = await ArtworkCache.shared.artwork(for: url, maxPixelSize: maxPixelSize)
            if !Task.isCancelled {
                image = loaded
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .artworkUpdated)) { notification in
            guard image == nil,
                  let path = notification.object as? String,
                  path == url?.path,
                  let url else { return }
            Task {
                let loaded = await ArtworkCache.shared.artwork(for: url, maxPixelSize: maxPixelSize)
                if !Task.isCancelled {
                    image = loaded
                }
            }
        }
    }
}
