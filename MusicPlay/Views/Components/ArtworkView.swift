import SwiftUI

struct ArtworkView: View {
    let url: URL?
    var size: CGFloat
    var cornerRadius: CGFloat = 6

    @State private var image: PlatformImage?

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
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let loaded = await ArtworkCache.shared.artwork(for: url)
            if !Task.isCancelled {
                image = loaded
            }
        }
    }
}
