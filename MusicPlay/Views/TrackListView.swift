import AppKit
import SwiftUI

struct TrackListView: View, Equatable {
    @EnvironmentObject private var library: LibraryStore

    let title: String
    let tracks: [Track]
    let isScanning: Bool
    let isLibraryEmpty: Bool
    let hasActiveSearch: Bool
    @Binding var searchText: String
    @Binding var sort: TrackSort
    let allowsSorting: Bool
    let favoriteIDs: Set<String>
    let currentTrackID: String?
    let isPlaying: Bool
    let emptyIcon: String
    let emptyTitle: String
    let emptyMessage: String
    let onPlay: (Track) -> Void
    let onToggleFavorite: (Track) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if tracks.isEmpty {
                emptyState
            } else {
                columnHeader
                Divider()
                trackList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(tracks.count) 首歌曲")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在扫描…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 12)

            SearchField(text: $searchText)

            if allowsSorting {
                Menu {
                    TrackSortMenuContent(sort: $sort)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text(sort.option.label)
                            .font(.system(size: 12))
                        Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("排序方式")
            }

            Button {
                Task { await library.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("重新扫描资料库")
            .disabled(isScanning)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLibraryEmpty {
            EmptyStateView(
                icon: "music.note.house",
                title: "资料库还是空的",
                message: "导入一个音乐文件夹，或直接把文件夹拖进窗口。支持 MP3、M4A、FLAC、WAV、AIFF 等格式。",
                actionTitle: "导入音乐文件夹",
                action: { library.importFolders() }
            )
        } else if hasActiveSearch {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "没有找到歌曲",
                message: "换个关键词试试，或清空搜索。"
            )
        } else {
            EmptyStateView(
                icon: emptyIcon,
                title: emptyTitle,
                message: emptyMessage
            )
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("#")
                .frame(width: 24, alignment: .leading)

            if allowsSorting {
                Button {
                    toggleSort(.title)
                } label: {
                    HStack(spacing: 10) {
                        Color.clear.frame(width: 34, height: 1)
                        sortLabel("标题", option: .title)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    toggleSort(.album)
                } label: {
                    sortLabel("专辑", option: .album)
                        .frame(width: 170, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Color.clear.frame(width: 24, height: 1)

                Button {
                    toggleSort(.duration)
                } label: {
                    sortLabel("时长", option: .duration)
                        .frame(width: 52, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Color.clear.frame(width: 34, height: 1)
                    Text("标题")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("专辑")
                    .frame(width: 170, alignment: .leading)

                Color.clear.frame(width: 24, height: 1)

                Text("时长")
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.02))
    }

    private func sortLabel(_ title: String, option: TrackSortOption) -> some View {
        HStack(spacing: 3) {
            Text(title)
            if sort.option == option {
                Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func toggleSort(_ option: TrackSortOption) {
        if sort.option == option {
            sort = TrackSort(option: option, ascending: !sort.ascending)
        } else {
            sort = TrackSort(option: option, ascending: option.preferredAscending)
        }
    }

    private var trackList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        index: index + 1,
                        track: track,
                        isCurrent: currentTrackID == track.id,
                        isPlaying: isPlaying && currentTrackID == track.id,
                        isFavorite: favoriteIDs.contains(track.stableID),
                        onPlay: { onPlay(track) },
                        onToggleFavorite: { onToggleFavorite(track) }
                    )
                }
            }
            .padding(.vertical, 6)
        }
    }

    static func == (lhs: TrackListView, rhs: TrackListView) -> Bool {
        lhs.title == rhs.title
            && lhs.tracks == rhs.tracks
            && lhs.isScanning == rhs.isScanning
            && lhs.isLibraryEmpty == rhs.isLibraryEmpty
            && lhs.hasActiveSearch == rhs.hasActiveSearch
            && lhs.searchText == rhs.searchText
            && lhs.sort == rhs.sort
            && lhs.allowsSorting == rhs.allowsSorting
            && lhs.favoriteIDs == rhs.favoriteIDs
            && lhs.currentTrackID == rhs.currentTrackID
            && lhs.isPlaying == rhs.isPlaying
            && lhs.emptyIcon == rhs.emptyIcon
            && lhs.emptyTitle == rhs.emptyTitle
            && lhs.emptyMessage == rhs.emptyMessage
    }
}

private struct TrackRow: View {
    let index: Int
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    if isPlaying {
                        EqualizerBars()
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Text("\(index)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 24)

            HStack(spacing: 10) {
                ArtworkView(url: track.url, size: 34, cornerRadius: 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? "未知艺人" : track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.album.isEmpty ? "—" : track.album)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isFavorite ? Color.pink : Color.secondary.opacity(isHovering ? 0.9 : 0.5))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "取消喜欢" : "喜欢")
            .accessibilityLabel(isFavorite ? "取消喜欢" : "喜欢")

            Text(durationString(track.duration))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onPlay()
        }
        .contextMenu {
            Button("播放") {
                onPlay()
            }
            Button(isFavorite ? "取消喜欢" : "喜欢") {
                onToggleFavorite()
            }
            Button("在访达中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([track.url])
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var rowBackground: Color {
        if isCurrent {
            return Color.accentColor.opacity(isHovering ? 0.14 : 0.09)
        }
        return isHovering ? Color.primary.opacity(0.05) : .clear
    }
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("搜索", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { isFocused = true }
        .help("支持歌名、歌手、专辑，也支持拼音和首字母，例如 zjl")
    }
}
