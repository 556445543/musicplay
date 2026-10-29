import SwiftUI

struct MobileMiniPlayer: View {
    @EnvironmentObject private var player: PlayerEngine
    var openPlayer: () -> Void

    private var progress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(max(player.currentTime / player.duration, 0), 1))
    }

    private var subtitle: String {
        guard let track = player.currentTrack else { return "" }
        let artist = track.artist.isEmpty ? "未知艺人" : track.artist
        return track.album.isEmpty ? artist : "\(artist) · \(track.album)"
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Color.clear
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 2)

            HStack(spacing: 12) {
                ArtworkView(url: player.currentTrack?.url, size: 44, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.title ?? "未在播放")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一首")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial, ignoresSafeAreaEdges: .bottom)
        .contentShape(Rectangle())
        .onTapGesture(perform: openPlayer)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("打开播放页")
    }
}
