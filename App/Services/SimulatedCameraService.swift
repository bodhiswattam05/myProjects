import AVFoundation
import Observation
import UIKit

/// Stands in for the camera in the Simulator, previews and UI tests. Recording writes a
/// short, real movie file (a slate with a moving bar) so takes, playback and export can
/// be tested end to end without camera hardware.
@MainActor
@Observable
final class SimulatedCameraService: CameraControlling {
    let isSimulated = true
    private(set) var position: CameraPosition = .front
    private(set) var resolution: VideoResolution = .hd1080
    private(set) var frameRate = 30
    private(set) var isRecording = false
    let supportedResolutions: [VideoResolution] = [.hd720, .hd1080]
    let audioInputs: [AudioInputOption] = [AudioInputOption(id: "simulated", name: String(localized: "Simulated microphone"))]
    private(set) var selectedAudioInputID: String? = "simulated"

    @ObservationIgnored private let preview = SimulatedPreviewView()
    @ObservationIgnored private var startedAt: ContinuousClock.Instant?

    var previewView: UIView { preview }

    func supportedFrameRates(for resolution: VideoResolution) -> [Int] { [24, 30] }

    func configure(position: CameraPosition, resolution: VideoResolution, frameRate: Int) async throws {
        self.position = position
        self.resolution = supportedResolutions.contains(resolution) ? resolution : .hd1080
        self.frameRate = [24, 30].contains(frameRate) ? frameRate : 30
        preview.setPosition(position)
    }

    func selectAudioInput(id: String?) {
        selectedAudioInputID = id
    }

    func startPreview() {}
    func stopPreview() {}
    func updateRotation() {}

    func startRecording() async throws -> AsyncStream<AudioChunk> {
        guard !isRecording else { throw CameraError.cannotRecord }
        isRecording = true
        startedAt = .now
        preview.setRecording(true)
        // No real audio; the simulated speech service supplies the transcript instead.
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
        continuation.finish()
        return stream
    }

    func stopRecording() async throws -> RecordingResult {
        guard isRecording, let startedAt else { throw CameraError.notRecording }
        isRecording = false
        preview.setRecording(false)
        let elapsed = startedAt.duration(to: .now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let url = TakeStorage.newFileURL()
        // Keep generated files small: at most 20 seconds of 360×640 at 10 fps.
        try await SimulatedMovieWriter.write(to: url, seconds: min(max(seconds, 1), 20))
        return RecordingResult(url: url, duration: seconds)
    }
}

/// A calm placeholder where the camera picture would be.
final class SimulatedPreviewView: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(hex: 0x2A2F38)
        label.text = String(localized: "Simulated front camera")
        label.textColor = UIColor(hex: 0x8A8F98)
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -140)
        ])
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Simulated camera preview")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setPosition(_ position: CameraPosition) {
        label.text = position == .front
            ? String(localized: "Simulated front camera")
            : String(localized: "Simulated rear camera")
    }

    func setRecording(_ recording: Bool) {
        backgroundColor = recording ? UIColor(hex: 0x30262A) : UIColor(hex: 0x2A2F38)
    }
}

enum SimulatedMovieWriter {
    static func write(to url: URL, seconds: Double) async throws {
        let width = 360, height = 640, fps: Int32 = 10
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw CameraError.cannotRecord }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CameraError.cannotRecord }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(seconds * Double(fps))
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool else { break }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let pixelBuffer else { continue }
            draw(into: pixelBuffer, progress: Double(frame) / Double(max(frames, 1)), width: width, height: height)
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CameraError.cannotRecord }
    }

    private static func draw(into buffer: CVPixelBuffer, progress: Double, width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        context.setFillColor(UIColor(hex: 0x1A1D24).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(UIColor(hex: 0xF2B25C).cgColor)
        let y = CGFloat(height) * (0.2 + 0.6 * progress)
        context.fill(CGRect(x: 40, y: y, width: CGFloat(width - 80), height: 18))
    }
}
