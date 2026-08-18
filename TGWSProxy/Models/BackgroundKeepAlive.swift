import Foundation
import AVFoundation

/// Keeps the app alive in the background while the proxy is running.
///
/// iOS suspends apps shortly after they enter the background unless a supported
/// background mode is active. The practical, sideload-friendly approach used by
/// many proxy/VPN-style tools is the `audio` background mode with a looping
/// silent audio stream. This class configures the audio session for playback
/// and plays an endless silent buffer so the process stays alive and the local
/// proxy keeps serving connections.
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let queue = DispatchQueue(label: "tgws.backgroundKeepAlive", qos: .userInitiated)
    private var isRunning = false

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Starts the silent audio keep-alive loop.
    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            do {
                try AVAudioSession.sharedInstance().setCategory(
                    .playback,
                    mode: .default,
                    options: [.mixWithOthers]
                )
                try AVAudioSession.sharedInstance().setActive(true)
                try self.engine.start()
                self.scheduleSilence()
                self.player.play()
                self.isRunning = true
                Log.debug("Фоновый keep-alive запущен")
            } catch {
                Log.warning("Фоновый keep-alive не удался: \(error.localizedDescription)")
                self.isRunning = false
            }
        }
    }

    /// Stops the silent audio keep-alive loop.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.player.stop()
            self.engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self.isRunning = false
            Log.debug("Фоновый keep-alive остановлен")
        }
    }

    /// Schedules 10 seconds of silence, re-scheduling itself endlessly.
    private func scheduleSilence() {
        let frameCount = AVAudioFrameCount(format.sampleRate * 10)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        // The buffer is zero-filled (silence) by default; no audio is audible.
        player.scheduleBuffer(buffer) { [weak self] in
            self?.scheduleSilence()
        }
    }
}