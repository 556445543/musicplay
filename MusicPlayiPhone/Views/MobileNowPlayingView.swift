import SwiftUI
import UIKit

struct MobileNowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var scrubTime: Double?
    @State private var backdrop: UIImage?

    private var maxDuration: Double {
        max(player.duration, 0.01)
    }

    private var displayedTime: Double {
        scrubTime ?? player.currentTime
    }

    private var subtitle: String {
        guard let track = player.currentTrack else { return "" }
        let artist = track.artist.isEmpty ? "未知艺人" : track.artist
        return track.album.isEmpty ? artist : "\(artist) · \(track.album)"
    }

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = min(proxy.size.width - 64, max(180, proxy.size.height * 0.38), 380)

            ZStack {
                background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    Spacer(minLength: 12)

                    ArtworkView(url: player.currentTrack?.url, size: artworkSize, cornerRadius: 28)
                        .shadow(color: .black.opacity(0.45), radius: 28, y: 18)
                        .scaleEffect(player.isPlaying ? 1 : 0.94)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: player.isPlaying)

                    Spacer(minLength: 26)

                    trackInfo
                    progressSection
                    transportControls

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: player.currentTrack?.id) {
            backdrop = nil
            guard let url = player.currentTrack?.url else { return }
            let image = await ArtworkCache.shared.artwork(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                backdrop = image
            }
        }
    }

    private var background: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.21, green: 0.18, blue: 0.40),
                        Color(red: 0.08, green: 0.08, blue: 0.13),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let backdrop {
                    Image(uiImage: backdrop)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 64)
                        .opacity(0.40)
                        .transition(.opacity)
                }

                Color.black.opacity(0.16)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭播放页")

            Spacer()

            Text("正在播放")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Color.clear
                .frame(width: 38, height: 38)
        }
    }

    private var trackInfo: some View {
        VStack(spacing: 7) {
            Text(player.currentTrack?.title ?? "未在播放")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var progressSection: some View {
        VStack(spacing: 4) {
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
            .tint(.white)
            .disabled(player.duration <= 0)

            HStack {
                Text(timeString(displayedTime))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.top, 26)
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            Button {
                player.shuffleEnabled.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(player.shuffleEnabled ? Color.accentColor : Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("随机播放")
            .accessibilityValue(player.shuffleEnabled ? "已开启" : "已关闭")

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一首")

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 76, height: 76)
                        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.14))
                        .offset(x: player.isPlaying ? 0 : 3)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一首")

            Button {
                cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? Color.white.opacity(0.55) : Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("循环播放")
            .accessibilityValue(repeatDescription)
        }
        .padding(.top, 18)
    }

    private var repeatDescription: String {
        switch player.repeatMode {
        case .off: return "已关闭"
        case .all: return "全部循环"
        case .one: return "单曲循环"
        }
    }

    private func cycleRepeatMode() {
        switch player.repeatMode {
        case .off: player.repeatMode = .all
        case .all: player.repeatMode = .one
        case .one: player.repeatMode = .off
        }
    }
}
