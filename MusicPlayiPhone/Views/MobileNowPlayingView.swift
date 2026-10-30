import Combine
import SwiftUI
import UIKit

struct MobileNowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var lyricsLibrary: LyricsLibrary
    @EnvironmentObject private var activity: LibraryActivityStore
    @EnvironmentObject private var lyricsOffsets: LyricsOffsetStore
    @Environment(\.dismiss) private var dismiss

    @State private var scrubTime: Double?
    @State private var backdrop: UIImage?
    @State private var showLyrics = false
    @State private var lyrics: Lyrics?
    @State private var isLoadingLyrics = false
    @State private var swipeOffset: CGFloat = 0
    @AppStorage("lyricsFontScale") private var fontScale = 1.0

    private var maxDuration: Double {
        max(player.duration, 0.01)
    }

    private var displayedTime: Double {
        scrubTime ?? player.currentTime
    }

    private var offset: Double {
        lyricsOffsets.offset(for: player.currentTrack)
    }

    private var isFavorite: Bool {
        player.currentTrack.map { activity.isFavorite($0) } ?? false
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

                    if showLyrics {
                        lyricsPanel
                            .padding(.top, 4)
                            .transition(.opacity)

                        trackInfo
                            .padding(.top, 14)
                    } else {
                        Spacer(minLength: 12)

                        ArtworkView(url: player.currentTrack?.url, size: artworkSize, cornerRadius: 28)
                            .shadow(color: .black.opacity(0.45), radius: 28, y: 18)
                            .scaleEffect(player.isPlaying ? 1 : 0.94)
                            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: player.isPlaying)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showLyrics = true
                                }
                            }

                        Spacer(minLength: 26)

                        trackInfo
                    }

                    progressSection
                    transportControls

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 18)
                .animation(.easeInOut(duration: 0.25), value: showLyrics)
                .offset(x: swipeOffset)
                .simultaneousGesture(swipeToDismiss(in: proxy.size))
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
        .task(id: player.currentTrack?.id) {
            lyrics = nil
            guard let track = player.currentTrack else { return }
            isLoadingLyrics = true
            let loaded = await lyricsLibrary.lyrics(for: track)
            guard !Task.isCancelled, player.currentTrack?.id == track.id else { return }
            lyrics = loaded
            isLoadingLyrics = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .artworkUpdated)) { notification in
            guard backdrop == nil,
                  let path = notification.object as? String,
                  path == player.currentTrack?.id,
                  let url = player.currentTrack?.url else { return }
            Task {
                let image = await ArtworkCache.shared.artwork(for: url)
                guard !Task.isCancelled, player.currentTrack?.id == path else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    backdrop = image
                }
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
        ZStack {
            Text(showLyrics ? "歌词" : "正在播放")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))

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

                HStack(spacing: 8) {
                    if showLyrics, lyrics != nil {
                        lyricsMenu
                            .transition(.opacity)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLyrics.toggle()
                        }
                    } label: {
                        Image(systemName: showLyrics ? "photo" : "quote.bubble")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showLyrics ? "显示封面" : "显示歌词")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLyrics)
    }

    private var lyricsMenu: some View {
        Menu {
            if lyrics?.isTimed == true {
                Section("歌词偏移 \(lyricsOffsetLabel(offset))") {
                    Button {
                        lyricsOffsets.adjust(for: player.currentTrack, by: -0.5)
                    } label: {
                        Label("提前 0.5 秒", systemImage: "minus.circle")
                    }
                    Button {
                        lyricsOffsets.adjust(for: player.currentTrack, by: 0.5)
                    } label: {
                        Label("延后 0.5 秒", systemImage: "plus.circle")
                    }
                    Button {
                        lyricsOffsets.reset(for: player.currentTrack)
                    } label: {
                        Label("偏移归零", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(offset == 0)
                }
            }

            Section("歌词字体") {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        fontScale = max(0.8, fontScale - 0.1)
                    }
                } label: {
                    Label("小一点", systemImage: "textformat.size.smaller")
                }
                .disabled(fontScale <= 0.8)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        fontScale = min(1.4, fontScale + 0.1)
                    }
                } label: {
                    Label("大一点", systemImage: "textformat.size.larger")
                }
                .disabled(fontScale >= 1.4)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        fontScale = 1
                    }
                } label: {
                    Label("默认大小", systemImage: "textformat.size")
                }
                .disabled(abs(fontScale - 1) < 0.01)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(0.12)))
                .overlay(alignment: .topTrailing) {
                    if offset != 0 {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .offset(x: -1, y: 1)
                    }
                }
        }
        .accessibilityLabel("歌词设置")
    }

    private var lyricsPanel: some View {
        SyncedLyricsView(
            lyrics: lyrics,
            isLoading: isLoadingLyrics,
            currentTime: player.currentTime - offset,
            tintColor: .white,
            baseColor: .white.opacity(0.7),
            lineFontSize: CGFloat(17 * fontScale),
            contentHorizontalPadding: 0,
            onSeek: { time in player.seek(to: max(time + offset, 0)) },
            emptyText: "没有找到这首歌的歌词"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackInfo: some View {
        ZStack(alignment: .trailing) {
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
            .padding(.horizontal, 52)

            favoriteButton
        }
    }

    private var favoriteButton: some View {
        Button {
            guard let track = player.currentTrack else { return }
            activity.toggleFavorite(track)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.pink : Color.white.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.12)))
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(player.currentTrack == nil)
        .accessibilityLabel(isFavorite ? "取消喜欢" : "喜欢")
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

    private func swipeToDismiss(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard isHorizontalDismissDrag(value, in: size) else { return }
                swipeOffset = value.translation.width
            }
            .onEnded { value in
                guard isHorizontalDismissDrag(value, in: size) else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        swipeOffset = 0
                    }
                    return
                }
                let passed = abs(value.translation.width) > 90
                    || abs(value.predictedEndTranslation.width) > 180
                if passed {
                    let direction: CGFloat = value.translation.width < 0 ? -1 : 1
                    withAnimation(.easeOut(duration: 0.18)) {
                        swipeOffset = direction * size.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        dismiss()
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        swipeOffset = 0
                    }
                }
            }
    }

    private func isHorizontalDismissDrag(_ value: DragGesture.Value, in size: CGSize) -> Bool {
        guard value.startLocation.y < size.height * 0.67 else { return false }
        return abs(value.translation.width) > abs(value.translation.height) * 1.2
    }
}
