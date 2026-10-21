import Foundation
import SwiftData

/// Builds the SwiftData container. Local-only unless the user turns on iCloud sync and
/// this build has a CloudKit container configured (Info.plist `CueCloudKitContainer`).
enum ModelContainerFactory {
    static let cloudSyncKey = "cue.iCloudSyncEnabled"

    /// The CloudKit container identifier for this build, or nil when sync isn't set up.
    static var cloudKitContainerIdentifier: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "CueCloudKitContainer") as? String
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static var isCloudSyncAvailable: Bool { cloudKitContainerIdentifier != nil }

    static func make(inMemory: Bool = false, defaults: UserDefaults = .standard) -> ModelContainer {
        let schema = Schema(CueSchema.models)
        let wantsSync = defaults.bool(forKey: cloudSyncKey)
        let cloud: ModelConfiguration.CloudKitDatabase
        if !inMemory, wantsSync, let identifier = cloudKitContainerIdentifier {
            cloud = .private(identifier)
        } else {
            cloud = .none
        }
        // SwiftData logs a wall of errors on first launch if this folder doesn't exist yet.
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: cloud)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A store that can't open (for example after a bad migration in a prototype build)
            // shouldn't brick the app. Fall back to memory and say so in the log.
            print("Cue: could not open the store (\(error)). Using a temporary in-memory store.")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    /// In-memory container with sample data, for previews and tests.
    @MainActor
    static func preview() -> ModelContainer {
        let container = make(inMemory: true)
        let defaults = UserDefaults(suiteName: "cue.preview.\(UUID().uuidString)") ?? .standard
        SampleData.seedIfNeeded(container.mainContext, defaults: defaults)
        return container
    }
}
