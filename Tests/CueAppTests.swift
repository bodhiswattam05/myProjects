import CueCore
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Cue

@MainActor
@Suite("Prompter view model")
struct PrompterViewModelTests {
    static let text = """
    First line of the script here.
    Second line keeps going.
    ---
    Third line starts section two.
    Fourth line ends it.
    """

    /// Lays out one line every 60 points, as the stage view would report.
    func makeModel(pacing: PrompterSettings.Pacing = .voice) -> PrompterViewModel {
        var settings = PrompterSettings()
        settings.pacing = pacing
        settings.countdownSeconds = 0
        let model = PrompterViewModel(title: "Test", text: Self.text, settings: settings, speech: nil)
        for (index, line) in model.document.sections.flatMap(\.lines).enumerated() {
            model.setLineFrame(line.id, frame: CGRect(x: 0, y: Double(index) * 60, width: 300, height: 50))
        }
        model.setStageHeight(800)
        return model
    }

    func timed(_ text: String) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { index, word in
            TimedWord(text: String(word), start: Double(index) * 0.4, end: Double(index) * 0.4 + 0.3)
        }
    }

    @Test func transcriptAdvancesSpokenPosition() {
        let model = makeModel()
        model.handle(timed("first line of the"))
        #expect(model.spokenThrough == 3)
        model.handle(timed("first line of the script here second"))
        #expect(model.spokenThrough == 6)
        #expect(model.transcript.count == 7)
    }

    @Test func steadyPacingIgnoresAlignmentButKeepsTranscript() {
        let model = makeModel(pacing: .manual)
        model.handle(timed("first line of the"))
        #expect(model.spokenThrough == -1)
        #expect(model.transcript.count == 4)
    }

    @Test func voiceFallsBackToSteadyWhenUnavailable() {
        let model = makeModel()
        #expect(model.effectivePacing == .voice)
        model.voiceUnavailable("No model")
        #expect(model.effectivePacing == .manual)
    }

    @Test func jumpsBetweenSections() {
        let model = makeModel(pacing: .manual)
        model.jumpToNextSection()
        // Section two starts on the third line, at y = 120.
        #expect(model.offset == 120)
        #expect(model.sectionJumpCount == 1)
        model.jumpToPreviousSection()
        #expect(model.offset == 0)
    }

    @Test func scrubbingClampsToScript() {
        let model = makeModel(pacing: .manual)
        model.beginScrub()
        model.scrub(by: -10_000)
        #expect(model.offset == model.maxOffset)
        model.scrub(by: 10_000)
        #expect(model.offset == 0)
        model.endScrub()
    }

    @Test func playPauseCycle() {
        let model = makeModel(pacing: .manual)
        #expect(model.phase == .ready)
        model.togglePlayPause()
        #expect(model.phase == .running)
        model.togglePlayPause()
        #expect(model.phase == .paused)
        model.togglePlayPause()
        #expect(model.phase == .running)
        model.teardown()
    }

    @Test func countdownStartsBeforeRunning() {
        var settings = PrompterSettings()
        settings.countdownSeconds = 3
        let model = PrompterViewModel(title: "Test", text: Self.text, settings: settings, speech: nil)
        model.start()
        #expect(model.phase == .countdown(3))
        model.togglePlayPause()
        #expect(model.phase == .ready)
        model.teardown()
    }

    @Test func linesAboveTheBandCountAsRead() {
        let model = makeModel(pacing: .manual)
        model.beginScrub()
        model.scrub(by: -125)
        #expect(model.isLineRead(model.document.sections[0].lines[0].id))
        #expect(model.isLineRead(model.document.sections[0].lines[1].id))
        #expect(!model.isLineRead(model.document.sections[1].lines[0].id))
    }
}

@MainActor
@Suite("Sample data")
struct SampleDataTests {
    func freshDefaults() -> UserDefaults {
        let name = "cue.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func seedsOnceWithEveryMarkupTag() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let defaults = freshDefaults()
        SampleData.seedIfNeeded(container.mainContext, defaults: defaults)
        SampleData.seedIfNeeded(container.mainContext, defaults: defaults)
        let scripts = try container.mainContext.fetch(FetchDescriptor<Script>())
        let presets = try container.mainContext.fetch(FetchDescriptor<PrompterPreset>())
        #expect(scripts.count == 3)
        #expect(presets.count == 3)

        let welcome = try #require(scripts.first { $0.title == "Welcome to Cue" })
        for tag in ["[pause]", "[breathe]", "*", "//", "---"] {
            #expect(welcome.body.contains(tag), "missing \(tag)")
        }
    }

    @Test func resetRestoresSamplesWithoutTouchingUserScripts() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        SampleData.seedIfNeeded(context, defaults: freshDefaults())
        context.insert(Script(title: "Mine", body: "Hello"))
        let first = try #require(try context.fetch(FetchDescriptor<Script>()).first { $0.isSample })
        context.delete(first)
        try context.save()

        SampleData.reset(context)
        let scripts = try context.fetch(FetchDescriptor<Script>())
        #expect(scripts.filter(\.isSample).count == 3)
        #expect(scripts.contains { $0.title == "Mine" })
        #expect(try context.fetch(FetchDescriptor<PrompterPreset>()).count == 3)
        #expect(try context.fetch(FetchDescriptor<ScriptFolder>()).count == 1)
    }
}

@Suite("Importer and settings")
struct ImporterTests {
    @Test func markdownMapsToCueMarkup() {
        let markdown = """
        # Title
        Some **bold** words and __more__.
        - a list item
        ***
        Next
        """
        let script = ScriptImporter.markdownToScript(markdown)
        #expect(script == "Title\nSome *bold* words and *more*.\na list item\n---\nNext")
    }

    @Test func readsPlainTextFiles() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Talk notes.txt")
        try "Hello there [pause]".write(to: url, atomically: true, encoding: .utf8)
        let imported = try ScriptImporter.read(url)
        #expect(imported == .init(title: "Talk notes", body: "Hello there [pause]"))
    }

    @Test func emptyFilesAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "empty.txt")
        try "  \n".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: ScriptImporter.ImportError.self) { try ScriptImporter.read(url) }
    }

    @Test func settingsDecodeWithMissingKeys() throws {
        let data = Data(#"{"fontSize": 60, "isMirrored": true}"#.utf8)
        let settings = try JSONDecoder().decode(PrompterSettings.self, from: data)
        #expect(settings.fontSize == 60)
        #expect(settings.isMirrored)
        #expect(settings.readingLinePosition == PrompterSettings().readingLinePosition)
    }

    @Test func presetsRoundTrip() {
        let preset = PrompterPreset(name: "Rig", settings: .rigMode)
        #expect(preset.settings == .rigMode)
    }
}

@Suite("Lens placement")
struct LensPlacementTests {
    @Test func portraitPhoneUsesTopPanel() {
        let placement = LensPlacement.make(size: CGSize(width: 390, height: 844), orientation: .portrait, isPad: false, camera: .front)
        #expect(placement.alignment == .top)
        #expect(placement.heightFraction < 0.5)
    }

    @Test func landscapePhoneHugsTheCameraSide() {
        let size = CGSize(width: 844, height: 390)
        #expect(LensPlacement.make(size: size, orientation: .landscapeRight, isPad: false, camera: .front).alignment == .topLeading)
        #expect(LensPlacement.make(size: size, orientation: .landscapeLeft, isPad: false, camera: .front).alignment == .topTrailing)
    }

    @Test func rearCameraUsesFullStage() {
        let placement = LensPlacement.make(size: CGSize(width: 390, height: 844), orientation: .portrait, isPad: false, camera: .back)
        #expect(placement.heightFraction == 1)
    }
}

@MainActor
@Suite("Script polish")
struct PolishTests {
    @Test func cleanStripsPreambleAndQuotes() {
        #expect(PolishPrompt.clean("Here's the rewrite:\n\"We're ready.\"") == "We're ready.")
        #expect(PolishPrompt.clean("  “Short and sweet.”  ") == "Short and sweet.")
        #expect(PolishPrompt.clean("Plain text") == "Plain text")
    }

    @Test func trimPromptTargetsWordCount() {
        let prompt = PolishPrompt.prompt(for: "text", action: .trim(seconds: 30), wordsPerMinute: 140)
        #expect(prompt.contains("about 70 words"))
    }

    @Test func simulatedPolisherSuggestsAndRefusesNoOps() async throws {
        let polisher = SimulatedPolisher()
        let revised = try await polisher.polish("We are here. It is time.", action: .makeSpoken, wordsPerMinute: 140)
        #expect(revised == "We're here. It's time.")
        await #expect(throws: PolishError.self) {
            try await polisher.polish("Nothing to change", action: .makeSpoken, wordsPerMinute: 140)
        }
    }
}
