import SwiftUI

struct ProcessingSpinner: View {
    let color: Color
    private let symbols = ["\u{00B7}", "\u{2722}", "\u{2733}", "\u{2217}", "\u{273B}", "\u{273D}"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.15) % symbols.count
            Text(symbols[phase])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
        }
    }
}
