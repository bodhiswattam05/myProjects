import AVFoundation
import AVKit
import CueCore
import Photos
import SwiftData
import SwiftUI

/// Every recorded take, newest first.
struct TakesListView: View {
    @Query(sort: [SortDescriptor(\Take.createdAt, order: .reverse)]) private var takes: [Take]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if takes.isEmpty {
                ContentUnavailableView {
                    Label("No takes yet", systemImage: "film")
                } description: {
                    Text("Open a script and tap Record. Takes stay on this device until you export them.")
                }
            } else {
                List {
                    ForEach(takes) { take in
                        NavigationLink {
                            TakeDetailView(take: take)
                        } label: {
                            TakeRow(take: take)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(take) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Takes")
    }

    private func delete(_ take: Take) {
        TakeStorage.delete(take)
        modelContext.delete(take)
        try? modelContext.save()
    }
}

struct TakeRow: View {
    let take: Take

    var body: some View {
        HStack(spacing: CueSpacing.m) {
            TakeThumbnail(url: take.fileURL)
                .frame(width: 56, height: 72)
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: CueSpacing.xs) {
                Text(take.scriptTitle)
                    .font(.headline)
                    .foregroundStyle(CueColor.primaryText)
                    .lineLimit(1)
                Text(take.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(CueColor.secondaryText)
                HStack(spacing: CueSpacing.s) {
                    Text(Duration.seconds(take.duration), format: .time(pattern: .minuteSecond))
                        .monospacedDigit()
                    if take.isSimulated {
                        Text("Simulated")
                    }
                }
                .font(.caption)
                .foregroundStyle(CueColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("takeRow")
    }
}

/// First frame of a take, loaded off the main thread.
struct TakeThumbnail: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            CueColor.stage
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film")
                    .foregroundStyle(CueColor.mist)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { return }
            image = await Self.thumbnail(for: url)
        }
    }

    nonisolated static func thumbnail(for url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let (cgImage, _) = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Plays a take, shows its coach card, and exports or shares it.
struct TakeDetailView: View {
    let take: Take
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var exportState: ExportState = .idle

    enum ExportState: Equatable {
        case idle
        case exporting
        case done
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueSpacing.xl) {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .frame(maxHeight: 520)
                        .clipShape(.rect(cornerRadius: 16))
                        .frame(maxWidth: .infinity)
                }
                CoachCardView(report: take.report, targetWordsPerMinute: take.script?.wordsPerMinute ?? ReadTimeEstimator.defaultWordsPerMinute)
                details
            }
            .padding(CueSpacing.l)
        }
        .background(CueColor.background)
        .navigationTitle(take.scriptTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url = take.fileURL {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                Menu {
                    Button("Export to Photos", systemImage: "photo.on.rectangle") {
                        Task { await export() }
                    }
                    Button("Delete take", systemImage: "trash", role: .destructive) {
                        TakeStorage.delete(take)
                        modelContext.delete(take)
                        try? modelContext.save()
                        dismiss()
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .onAppear {
            if let url = take.fileURL, FileManager.default.fileExists(atPath: url.path()) {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear { player?.pause() }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: CueSpacing.s) {
            LabeledContent("Length") {
                Text(Duration.seconds(take.duration), format: .time(pattern: .minuteSecond))
            }
            LabeledContent("Camera", value: take.cameraPosition.displayName)
            if !take.resolutionLabel.isEmpty {
                LabeledContent("Format", value: take.resolutionLabel)
            }
            switch exportState {
            case .idle: EmptyView()
            case .exporting: ProgressView("Exporting…")
            case .done: Label("Saved to Photos", systemImage: "checkmark.circle").foregroundStyle(CueColor.accent)
            case let .failed(message): Text(message).foregroundStyle(CueColor.cueRed)
            }
        }
        .font(.subheadline)
    }

    private func export() async {
        guard let url = take.fileURL else { return }
        exportState = .exporting
        guard await PermissionCenter.requestPhotosAddAccess() else {
            exportState = .failed(String(localized: "Cue needs permission to add to Photos. You can allow it in Settings."))
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            exportState = .done
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }
}

/// Shown right after a take is saved.
struct TakeSummarySheet: View {
    let take: Take
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                CoachCardView(report: take.report, targetWordsPerMinute: take.script?.wordsPerMinute ?? ReadTimeEstimator.defaultWordsPerMinute)
                    .padding(CueSpacing.l)
            }
            .navigationTitle("Take saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("takeSummary.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
