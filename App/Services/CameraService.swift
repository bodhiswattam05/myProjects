import AVFoundation
import Observation
import UIKit

enum VideoResolution: String, CaseIterable, Identifiable, Codable, Sendable {
    case hd720
    case hd1080
    case uhd4K

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hd720: "720p"
        case .hd1080: "1080p"
        case .uhd4K: "4K"
        }
    }

    /// Landscape sensor dimensions, as AVFoundation reports them.
    var dimensions: (width: Int32, height: Int32) {
        switch self {
        case .hd720: (1280, 720)
        case .hd1080: (1920, 1080)
        case .uhd4K: (3840, 2160)
        }
    }
}

struct AudioInputOption: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
}

struct RecordingResult: Sendable {
    var url: URL
    var duration: Double
}

enum CameraError: LocalizedError {
    case notAuthorized
    case noCamera
    case cannotRecord
    case notRecording

    var errorDescription: String? {
        switch self {
        case .notAuthorized: String(localized: "Cue doesn't have access to the camera. You can allow it in Settings.")
        case .noCamera: String(localized: "This camera isn't available.")
        case .cannotRecord: String(localized: "Recording couldn't start. Try again.")
        case .notRecording: String(localized: "Nothing is being recorded.")
        }
    }
}

/// Camera capture. The prompter overlay is drawn by SwiftUI on top of `previewView` and is
/// never part of the recorded video.
@MainActor
protocol CameraControlling: AnyObject {
    var isSimulated: Bool { get }
    var position: CameraPosition { get }
    var resolution: VideoResolution { get }
    var frameRate: Int { get }
    var isRecording: Bool { get }
    var previewView: UIView { get }
    var supportedResolutions: [VideoResolution] { get }
    func supportedFrameRates(for resolution: VideoResolution) -> [Int]
    var audioInputs: [AudioInputOption] { get }
    var selectedAudioInputID: String? { get }

    func configure(position: CameraPosition, resolution: VideoResolution, frameRate: Int) async throws
    func selectAudioInput(id: String?)
    func startPreview()
    func stopPreview()
    /// Starts writing a movie. Returns the take's audio so speech recognition can listen to it.
    func startRecording() async throws -> AsyncStream<AudioChunk>
    func stopRecording() async throws -> RecordingResult
    /// Keeps the picture upright as the device rotates.
    func updateRotation()
}

// MARK: - Live camera

@MainActor
@Observable
final class LiveCameraService: CameraControlling {
    let isSimulated = false
    private(set) var position: CameraPosition = .front
    private(set) var resolution: VideoResolution = .hd1080
    private(set) var frameRate = 30
    private(set) var isRecording = false
    private(set) var supportedResolutions: [VideoResolution] = []
    private(set) var audioInputs: [AudioInputOption] = []
    private(set) var selectedAudioInputID: String?

    @ObservationIgnored private let engine: CaptureEngine
    @ObservationIgnored private let preview: PreviewView
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    var previewView: UIView { preview }

    init() {
        let engine = CaptureEngine()
        self.engine = engine
        preview = PreviewView(session: engine.session)
    }

    func supportedFrameRates(for resolution: VideoResolution) -> [Int] {
        guard let device else { return [30] }
        return Self.frameRates(device: device, resolution: resolution)
    }

    func configure(position: CameraPosition, resolution: VideoResolution, frameRate: Int) async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw CameraError.notAuthorized }
        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition) else {
            throw CameraError.noCamera
        }
        let available = VideoResolution.allCases.filter { Self.format(device: device, resolution: $0, frameRate: 24) != nil }
        let chosen = available.contains(resolution) ? resolution : (available.last(where: { $0 != .uhd4K }) ?? available.last ?? .hd1080)
        let rates = Self.frameRates(device: device, resolution: chosen)
        let rate = rates.contains(frameRate) ? frameRate : (rates.contains(30) ? 30 : rates.first ?? 30)
        let format = Self.format(device: device, resolution: chosen, frameRate: rate)
        let wantsAudio = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        try await engine.configure(device: UncheckedBox(device), format: format.map { UncheckedBox($0) }, frameRate: rate, mirrored: position == .front, audio: wantsAudio)

        self.device = device
        self.position = position
        self.resolution = chosen
        self.frameRate = rate
        supportedResolutions = available
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview.previewLayer)
        refreshAudioInputs()
        updateRotation()
    }

    func selectAudioInput(id: String?) {
        let session = AVAudioSession.sharedInstance()
        let port = session.availableInputs?.first { $0.uid == id }
        try? session.setPreferredInput(port)
        selectedAudioInputID = port?.uid
    }

    func startPreview() {
        engine.startRunning()
    }

    func stopPreview() {
        engine.stopRunning()
    }

    func updateRotation() {
        guard let rotationCoordinator else { return }
        let previewAngle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
        if let connection = preview.previewLayer.connection, connection.isVideoRotationAngleSupported(previewAngle) {
            connection.videoRotationAngle = previewAngle
        }
        engine.setCaptureRotation(rotationCoordinator.videoRotationAngleForHorizonLevelCapture)
    }

    func startRecording() async throws -> AsyncStream<AudioChunk> {
        guard !isRecording else { throw CameraError.cannotRecord }
        updateRotation()
        let stream = try await engine.startRecording(to: TakeStorage.newFileURL())
        isRecording = true
        return stream
    }

    func stopRecording() async throws -> RecordingResult {
        guard isRecording else { throw CameraError.notRecording }
        isRecording = false
        return try await engine.stopRecording()
    }

    private func refreshAudioInputs() {
        let session = AVAudioSession.sharedInstance()
        audioInputs = (session.availableInputs ?? []).map { AudioInputOption(id: $0.uid, name: $0.portName) }
        selectedAudioInputID = session.preferredInput?.uid
    }

    private static func format(device: AVCaptureDevice, resolution: VideoResolution, frameRate: Int) -> AVCaptureDevice.Format? {
        let target = resolution.dimensions
        let matches = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == target.width && dimensions.height == target.height
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(frameRate) && $0.minFrameRate <= Double(frameRate) }
        }
        // Prefer full-range video, then the first match.
        let fullRange = matches.first { CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange }
        return fullRange ?? matches.first
    }

    private static func frameRates(device: AVCaptureDevice, resolution: VideoResolution) -> [Int] {
        [24, 25, 30, 60].filter { format(device: device, resolution: resolution, frameRate: $0) != nil }
    }
}

/// The preview surface: a view backed by `AVCaptureVideoPreviewLayer`.
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // The layer class above guarantees this cast.
        layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast
    }

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Camera preview")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// Owns the capture session and the movie writer. Everything here runs on `queue`;
/// sample buffers arrive there too, which is why the class is `@unchecked Sendable`.
final class CaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cue.capture")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    // Recording state, touched only on `queue`.
    private var writer: AVAssetWriter?
    private var writerVideo: AVAssetWriterInput?
    private var writerAudio: AVAssetWriterInput?
    private var firstTime: CMTime?
    private var lastTime: CMTime = .zero
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?
    private var captureRotation: CGFloat = 90

    func configure(device: UncheckedBox<AVCaptureDevice>, format: UncheckedBox<AVCaptureDevice.Format>?, frameRate: Int, mirrored: Bool, audio: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    try configureOnQueue(device: device.value, format: format?.value, frameRate: frameRate, mirrored: mirrored, audio: audio)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureOnQueue(device: AVCaptureDevice, format: AVCaptureDevice.Format?, frameRate: Int, mirrored: Bool, audio: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let videoInput { session.removeInput(videoInput) }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.noCamera }
        session.addInput(input)
        videoInput = input

        if audio, audioInput == nil, let microphone = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }

        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = false
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        if audioInput != nil, !session.outputs.contains(audioOutput), session.canAddOutput(audioOutput) {
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(audioOutput)
        }

        if let format {
            try device.lockForConfiguration()
            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
            if connection.isVideoRotationAngleSupported(captureRotation) {
                connection.videoRotationAngle = captureRotation
            }
        }
    }

    func startRunning() {
        queue.async { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stopRunning() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func setCaptureRotation(_ angle: CGFloat) {
        queue.async { [self] in
            // Changing rotation mid-take would rotate part of the movie; keep it fixed while writing.
            guard writer == nil else { return }
            captureRotation = angle
            if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    func startRecording(to url: URL) async throws -> AsyncStream<AudioChunk> {
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .bufferingNewest(64))
        try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                    let videoSettings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
                    let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                    video.expectsMediaDataInRealTime = true
                    guard writer.canAdd(video) else { throw CameraError.cannotRecord }
                    writer.add(video)
                    if audioInput != nil {
                        let audioSettings = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov)
                        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                        audio.expectsMediaDataInRealTime = true
                        if writer.canAdd(audio) {
                            writer.add(audio)
                            writerAudio = audio
                        }
                    }
                    self.writer = writer
                    writerVideo = video
                    firstTime = nil
                    audioContinuation = continuation
                    resume.resume()
                } catch {
                    resume.resume(throwing: error)
                }
            }
        }
        return stream
    }

    func stopRecording() async throws -> RecordingResult {
        try await withCheckedThrowingContinuation { (resume: CheckedContinuation<RecordingResult, any Error>) in
            queue.async { [self] in
                audioContinuation?.finish()
                audioContinuation = nil
                guard let writer, writer.status == .writing, let firstTime else {
                    self.writer = nil
                    resume.resume(throwing: CameraError.cannotRecord)
                    return
                }
                let duration = max(0, (lastTime - firstTime).seconds)
                writerVideo?.markAsFinished()
                writerAudio?.markAsFinished()
                let url = writer.outputURL
                let box = UncheckedBox(writer)
                writer.finishWriting { [self] in
                    queue.async { [self] in
                        self.writer = nil
                        writerVideo = nil
                        writerAudio = nil
                        if box.value.status == .completed {
                            resume.resume(returning: RecordingResult(url: url, duration: duration))
                        } else {
                            resume.resume(throwing: box.value.error ?? CameraError.cannotRecord)
                        }
                    }
                }
            }
        }
    }

    // MARK: Sample buffers (on `queue`)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let writer else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if output === videoOutput {
            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: time)
                firstTime = time
            }
            guard writer.status == .writing, let writerVideo, writerVideo.isReadyForMoreMediaData else { return }
            writerVideo.append(sampleBuffer)
            lastTime = time
        } else if output === audioOutput {
            if let pcm = Self.pcmBuffer(from: sampleBuffer) {
                audioContinuation?.yield(AudioChunk(buffer: pcm))
            }
            guard writer.status == .writing, let firstTime, time >= firstTime, let writerAudio, writerAudio.isReadyForMoreMediaData else { return }
            writerAudio.append(sampleBuffer)
        }
    }

    /// Copies a capture audio buffer into an `AVAudioPCMBuffer` for speech recognition.
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: streamDescription) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
