import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var activity: LibraryActivityStore
    let fallbackQueue: [Track]
    @Binding var showLyrics: Bool

    @State private var scrubTime: Double?

    private var maxDuration: Double {
        max(player.duration, 0.01)
    }

    private var displayedTime: Double {
        scrubTime ?? player.currentTime
    }

    private var canPlay: Bool {
        player.currentTrack != nil || !fallbackQueue.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 20) {
                nowPlaying
                    .frame(width: 280, alignment: .leading)

                VStack(spacing: 3) {
                    transportControls
                    progressRow
                }
                .frame(maxWidth: .infinity)

                volumeControl
                    .frame(width: 150, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            ArtworkView(url: player.currentTrack?.url, size: 52, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentTrack?.title ?? "未在播放")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                guard let track = player.currentTrack else { return }
                activity.toggleFavorite(track)
            } label: {
                Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isCurrentFavorite ? Color.pink : Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.currentTrack == nil)
            .help(isCurrentFavorite ? "取消喜欢" : "喜欢")
            .accessibilityLabel(isCurrentFavorite ? "取消喜欢" : "喜欢")

            Button {
                showLyrics.toggle()
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(showLyrics ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showLyrics ? "隐藏歌词" : "显示歌词")
        }
    }

    private var isCurrentFavorite: Bool {
        player.currentTrack.map { activity.isFavorite($0) } ?? false
    }

    private var subtitle: String {
        guard let track = player.currentTrack else {
            return "选择一首歌开始播放"
        }
        let artist = track.artist.isEmpty ? "未知艺人" : track.artist
        if track.album.isEmpty {
            return artist
        }
        return "\(artist) — \(track.album)"
    }

    private var transportControls: some View {
        HStack(spacing: 18) {
            Button {
                player.shuffleEnabled.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(player.shuffleEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("随机播放")

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 15))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(player.currentTrack == nil ? Color.secondary.opacity(0.4) : Color.primary)
            .disabled(player.currentTrack == nil)
            .help("上一首")

            Button(action: playPause) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: player.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canPlay)
            .opacity(canPlay ? 1 : 0.45)
            .help(player.isPlaying ? "暂停" : "播放")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(player.currentTrack == nil ? Color.secondary.opacity(0.4) : Color.primary)
            .disabled(player.currentTrack == nil)
            .help("下一首")

            Button {
                player.repeatMode = player.repeatMode == .off ? .all : (player.repeatMode == .all ? .one : .off)
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(repeatHelp)
        }
    }

    private var repeatHelp: String {
        switch player.repeatMode {
        case .off: return "循环播放：关闭"
        case .all: return "循环播放：全部"
        case .one: return "循环播放：单曲"
        }
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            Text(timeString(displayedTime))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { min(max(displayedTime, 0), maxDuration) },
                    set: { scrubTime = $0 }
                ),
                in: 0...maxDuration,
                onEditingChanged: { editing in
                    if editing {
                        scrubTime = player.currentTime
                    } else {
                        if let time = scrubTime {
                            player.seek(to: time)
                        }
                        scrubTime = nil
                    }
                }
            )
            .controlSize(.small)
            .disabled(player.currentTrack == nil || player.duration <= 0)

            Text(timeString(player.duration))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: volumeSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Slider(value: $player.volume, in: 0...1)
                .controlSize(.small)
        }
    }

    private var volumeSymbol: String {
        if player.volume <= 0 {
            return "speaker.slash.fill"
        }
        if player.volume < 0.33 {
            return "speaker.fill"
        }
        if player.volume < 0.66 {
            return "speaker.wave.1.fill"
        }
        return "speaker.wave.2.fill"
    }

    private func playPause() {
        if player.currentTrack == nil, let first = fallbackQueue.first {
            player.play(first, in: fallbackQueue)
        } else {
            player.togglePlayPause(fallbackQueue: fallbackQueue)
        }
    }
}
