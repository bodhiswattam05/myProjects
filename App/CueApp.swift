import SwiftData
import SwiftUI

@main
struct CueApp: App {
    @State private var services: AppServices
    private let container: ModelContainer

    init() {
        if LaunchMode.isUITesting {
            // Clean, simulated app: in-memory store, fake camera and fake speech, no onboarding.
            UserDefaults.standard.set(true, forKey: PreferenceKey.hasCompletedOnboarding)
            container = ModelContainerFactory.make(inMemory: true)
            _services = State(initialValue: .simulated())
            let defaults = UserDefaults(suiteName: "cue.uitests") ?? .standard
            defaults.removePersistentDomain(forName: "cue.uitests")
            SampleData.seedIfNeeded(container.mainContext, defaults: defaults)
        } else {
            container = ModelContainerFactory.make()
            _services = State(initialValue: .live())
            SampleData.seedIfNeeded(container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @State private var pendingImportURL: URL?

    var body: some View {
        LibraryView(pendingImportURL: $pendingImportURL)
            .fullScreenCover(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { if !$0 { hasCompletedOnboarding = true } })) {
                OnboardingView { hasCompletedOnboarding = true }
            }
            // "Open in Cue" from Files or another app's share sheet.
            .onOpenURL { url in pendingImportURL = url }
    }
}
