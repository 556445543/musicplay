import SwiftUI

#if os(iOS)
import UIKit
#endif

struct SyncedLyricsView: View {
    let lyrics: Lyrics?
    var isLoading: Bool = false
    let currentTime: TimeInterval
    var tintColor: Color = .accentColor
    var baseColor: Color = .secondary
    var lineFontSize: CGFloat = 15
    var contentHorizontalPadding: CGFloat = 18
    var onSeek: ((TimeInterval) -> Void)?
    var emptyText: String = "没有找到这首歌的歌词"

    @State private var followsPlayback = true

    private var activeIndex: Int? {
        lyrics?.activeIndex(at: currentTime)
    }

    var body: some View {
        Group {
            if let lyrics, lyrics.isTimed {
                timedLines(lyrics)
            } else if let lyrics, let plainText = lyrics.plainText {
                plainLines(plainText)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
    }

    private func timedLines(_ lyrics: Lyrics) -> some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: lineFontSize * 1.1) {
                            ForEach(lyrics.lines) { line in
                                lineView(line, isActive: line.id == activeIndex)
                                    .id(line.id)
                            }
                        }
                        .padding(.horizontal, contentHorizontalPadding)
                        .padding(.vertical, max(36, geo.size.height * 0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { _ in
                                if followsPlayback {
                                    followsPlayback = false
                                }
                            }
                    )
                    .mask(edgeFade)

                    if !followsPlayback, let activeIndex {
                        followButton(proxy, index: activeIndex)
                            .padding(.leading, max(contentHorizontalPadding - 14, 0))
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: followsPlayback)
                .onChange(of: activeIndex) { _, newValue in
                    guard followsPlayback, let newValue else { return }
                    withAnimation(.smooth(duration: 0.45)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onChange(of: lyrics) { _, _ in
                    followsPlayback = true
                    guard let activeIndex else { return }
                    proxy.scrollTo(activeIndex, anchor: .center)
                }
                .onAppear {
                    guard let activeIndex else { return }
                    proxy.scrollTo(activeIndex, anchor: .center)
                }
            }
        }
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.055),
                .init(color: .black, location: 0.945),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func followButton(_ proxy: ScrollViewProxy, index: Int) -> some View {
        Button {
            followsPlayback = true
            withAnimation(.smooth(duration: 0.45)) {
                proxy.scrollTo(index, anchor: .center)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: max(9, lineFontSize - 7), weight: .semibold))
                Text("回到当前")
                    .font(.system(size: max(10, lineFontSize - 5), weight: .medium))
            }
            .foregroundStyle(tintColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到当前歌词")
    }

    private func lineView(_ line: LyricLine, isActive: Bool) -> some View {
        Button {
            seek(to: line.time)
            followsPlayback = true
        } label: {
            Text(line.text)
                .font(.system(size: isActive ? lineFontSize + 3 : lineFontSize, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? tintColor : baseColor)
                .opacity(isActive ? 1 : 0.7)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.22), value: isActive)
        }
        .buttonStyle(.plain)
        .disabled(onSeek == nil)
        .accessibilityLabel(line.text)
    }

    private func seek(to time: TimeInterval) {
        guard let onSeek else { return }
        onSeek(time)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func plainLines(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: lineFontSize))
                .foregroundStyle(baseColor)
                .lineSpacing(9)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.vertical, 32)
                .textSelection(.enabled)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 24, weight: .light))
            Text(emptyText)
                .font(.system(size: 12))
        }
        .foregroundStyle(baseColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
