import CueCore
import SwiftUI

/// The delivery coach: quiet, neutral facts about a take. Not a score.
struct CoachCardView: View {
    let report: DeliveryReport?
    let targetWordsPerMinute: Int

    var body: some View {
        VStack(alignment: .leading, spacing: CueSpacing.l) {
            Text("Delivery")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CueColor.primaryText)
            if let report, report.wordsSpoken > 0 {
                content(report)
            } else {
                Text("No speech summary for this take. Cue builds one on this device when speech recognition is available while you record.")
                    .font(.subheadline)
                    .foregroundStyle(CueColor.secondaryText)
            }
        }
        .padding(CueSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coachCard")
    }

    @ViewBuilder
    private func content(_ report: DeliveryReport) -> some View {
        CoachRow(
            symbol: "speedometer",
            title: "Pace",
            detail: Text("\(Int(report.actualWordsPerMinute.rounded())) words per minute. Your target was \(report.targetWordsPerMinute).")
        )
        CoachRow(
            symbol: "text.badge.checkmark",
            title: "Script covered",
            detail: Text(report.scriptCoverage, format: .percent.precision(.fractionLength(0)))
        )
        CoachRow(
            symbol: "pause.circle",
            title: "Longest pauses",
            detail: report.longestPauses.isEmpty
                ? Text("No pauses longer than a second.")
                : Text(report.longestPauses.map(pauseDescription).joined(separator: "\n"))
        )
        CoachRow(
            symbol: "arrow.triangle.branch",
            title: "Off script",
            detail: report.offScript.isEmpty
                ? Text("You stayed with the script.")
                : Text(report.offScript.map(offScriptDescription).joined(separator: "\n"))
        )
        CoachRow(
            symbol: "ellipsis.bubble",
            title: "Filler words",
            detail: report.fillerCount == 0
                ? Text("None heard.")
                : Text("\(report.fillerCount): \(fillerBreakdown(report))")
        )
    }

    private func pauseDescription(_ pause: DeliveryReport.Pause) -> String {
        let seconds = pause.duration.formatted(.number.precision(.fractionLength(1)))
        if let word = pause.afterWord {
            return String(localized: "\(seconds) sec after “\(word)”")
        }
        return String(localized: "\(seconds) sec")
    }

    private func offScriptDescription(_ segment: DeliveryReport.OffScript) -> String {
        let quote = segment.text.count > 60 ? String(segment.text.prefix(60)) + "…" : segment.text
        if let section = segment.sectionIndex {
            return String(localized: "Section \(section + 1): “\(quote)”")
        }
        return "“\(quote)”"
    }

    private func fillerBreakdown(_ report: DeliveryReport) -> String {
        report.fillers
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
    }
}

private struct CoachRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CueSpacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(CueColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CueSpacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CueColor.primaryText)
                detail
                    .font(.subheadline)
                    .foregroundStyle(CueColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Coach card") {
    let document = ScriptParser.parse(SampleData.scripts[1].body)
    var options = TranscriptSimulator.Options()
    options.fillerRate = 0.08
    options.longPauseRate = 0.05
    let transcript = TranscriptSimulator(options: options).transcript(for: document)
    let report = DeliveryCoach.analyze(transcript: transcript, document: document, targetWordsPerMinute: 140, duration: transcript.last?.end ?? 0)
    return ScrollView {
        CoachCardView(report: report, targetWordsPerMinute: 140)
            .padding()
    }
}
