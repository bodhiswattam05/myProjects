import CueCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum LibrarySection: Hashable {
    case allScripts
    case takes
    case folder(UUID)
}

enum ScriptSort: String, CaseIterable, Identifiable {
    case lastEdited
    case title

    var id: String { rawValue }
    var displayName: LocalizedStringKey {
        switch self {
        case .lastEdited: "Last edited"
        case .title: "Title"
        }
    }
}

/// Folders → scripts → editor. Collapses to a stack on iPhone, opening on the script list.
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: [SortDescriptor(\ScriptFolder.createdAt)]) private var folders: [ScriptFolder]

    @State private var section: LibrarySection? = .allScripts
    @State private var selectedScriptID: PersistentIdentifier?
    @State private var preferredColumn: NavigationSplitViewColumn = .content
    @State private var showsSettings = false
    @State private var importError: String?
    @Binding var pendingImportURL: URL?

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            FolderSidebar(selection: $section, folders: folders)
                .navigationTitle("Cue")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        settingsButton
                    }
                }
        } content: {
            switch section ?? .allScripts {
            case .takes:
                TakesListView()
            case .allScripts:
                ScriptListView(folder: nil, selection: $selectedScriptID, showsSettings: $showsSettings, onImport: importFile)
            case let .folder(id):
                ScriptListView(folder: folders.first { $0.id == id }, selection: $selectedScriptID, showsSettings: $showsSettings, onImport: importFile)
            }
        } detail: {
            if let selectedScriptID, let script = modelContext.model(for: selectedScriptID) as? Script, !script.isDeleted {
                EditorView(script: script)
                    .id(script.id)
            } else {
                ContentUnavailableView {
                    Label("No script selected", systemImage: "text.alignleft")
                } description: {
                    Text("Choose a script, or write a new one.")
                }
            }
        }
        .tint(CueColor.accent)
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onChange(of: pendingImportURL) { _, url in
            guard let url else { return }
            importFile(url)
            pendingImportURL = nil
        }
        .onChange(of: section) { _, _ in selectedScriptID = nil }
        .onChange(of: selectedScriptID) { _, id in
            if id != nil { preferredColumn = .detail }
        }
    }

    private var settingsButton: some View {
        Button {
            showsSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .accessibilityIdentifier("library.settings")
    }

    private func importFile(_ url: URL) {
        do {
            let imported = try ScriptImporter.read(url)
            let folder: ScriptFolder? = if case let .folder(id) = section { folders.first { $0.id == id } } else { nil }
            let script = Script(title: imported.title, body: imported.body, wordsPerMinute: UserPreferences.defaultWordsPerMinute, folder: folder)
            modelContext.insert(script)
            try? modelContext.save()
            selectedScriptID = script.persistentModelID
            preferredColumn = .detail
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// The sidebar: everything, takes, and the user's folders.
struct FolderSidebar: View {
    @Binding var selection: LibrarySection?
    let folders: [ScriptFolder]
    @Environment(\.modelContext) private var modelContext
    @State private var isNamingFolder = false
    @State private var folderName = ""
    @State private var renaming: ScriptFolder?

    var body: some View {
        List(selection: $selection) {
            Label("All scripts", systemImage: "doc.text")
                .tag(LibrarySection.allScripts)
            Label("Takes", systemImage: "film.stack")
                .tag(LibrarySection.takes)
                .accessibilityIdentifier("sidebar.takes")
            Section("Folders") {
                ForEach(folders) { folder in
                    Label(folder.name, systemImage: "folder")
                        .badge((folder.scripts ?? []).count)
                        .tag(LibrarySection.folder(folder.id))
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                folderName = folder.name
                                renaming = folder
                                isNamingFolder = true
                            }
                            Button("Delete folder", systemImage: "trash", role: .destructive) {
                                delete(folder)
                            }
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(folder) }
                        }
                }
                Button("New folder", systemImage: "folder.badge.plus") {
                    folderName = ""
                    renaming = nil
                    isNamingFolder = true
                }
                .foregroundStyle(CueColor.accent)
            }
        }
        .alert(renaming == nil ? Text("New folder") : Text("Rename folder"), isPresented: $isNamingFolder) {
            TextField("Folder name", text: $folderName)
            Button("Save") { saveFolder() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scripts in a deleted folder stay in All scripts.")
        }
    }

    private func saveFolder() {
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let renaming {
            renaming.name = name
        } else {
            modelContext.insert(ScriptFolder(name: name))
        }
        try? modelContext.save()
    }

    private func delete(_ folder: ScriptFolder) {
        if selection == .folder(folder.id) { selection = .allScripts }
        modelContext.delete(folder)
        try? modelContext.save()
    }
}

/// Scripts, newest edit first, with search and swipe actions.
struct ScriptListView: View {
    let folder: ScriptFolder?
    @Binding var selection: PersistentIdentifier?
    @Binding var showsSettings: Bool
    var onImport: (URL) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Script.editedAt, order: .reverse)]) private var allScripts: [Script]
    @Query(sort: [SortDescriptor(\ScriptFolder.createdAt)]) private var folders: [ScriptFolder]
    @State private var searchText = ""
    @AppStorage("cue.scriptSort") private var sort: ScriptSort = .lastEdited
    @State private var showsImporter = false
    @State private var prompterScript: Script?

    var body: some View {
        Group {
            if scripts.isEmpty, searchText.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(scripts) { script in
                        ScriptRow(script: script)
                            .tag(script.persistentModelID)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(script) }
                                Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(script) }
                                    .tint(.gray)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Prompter", systemImage: "play.fill") { prompterScript = script }
                                    .tint(CueColor.tungstenDeep)
                            }
                            .contextMenu { contextMenu(for: script) }
                    }
                }
                .overlay {
                    if scripts.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
        .navigationTitle(folder?.name ?? String(localized: "All scripts"))
        .searchable(text: $searchText, prompt: Text("Search scripts"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(ScriptSort.allCases) { Text($0.displayName).tag($0) }
                    }
                    Button("Import from Files", systemImage: "square.and.arrow.down") { showsImporter = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .accessibilityIdentifier("library.more")
                Button {
                    newScript()
                } label: {
                    Label("New script", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("library.newScript")
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: ScriptImporter.contentTypes) { result in
            if case let .success(url) = result { onImport(url) }
        }
        .fullScreenCover(item: $prompterScript) { script in
            PrompterLauncher(script: script)
        }
    }

    private var scripts: [Script] {
        var result = allScripts
        if let folder {
            result = result.filter { $0.folder?.id == folder.id }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.title.localizedStandardContains(query) || $0.body.localizedStandardContains(query)
            }
        }
        if sort == .title {
            result.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
        return result
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Write or import your first script", systemImage: "text.alignleft")
        } description: {
            Text("Scripts stay on this device. Use [pause], *emphasis* and // notes as you write.")
        } actions: {
            Button("New script") { newScript() }
                .buttonStyle(.borderedProminent)
            Button("Import from Files") { showsImporter = true }
        }
    }

    @ViewBuilder
    private func contextMenu(for script: Script) -> some View {
        Button("Open prompter", systemImage: "play.fill") { prompterScript = script }
        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(script) }
        Menu("Move to folder", systemImage: "folder") {
            Button("No folder") { script.folder = nil }
            ForEach(folders) { folder in
                Button(folder.name) { script.folder = folder }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { delete(script) }
    }

    private func newScript() {
        let script = Script(title: "", body: "", wordsPerMinute: UserPreferences.defaultWordsPerMinute, folder: folder)
        modelContext.insert(script)
        try? modelContext.save()
        selection = script.persistentModelID
    }

    private func duplicate(_ script: Script) {
        let copy = Script(
            title: String(localized: "\(script.displayTitle) copy"),
            body: script.body,
            wordsPerMinute: script.wordsPerMinute,
            folder: script.folder
        )
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func delete(_ script: Script) {
        if selection == script.persistentModelID { selection = nil }
        modelContext.delete(script)
        try? modelContext.save()
    }
}

struct ScriptRow: View {
    let script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: CueSpacing.xs) {
            Text(script.displayTitle)
                .font(.headline)
                .foregroundStyle(CueColor.primaryText)
                .lineLimit(2)
            Text(script.plainPreview)
                .font(.subheadline)
                .foregroundStyle(CueColor.secondaryText)
                .lineLimit(2)
            HStack(spacing: CueSpacing.s) {
                Text(script.editedAt, format: .relative(presentation: .named))
                Text(verbatim: "·")
                    .accessibilityHidden(true)
                Text(readTime)
            }
            .font(.caption)
            .foregroundStyle(CueColor.secondaryText)
        }
        .padding(.vertical, CueSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scriptRow")
    }

    private var readTime: String {
        let seconds = ReadTimeEstimator(wordsPerMinute: script.wordsPerMinute).seconds(for: script.body)
        return ReadTimeEstimator.format(seconds: seconds)
    }
}

#Preview("Library") {
    @Previewable @State var url: URL?
    LibraryView(pendingImportURL: $url)
        .previewEnvironment()
}
