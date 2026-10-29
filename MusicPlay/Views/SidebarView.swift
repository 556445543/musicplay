import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case allTracks
    case folder(URL)
}

struct SidebarView: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("资料库") {
                Label("所有歌曲", systemImage: "music.note.list")
                    .badge(library.tracks.count)
                    .tag(SidebarItem.allTracks)
            }

            Section("文件夹") {
                if library.folders.isEmpty {
                    Text("还没有导入文件夹")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(library.folders, id: \.self) { folder in
                        Label(folder.lastPathComponent, systemImage: "folder")
                            .lineLimit(1)
                            .help(folder.path)
                            .tag(SidebarItem.folder(folder))
                            .contextMenu {
                                Button("在访达中显示") {
                                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                                }
                                Button("从资料库移除") {
                                    if selection == .folder(folder) {
                                        selection = .allTracks
                                    }
                                    library.removeFolder(folder)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    library.importFolders()
                } label: {
                    Label("添加文件夹", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}
