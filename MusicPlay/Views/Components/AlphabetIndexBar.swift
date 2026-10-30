import SwiftUI

struct AlphabetIndexBar: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var activeLetter: String?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(activeLetter == letter ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !letters.isEmpty else { return }
                        let step = max(proxy.size.height / CGFloat(letters.count), 1)
                        let index = min(max(Int(value.location.y / step), 0), letters.count - 1)
                        let letter = letters[index]
                        guard letter != activeLetter else { return }
                        activeLetter = letter
                        onSelect(letter)
                    }
                    .onEnded { _ in
                        activeLetter = nil
                    }
            )
        }
        .frame(width: 22)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: activeLetter)
        #endif
    }
}
