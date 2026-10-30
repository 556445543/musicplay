import SwiftUI

struct LyricsPane: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var lyricsLibrary: LyricsLibrary
    @EnvironmentObject private var lyricsOffsets: LyricsOffsetStore

    @State private var lyrics: Lyrics?
    @State private var isLoading = false

    private var offset: Double {
        lyricsOffsets.offset(for: player.currentTrack)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SyncedLyricsView(
                lyrics: lyrics,
                isLoading: isLoading,
                currentTime: player.currentTime - offset,
                onSeek: player.currentTrack == nil ? nil : { time in
                    player.seek(to: max(time + offset, 0))
                },
                emptyText: player.currentTrack == nil ? "选择一首歌查看歌词" : "没有找到这首歌的歌词"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task(id: player.currentTrack?.id) {
            await loadLyrics()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("歌词")
                .font(.system(size: 13, weight: .semibold))

            if let lyrics {
                Text(lyrics.sourceLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }

            Spacer(minLength: 0)

            if lyrics?.isTimed == true, player.currentTrack != nil {
                offsetControl
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var offsetControl: some View {
        HStack(spacing: 0) {
            Button {
                lyricsOffsets.adjust(for: player.currentTrack, by: -0.5)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("歌词提前 0.5 秒")

            Button {
                lyricsOffsets.reset(for: player.currentTrack)
            } label: {
                Text(lyricsOffsetLabel(offset))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .frame(minWidth: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("歌词偏移，点击归零")

            Button {
                lyricsOffsets.adjust(for: player.currentTrack, by: 0.5)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("歌词延后 0.5 秒")
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(offset == 0 ? Color.secondary : Color.accentColor)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("歌词偏移")
    }

    private func loadLyrics() async {
        guard let track = player.currentTrack else {
            lyrics = nil
            isLoading = false
            return
        }

        isLoading = true
        let loaded = await lyricsLibrary.lyrics(for: track)
        guard player.currentTrack?.id == track.id else { return }
        lyrics = loaded
        isLoading = false
    }
}
