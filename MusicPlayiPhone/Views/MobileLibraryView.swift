import SwiftUI
import UniformTypeIdentifiers

struct MobileLibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine

    @State private var searchText = ""
    @State private var importMode: ImportMode = .files
    @State private var showImporter = false
    @State private var showNowPlaying = false
    @State private var feedback: ImportFeedback?

    private var visibleTracks: [Track] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.tracks }
        return library.tracks.filter { track in
            track.title.localizedCaseInsensitiveContains(query)
                || track.artist.localizedCaseInsensitiveContains(query)
                || track.album.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty {
                    emptyLibrary
                } else if visibleTracks.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    trackList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("音乐库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            beginImport(.files)
                        } label: {
                            Label("导入歌曲", systemImage: "music.note")
                        }
                        Button {
                            beginImport(.folder)
                        } label: {
                            Label("导入文件夹", systemImage: "folder")
                        }
                        Divider()
                        Button {
                            feedback = ImportFeedback(
                                title: "如何导入音乐",
                                message: "点“导入歌曲”后，在文件选择器底部选择“浏览”，找到 MP3、M4A、FLAC、WAV 或 AIFF 文件。也可以连接电脑，在 Finder → iPhone → 文件 → MusicPlay 里直接拖入歌曲。\n\n注意：Apple Music 等流媒体里受版权保护的歌曲不能导入，必须是音乐文件本身。"
                            )
                        } label: {
                            Label("如何导入音乐？", systemImage: "questionmark.circle")
                        }
                        Button {
                            Task { await library.refresh() }
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                        }
                        .disabled(library.isScanning)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .accessibilityLabel("添加音乐")
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索歌曲、艺人或专辑"
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentTrack != nil {
                    MobileMiniPlayer(openPlayer: { showNowPlaying = true })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: player.currentTrack?.id)
            .overlay(alignment: .top) {
                if library.isImporting {
                    importingBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: library.isImporting)
            .alert("无法播放", isPresented: Binding(
                get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(player.errorMessage ?? "")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importMode.contentTypes,
            allowsMultipleSelection: importMode.allowsMultipleSelection
        ) { result in
            let mode = importMode
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                Task {
                    let count: Int
                    if mode == .folder, let folder = urls.first {
                        count = await library.importFolder(folder)
                    } else {
                        count = await library.importFiles(urls)
                    }
                    showImportResult(count)
                }
            case .failure(let error):
                guard (error as NSError).code != NSUserCancelledError else { return }
                feedback = ImportFeedback(title: "无法导入", message: error.localizedDescription)
            }
        }
        .alert(item: $feedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("好"))
            )
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            MobileNowPlayingView()
                .environmentObject(player)
        }
    }

    private var trackList: some View {
        List {
            Section {
                ForEach(visibleTracks) { track in
                    MobileTrackRow(
                        track: track,
                        isCurrent: player.currentTrack?.id == track.id,
                        isPlaying: player.isPlaying && player.currentTrack?.id == track.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        play(track)
                    }
                    .contextMenu {
                        Button {
                            player.play(track, in: visibleTracks)
                        } label: {
                            Label("播放", systemImage: "play.fill")
                        }
                        if player.currentTrack?.id == track.id {
                            Button {
                                player.togglePlayPause(fallbackQueue: visibleTracks)
                            } label: {
                                Label(
                                    player.isPlaying ? "暂停" : "继续播放",
                                    systemImage: player.isPlaying ? "pause.fill" : "play.fill"
                                )
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(rowBackground(for: track))
                }
            } header: {
                HStack(spacing: 6) {
                    Text("\(visibleTracks.count) 首歌曲")
                    if library.isScanning || library.isImporting {
                        ProgressView()
                            .controlSize(.mini)
                        Text(library.isImporting ? "正在导入…" : "正在扫描…")
                    }
                    Spacer(minLength: 0)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await library.refresh()
        }
    }

    private var emptyLibrary: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.38, green: 0.34, blue: 0.78),
                                    Color(red: 0.58, green: 0.32, blue: 0.68),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 108)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)

                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 48)

                VStack(spacing: 8) {
                    Text("把音乐放进口袋")
                        .font(.title2.weight(.bold))
                    Text("从“文件”导入歌曲或整个文件夹，音乐会被复制到 MusicPlay 自己的资料库里。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                VStack(spacing: 12) {
                    Button {
                        beginImport(.files)
                    } label: {
                        Label("导入歌曲", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        beginImport(.folder)
                    } label: {
                        Label("导入文件夹", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 32)

                VStack(spacing: 6) {
                    Text("支持 MP3、M4A、FLAC、WAV、AIFF 等格式")
                    Text("导入时在文件选择器底部点“浏览”找到歌曲；也可以用数据线连接电脑，在 Finder → iPhone → 文件 → MusicPlay 里直接拖入。")
                        .multilineTextAlignment(.center)
                }
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 28)

                if library.isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在扫描资料库…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var importingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text("正在导入歌曲…")
                .font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .foregroundStyle(.white)
        .padding(.top, 10)
    }

    private func rowBackground(for track: Track) -> Color {
        player.currentTrack?.id == track.id
            ? Color.accentColor.opacity(0.09)
            : Color(.systemBackground)
    }

    private func play(_ track: Track) {
        if player.currentTrack?.id == track.id {
            player.togglePlayPause(fallbackQueue: visibleTracks)
        } else {
            player.play(track, in: visibleTracks)
        }
    }

    private func beginImport(_ mode: ImportMode) {
        importMode = mode
        showImporter = true
    }

    private func showImportResult(_ count: Int) {
        if count > 0 {
            feedback = ImportFeedback(
                title: "导入完成",
                message: "已向资料库添加 \(count) 首歌曲。"
            )
        } else {
            feedback = ImportFeedback(
                title: "没有可导入的歌曲",
                message: "请选择 MP3、M4A、FLAC、WAV 或 AIFF 格式的音频文件。"
            )
        }
    }
}

private enum ImportMode: Equatable {
    case files
    case folder

    var contentTypes: [UTType] {
        switch self {
        case .files: return [.audio]
        case .folder: return [.folder]
        }
    }

    var allowsMultipleSelection: Bool {
        switch self {
        case .files: return true
        case .folder: return false
        }
    }
}

private struct ImportFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct MobileTrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.url, size: 50, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(track.artist.isEmpty ? "未知艺人" : track.artist)
                    if !track.album.isEmpty {
                        Text("·")
                        Text(track.album)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isCurrent {
                if isPlaying {
                    EqualizerBars()
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            } else if track.duration > 0 {
                Text(durationString(track.duration))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
