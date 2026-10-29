import SwiftUI

struct EqualizerBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = sin(time * 5 + Double(index) * 1.9)
                    let height = 5 + 8 * (0.5 + 0.5 * wave)
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 2.5, height: max(3, height))
                }
            }
            .frame(width: 24, height: 16, alignment: .bottom)
        }
    }
}
