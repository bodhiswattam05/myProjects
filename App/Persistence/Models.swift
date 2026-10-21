import Foundation
import SwiftData
import CueCore

// Every stored property has a default and every relationship is optional, with no
// unique constraints. That keeps the schema CloudKit-compatible for the optional
// iCloud sync toggle.

@Model
final class ScriptFolder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \Script.folder)
    var scripts: [Script]? = []

    init(name: String) {
        self.name = name
    }
}

@Model
final class Script {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date.now
    var editedAt: Date = Date.now
    /// Target pace for this script, in words per minute.
    var wordsPerMinute: Int = ReadTimeEstimator.defaultWordsPerMinute
    var isSample: Bool = false
    var folder: ScriptFolder?
    @Relationship(deleteRule: .nullify, inverse: \Take.script)
    var takes: [Take]? = []

    init(title: String, body: String, wordsPerMinute: Int = ReadTimeEstimator.defaultWordsPerMinute, folder: ScriptFolder? = nil, isSample: Bool = false) {
        self.title = title
        self.body = body
        self.wordsPerMinute = wordsPerMinute
        self.folder = folder
        self.isSample = isSample
    }

    /// Title for lists: the stored title, or the first words of the body.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let words = firstLine.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? String(localized: "Untitled script") : words
    }

    /// The body with markup removed, for list previews and search.
    var plainPreview: String {
        let document = ScriptParser.parse(body)
        return document.words.prefix(30).map(\.display).joined(separator: " ")
    }

    func touch() {
        editedAt = .now
    }
}

@Model
final class Take {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var duration: Double = 0
    /// File name inside `TakeStorage.directory`. Nil if the file was never written.
    var fileName: String?
    var cameraPositionRaw: String = CameraPosition.front.rawValue
    var resolutionLabel: String = ""
    var scriptTitle: String = ""
    /// The delivery coach summary, JSON-encoded `DeliveryReport`.
    var reportData: Data?
    /// True when made by the simulated camera (Simulator, UI tests).
    var isSimulated: Bool = false
    var script: Script?

    init(scriptTitle: String, script: Script?, duration: Double, fileName: String?, cameraPosition: CameraPosition, resolutionLabel: String, isSimulated: Bool) {
        self.scriptTitle = scriptTitle
        self.script = script
        self.duration = duration
        self.fileName = fileName
        self.cameraPositionRaw = cameraPosition.rawValue
        self.resolutionLabel = resolutionLabel
        self.isSimulated = isSimulated
    }

    var cameraPosition: CameraPosition {
        CameraPosition(rawValue: cameraPositionRaw) ?? .front
    }

    var fileURL: URL? {
        fileName.map { TakeStorage.directory.appending(path: $0) }
    }

    var report: DeliveryReport? {
        get { reportData.flatMap { try? JSONDecoder().decode(DeliveryReport.self, from: $0) } }
        set { reportData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

@Model
final class PrompterPreset {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var isBuiltIn: Bool = false
    /// JSON-encoded `PrompterSettings`, so new settings can be added without a migration.
    var settingsData: Data = Data()

    init(name: String, settings: PrompterSettings, isBuiltIn: Bool = false) {
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.settingsData = (try? JSONEncoder().encode(settings)) ?? Data()
    }

    var settings: PrompterSettings {
        get { (try? JSONDecoder().decode(PrompterSettings.self, from: settingsData)) ?? PrompterSettings() }
        set { settingsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

enum CameraPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case front
    case back

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .front: String(localized: "Front")
        case .back: String(localized: "Rear")
        }
    }
}

/// Where take files live: Application Support/Takes. Never synced; included in the
/// user's own device backup.
enum TakeStorage {
    static var directory: URL {
        let base = URL.applicationSupportDirectory.appending(path: "Takes", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func newFileURL() -> URL {
        directory.appending(path: "take-\(UUID().uuidString).mov")
    }

    static func delete(_ take: Take) {
        if let url = take.fileURL { try? FileManager.default.removeItem(at: url) }
    }
}

enum CueSchema {
    static var models: [any PersistentModel.Type] { [Script.self, ScriptFolder.self, Take.self, PrompterPreset.self] }
}
