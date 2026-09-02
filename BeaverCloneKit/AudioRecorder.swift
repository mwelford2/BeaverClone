import Foundation
import AVFoundation
import Combine

/// One completed slice of a live recording. `fileName` holds just that slice's audio;
/// `startOffset` is where it begins within the eventual full recording, so per-word
/// timestamps returned by transcribing this slice alone can be shifted into the timeline
/// of the final, concatenated file.
public struct RecordingSegment: Equatable {
    public let fileName: String
    public let startOffset: TimeInterval
    public let duration: TimeInterval
}

/// Records in a sequence of short segments instead of one continuous file, so audio can be
/// handed off for transcription while recording is still in progress ("live" transcription).
/// Segment boundaries aren't fixed-interval: recording keeps going a little past the target
/// length until it detects a brief pause in speech (via input metering), so cuts land between
/// words/phrases rather than mid-word. Segments are stitched back into one file on stop.
@MainActor
public final class AudioRecorder: NSObject, ObservableObject {
    @Published public var isRecording = false
    @Published public var elapsedTime: TimeInterval = 0
    @Published public var permissionDenied = false

    /// Fires each time a segment finishes (either by hitting the silence/duration cutoff, or
    /// the final flush on stop). Consumers should transcribe it and append to a running transcript.
    public var onSegmentFinished: ((RecordingSegment) -> Void)?

    /// Target segment length before we start listening for a quiet moment to cut on.
    private let targetSegmentDuration: TimeInterval = 12
    /// Hard cap so a continuously-loud recording still gets chunked.
    private let maxSegmentDuration: TimeInterval = 18
    /// How long input level must stay below the silence threshold before we treat it as a pause.
    private let silenceHoldDuration: TimeInterval = 0.3
    /// Average-power threshold (dBFS) below which we consider the input "quiet."
    private let silenceThresholdDB: Float = -35

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var meterTimer: Timer?
    private var recordingStart: Date?
    private var segmentStart: Date?
    private var segmentStartOffset: TimeInterval = 0
    private var quietSince: Date?
    public private(set) var currentFileName: String?
    private(set) var segments: [RecordingSegment] = []

    public override init() {
        super.init()
    }

    public func requestPermission(completion: @escaping (Bool) -> Void) {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
        #endif
    }

    public func startRecording() {
        requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.permissionDenied = true
                return
            }
            self.beginRecording()
        }
    }

    private func beginRecording() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
            return
        }
        #endif

        segments = []
        recordingStart = Date()
        segmentStartOffset = 0
        isRecording = true
        elapsedTime = 0
        startTimer()
        startNewSegment()
    }

    private func startNewSegment() {
        let fileURL = AudioFileStore.shared.newRecordingURL()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.record()
            audioRecorder = recorder
            currentFileName = fileURL.lastPathComponent
            segmentStart = Date()
            quietSince = nil
            startMeterTimer()
        } catch {
            print("Failed to start recording segment: \(error)")
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.recordingStart else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    /// Polls input level to (a) detect a quiet moment once we're past the target segment
    /// length, and (b) enforce the hard max length regardless of quiet.
    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSegmentCutoff()
            }
        }
    }

    private func checkSegmentCutoff() {
        guard let recorder = audioRecorder, let segmentStart else { return }
        let elapsed = Date().timeIntervalSince(segmentStart)

        if elapsed >= maxSegmentDuration {
            cutSegment()
            return
        }

        guard elapsed >= targetSegmentDuration else { return }

        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)

        if power < silenceThresholdDB {
            let now = Date()
            let since = quietSince ?? now
            if quietSince == nil { quietSince = now }
            if now.timeIntervalSince(since) >= silenceHoldDuration {
                cutSegment()
            }
        } else {
            quietSince = nil
        }
    }

    /// Finishes the current segment file and immediately starts the next one, with no gap
    /// long enough to be perceptible — recording never actually stops until the user stops it.
    private func cutSegment() {
        guard isRecording, let recorder = audioRecorder, let fileName = currentFileName, let segmentStart else { return }
        meterTimer?.invalidate()
        meterTimer = nil

        let duration = Date().timeIntervalSince(segmentStart)
        recorder.stop()

        let segment = RecordingSegment(fileName: fileName, startOffset: segmentStartOffset, duration: duration)
        segments.append(segment)
        segmentStartOffset += duration
        onSegmentFinished?(segment)

        startNewSegment()
    }

    @discardableResult
    public func stopRecording() -> (segments: [RecordingSegment], duration: TimeInterval)? {
        guard isRecording else { return nil }
        meterTimer?.invalidate()
        meterTimer = nil
        timer?.invalidate()
        timer = nil

        if let recorder = audioRecorder, let fileName = currentFileName, let segmentStart {
            let duration = Date().timeIntervalSince(segmentStart)
            recorder.stop()
            if duration > 0.1 {
                let segment = RecordingSegment(fileName: fileName, startOffset: segmentStartOffset, duration: duration)
                segments.append(segment)
                onSegmentFinished?(segment)
            }
        }

        isRecording = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif

        let finishedSegments = segments
        let totalDuration = elapsedTime
        currentFileName = nil
        recordingStart = nil
        segmentStart = nil
        segments = []
        return (finishedSegments, totalDuration)
    }

    public func cancelRecording() {
        guard isRecording else { return }
        meterTimer?.invalidate()
        meterTimer = nil
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        isRecording = false

        if let fileName = currentFileName {
            AudioFileStore.shared.delete(fileName: fileName)
        }
        for segment in segments {
            AudioFileStore.shared.delete(fileName: segment.fileName)
        }

        currentFileName = nil
        recordingStart = nil
        segmentStart = nil
        segments = []
        elapsedTime = 0
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
}
