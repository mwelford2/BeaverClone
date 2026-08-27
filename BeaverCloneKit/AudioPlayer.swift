import Foundation
import AVFoundation
import Combine

@MainActor
public final class AudioPlayer: NSObject, ObservableObject {
    @Published public var isPlaying = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    public override init() {
        super.init()
    }

    public func load(fileName: String) {
        let url = AudioFileStore.shared.url(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            print("Failed to load audio: \(error)")
        }
    }

    public func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    public func seekAndPlay(to time: TimeInterval) {
        seek(to: time)
        if !isPlaying {
            play()
        }
    }

    public func stop() {
        player?.stop()
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = self.player?.currentTime ?? 0
            }
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.timer?.invalidate()
        }
    }
}
