import Foundation
import AVFoundation
import Combine

@MainActor
public final class AudioRecorder: NSObject, ObservableObject {
    @Published public var isRecording = false
    @Published public var elapsedTime: TimeInterval = 0
    @Published public var permissionDenied = false

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStart: Date?
    public private(set) var currentFileName: String?

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

        let fileName = "\(UUID().uuidString).m4a"
        let fileURL = AudioFileStore.shared.url(for: fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            currentFileName = fileName
            recordingStart = Date()
            isRecording = true
            elapsedTime = 0
            startTimer()
        } catch {
            print("Failed to start recording: \(error)")
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

    @discardableResult
    public func stopRecording() -> (fileName: String, duration: TimeInterval)? {
        guard isRecording, let fileName = currentFileName else { return nil }
        audioRecorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif

        let duration = elapsedTime
        currentFileName = nil
        recordingStart = nil
        return (fileName, duration)
    }

    public func cancelRecording() {
        guard let fileName = currentFileName else { return }
        audioRecorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        AudioFileStore.shared.delete(fileName: fileName)
        currentFileName = nil
        recordingStart = nil
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
