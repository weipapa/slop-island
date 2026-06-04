import SwiftUI

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        Text(rendered)
            .textSelection(.enabled)
    }

    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
