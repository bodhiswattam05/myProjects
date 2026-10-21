import Foundation
import SwiftData

/// First-launch content so the app is usable straight away, plus the built-in presets.
@MainActor
enum SampleData {
    static let seededKey = "cue.sampleDataSeeded"

    static let scripts: [(title: String, body: String)] = [
        (
            "Welcome to Cue",
            """
            // This script uses every markup tag. Notes like this one are dimmed and never spoken.
            Hi, and welcome to *Cue*. [pause]
            This text scrolls while you read, and the glowing band shows where your eyes should be.
            [breathe]
            Tap once to pause. Double-tap to jump to the next section.
            ---
            Try *Follow my voice* in the prompter controls. // Works offline.
            Cue listens on this iPhone and keeps pace with you. If you stop, it waits. [pause]
            When you start again, it catches up smoothly.
            ---
            Words you have already said fade back, so the next line is always easy to find.
            That's it. *Happy recording.*
            """
        ),
        (
            "Product update, 60 seconds",
            """
            Hey everyone, quick update on what shipped this week. [pause]
            First, the new onboarding is live for all users. Early numbers look *really* encouraging.
            // Mention the team by name if there's time.
            ---
            Second, we fixed the sync issue that a few of you reported. [breathe]
            If you still see it, reply to this video and we'll look straight away.
            ---
            Next week, we're focusing on performance. [pause]
            Thanks for watching, and see you on Friday.
            """
        ),
        (
            "Conference talk opener",
            """
            Good morning, and thank you for having me. [pause]
            I want to start with a question. How many of you have rehearsed a talk in front of a mirror?
            [pause]
            // Wait for hands.
            Most of us have. And most of us stop after the first minute, because it feels strange.
            ---
            Today I'll share three habits that make rehearsal *feel natural*. [breathe]
            They take five minutes a day, and you can start this afternoon.
            """
        )
    ]

    static let presets: [(name: String, settings: PrompterSettings)] = [
        (String(localized: "Rig mode"), .rigMode),
        (String(localized: "Selfie mode"), .selfieMode),
        (String(localized: "Rehearsal"), .rehearsal)
    ]

    /// Seeds once per install. Safe to call on every launch.
    static func seedIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seededKey) else { return }
        insertAll(into: context)
        defaults.set(true, forKey: seededKey)
    }

    /// Debug: removes sample scripts and built-in presets, then adds fresh copies.
    /// The user's own scripts are left alone.
    static func reset(_ context: ModelContext) {
        try? context.delete(model: Script.self, where: #Predicate { $0.isSample })
        try? context.delete(model: PrompterPreset.self, where: #Predicate { $0.isBuiltIn })
        try? context.save()
        let folders = (try? context.fetch(FetchDescriptor<ScriptFolder>())) ?? []
        for folder in folders where (folder.scripts ?? []).isEmpty {
            context.delete(folder)
        }
        insertAll(into: context)
    }

    private static func insertAll(into context: ModelContext) {
        let folder = ScriptFolder(name: String(localized: "Samples"))
        context.insert(folder)
        for (offset, sample) in scripts.enumerated() {
            let script = Script(title: sample.title, body: sample.body, folder: folder, isSample: true)
            // Stagger edit dates so "last edited" order matches the list above.
            script.editedAt = Date.now.addingTimeInterval(Double(-offset) * 60)
            context.insert(script)
        }
        for preset in presets {
            context.insert(PrompterPreset(name: preset.name, settings: preset.settings, isBuiltIn: true))
        }
        try? context.save()
    }
}
