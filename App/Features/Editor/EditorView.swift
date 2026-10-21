import CueCore
import SwiftData
import SwiftUI

/// Script editor: title, markup-aware body, live read time, and the way into the prompter
/// and the recorder.
struct EditorView: View {
    @Bindable var script: Script
    @Environment(\.modelContext) private var modelContext
    @State private var controller = MarkupTextController()
    @State private var presentation: Presentation?
    @State private var polishRequest: PolishRequest?
    @Environment(AppServices.self) private var services

    enum Presentation: String, Identifiable {
        case prompter
        case recorder
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $script.title, prompt: Text("Untitled script"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(CueColor.primaryText)
                .padding(.horizontal, CueSpacing.l + 1)
                .padding(.top, CueSpacing.m)
                .accessibilityIdentifier("editor.title")
                .submitLabel(.next)

            MarkupTextView(
                text: $script.body,
                controller: controller,
                placeholder: String(localized: "Write what you'll say. Use [pause], [breathe], *emphasis*, // notes and --- between sections.")
            )

            ReadTimeBar(text: script.body, wordsPerMinute: $script.wordsPerMinute)
        }
        .background(CueColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Hidden entirely where on-device models aren't available.
                if services.polisher.isAvailable {
                    polishMenu
                }
                Button {
                    controller.dismissKeyboard()
                    presentation = .recorder
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .accessibilityIdentifier("editor.record")

                Button {
                    controller.dismissKeyboard()
                    presentation = .prompter
                } label: {
                    Label("Open prompter", systemImage: "play.fill")
                }
                .accessibilityIdentifier("editor.openPrompter")
            }
            ToolbarItemGroup(placement: .keyboard) {
                markupButtons
            }
        }
        .onChange(of: script.body) { _, _ in script.touch() }
        .onChange(of: script.title) { _, _ in script.touch() }
        .onDisappear { try? modelContext.save() }
        .sheet(item: $polishRequest) { request in
            PolishDiffSheet(request: request, wordsPerMinute: script.wordsPerMinute, polisher: services.polisher) { revised in
                controller.replace(request.range, with: revised)
            }
        }
        .fullScreenCover(item: $presentation) { presentation in
            switch presentation {
            case .prompter: PrompterLauncher(script: script)
            case .recorder: RecorderLauncher(script: script)
            }
        }
    }

    private var polishMenu: some View {
        Menu {
            Section("Selected text, or the whole script") {
                Button(PolishAction.makeSpoken.title, systemImage: "quote.bubble") { requestPolish(.makeSpoken) }
                Menu("Trim to…", systemImage: "scissors") {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { seconds in
                        Button(PolishAction.trim(seconds: seconds).title) { requestPolish(.trim(seconds: seconds)) }
                    }
                }
                Button(PolishAction.addPauses.title, systemImage: "pause") { requestPolish(.addPauses) }
            }
        } label: {
            Label("Polish", systemImage: "wand.and.sparkles")
        }
        .accessibilityIdentifier("editor.polish")
    }

    private func requestPolish(_ action: PolishAction) {
        guard let selection = controller.selectionOrAll(), !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        controller.dismissKeyboard()
        polishRequest = PolishRequest(action: action, range: selection.range, original: selection.text)
    }

    @ViewBuilder
    private var markupButtons: some View {
        Button("Pause", systemImage: "pause") { controller.insert("[pause] ") }
            .accessibilityLabel(Text("Insert pause"))
        Button("Breathe", systemImage: "wind") { controller.insert("[breathe] ") }
            .accessibilityLabel(Text("Insert breathe"))
        Button("Emphasis", systemImage: "bold") { controller.toggleEmphasis() }
            .accessibilityLabel(Text("Emphasis"))
        Button("Note", systemImage: "text.bubble") { controller.insert("// ") }
            .accessibilityLabel(Text("Insert note"))
        Button("Section", systemImage: "minus") { controller.insert("\n---\n") }
            .accessibilityLabel(Text("Insert section break"))
        Spacer()
        Button("Done") { controller.dismissKeyboard() }
    }
}

/// Live estimate of how long the script takes to read, at the script's own pace.
struct ReadTimeBar: View {
    let text: String
    @Binding var wordsPerMinute: Int

    var body: some View {
        let document = ScriptParser.parse(text)
        let seconds = ReadTimeEstimator(wordsPerMinute: wordsPerMinute).seconds(for: document)
        HStack(spacing: CueSpacing.m) {
            Image(systemName: "clock")
                .foregroundStyle(CueColor.accent)
                .accessibilityHidden(true)
            Text("About \(ReadTimeEstimator.format(seconds: seconds))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CueColor.primaryText)
                .contentTransition(.numericText())
                .accessibilityIdentifier("editor.readTime")
            Text("\(document.words.count) words")
                .font(.subheadline)
                .foregroundStyle(CueColor.secondaryText)
            Spacer()
            Menu {
                Picker("Pace", selection: $wordsPerMinute) {
                    ForEach([100, 120, 140, 160, 180, 200], id: \.self) { value in
                        Text("\(value) words per minute").tag(value)
                    }
                }
            } label: {
                Text("\(wordsPerMinute) wpm")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CueColor.accent)
            }
            .accessibilityLabel(Text("Pace, \(wordsPerMinute) words per minute"))
        }
        .padding(.horizontal, CueSpacing.l)
        .padding(.vertical, CueSpacing.m)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Editor") {
    let container = ModelContainerFactory.preview()
    let script = (try? container.mainContext.fetch(FetchDescriptor<Script>()))?.first ?? Script(title: "Draft", body: "Hello [pause] world")
    return NavigationStack {
        EditorView(script: script)
    }
    .environment(AppServices.preview)
    .modelContainer(container)
}
