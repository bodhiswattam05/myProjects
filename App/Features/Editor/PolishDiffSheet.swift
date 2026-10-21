import CueCore
import SwiftUI

/// A suggested rewrite awaiting the user's decision.
struct PolishRequest: Identifiable {
    let id = UUID()
    let action: PolishAction
    let range: NSRange
    let original: String
}

/// Runs one polish action and shows the result as a word diff. The script only changes
/// if the user taps "Use this".
struct PolishDiffSheet: View {
    let request: PolishRequest
    let wordsPerMinute: Int
    let polisher: any ScriptPolishing
    var onAccept: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .working

    enum LoadState {
        case working
        case ready(String)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CueSpacing.l) {
                    switch state {
                    case .working:
                        HStack(spacing: CueSpacing.m) {
                            ProgressView()
                            Text("Rewriting on this device…")
                                .foregroundStyle(CueColor.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, CueSpacing.xxl)
                    case let .ready(revised):
                        legend
                        Text(diffText(revised))
                            .font(.body)
                            .textSelection(.enabled)
                            .accessibilityLabel(Text(spokenDiff(revised)))
                            .accessibilityIdentifier("polish.diff")
                        timing(revised)
                    case let .failed(message):
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(CueColor.secondaryText)
                    }
                }
                .padding(CueSpacing.l)
            }
            .background(CueColor.background)
            .navigationTitle(request.action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep original") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case let .ready(revised) = state {
                        Button("Use this") {
                            onAccept(revised)
                            dismiss()
                        }
                        .accessibilityIdentifier("polish.accept")
                    }
                }
            }
            .task { await run() }
        }
        .presentationDetents([.medium, .large])
    }

    private var legend: some View {
        HStack(spacing: CueSpacing.l) {
            Label("Removed", systemImage: "minus")
                .foregroundStyle(CueColor.secondaryText)
            Label("Added", systemImage: "plus")
                .foregroundStyle(CueColor.accent)
        }
        .font(.caption)
    }

    private func timing(_ revised: String) -> some View {
        let estimator = ReadTimeEstimator(wordsPerMinute: wordsPerMinute)
        let before = ReadTimeEstimator.format(seconds: estimator.seconds(for: request.original))
        let after = ReadTimeEstimator.format(seconds: estimator.seconds(for: revised))
        return Text("Read time: \(before) → \(after)")
            .font(.subheadline)
            .foregroundStyle(CueColor.secondaryText)
    }

    private func diffText(_ revised: String) -> AttributedString {
        var result = AttributedString()
        for (index, token) in WordDiff.tokens(from: request.original, to: revised).enumerated() {
            if index > 0 { result.append(AttributedString(" ")) }
            var piece = AttributedString(token.text)
            switch token.kind {
            case .same:
                piece.foregroundColor = CueColor.primaryText
            case .removed:
                piece.foregroundColor = CueColor.secondaryText
                piece.strikethroughStyle = .single
            case .added:
                piece.foregroundColor = CueColor.accent
                piece.underlineStyle = .single
            }
            result.append(piece)
        }
        return result
    }

    /// The diff in words, since VoiceOver can't hear strikethrough.
    private func spokenDiff(_ revised: String) -> String {
        WordDiff.tokens(from: request.original, to: revised).map { token in
            switch token.kind {
            case .same: token.text
            case .removed: String(localized: "Removed: \(token.text).")
            case .added: String(localized: "Added: \(token.text).")
            }
        }.joined(separator: " ")
    }

    private func run() async {
        do {
            let revised = try await polisher.polish(request.original, action: request.action, wordsPerMinute: wordsPerMinute)
            state = .ready(revised)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

#Preview("Polish diff") {
    PolishDiffSheet(
        request: PolishRequest(action: .makeSpoken, range: NSRange(location: 0, length: 0), original: "We are going to look at three habits, and it is easier than you think."),
        wordsPerMinute: 140,
        polisher: SimulatedPolisher(),
        onAccept: { _ in }
    )
}
