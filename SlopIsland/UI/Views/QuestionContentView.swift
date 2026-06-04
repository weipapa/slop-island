import SwiftUI

/// Paginated AskUserQuestion: shows ONE question at a time. Answering a single-
/// select question advances to the next; multi-select shows a Next/Submit button.
/// When the last question is answered, `onComplete` fires with the chosen option
/// index per question, in order.
struct QuestionContentView: View {
    let question: UserQuestion
    /// Ordered selected option index for each question.
    let onComplete: ([Int]) -> Void
    /// Notified when the visible page changes, so the panel can resize.
    var onPageChange: (Int) -> Void = { _ in }

    @State private var selections: [Int?]
    @State private var current: Int = 0

    private let cyan = Color(red: 0.0, green: 0.75, blue: 0.85)

    init(question: UserQuestion,
         onComplete: @escaping ([Int]) -> Void,
         onPageChange: @escaping (Int) -> Void = { _ in }) {
        self.question = question
        self.onComplete = onComplete
        self.onPageChange = onPageChange
        _selections = State(initialValue: Array(repeating: nil, count: question.items.count))
    }

    private var item: QuestionItem { question.items[current] }
    private var isLast: Bool { current == question.items.count - 1 }
    private var multiCount: Int { question.items.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if multiCount > 1, !item.header.isEmpty {
                Text(item.header)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }

            Text(item.prompt)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { oIndex, option in
                    Button {
                        select(oIndex)
                    } label: {
                        optionRow(number: oIndex + 1, option: option,
                                  isSelected: selections[current] == oIndex)
                    }
                    .buttonStyle(.plain)
                }
            }

            if item.multiSelect {
                Button {
                    advance()
                } label: {
                    Text(isLast ? "Submit" : "Next \u{2192}")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selections[current] == nil ? .white.opacity(0.3) : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selections[current] == nil ? Color.white.opacity(0.1) : cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(selections[current] == nil)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if current > 0 {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 11))
                .foregroundColor(cyan)
            Text("Claude asks")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(cyan)
            if multiCount > 1 {
                Spacer(minLength: 8)
                Text("\(current + 1) / \(multiCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private func select(_ oIndex: Int) {
        selections[current] = oIndex
        // Single-select advances immediately; multi-select waits for the button.
        if !item.multiSelect {
            advance()
        }
    }

    private func advance() {
        guard selections[current] != nil else { return }
        if isLast {
            onComplete(selections.compactMap { $0 })
        } else {
            current += 1
            onPageChange(current)
        }
    }

    private func goBack() {
        guard current > 0 else { return }
        current -= 1
        onPageChange(current)
    }

    private func optionRow(number: Int, option: QuestionOption, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? .black : cyan)
                .frame(width: 20, height: 20)
                .background(isSelected ? cyan : cyan.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let desc = option.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(isSelected ? 0.12 : 0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? cyan.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}
