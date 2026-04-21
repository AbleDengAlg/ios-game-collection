// AudioPlayer.swift
// Lightweight AVAudioPlayer wrapper — works on both iOS and macOS.
// Writes the stem to a temp WAV file then initialises AVAudioPlayer.

import AVFoundation
import Combine

@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false

    private var player: AVAudioPlayer?
    private var tempURL: URL?

    // MARK: - Play

    /// Render `data` into a temporary WAV file and start playback.
    func play(data: AudioData) {
        stop()

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard data.save(to: tmp.path) else { return }
        tempURL = tmp

        do {
#if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
#endif
            let p = try AVAudioPlayer(contentsOf: tmp)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
        } catch {
            print("AudioPlayer error: \(error)")
            cleanup()
        }
    }

    // MARK: - Stop

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        cleanup()
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.player = nil
            self.cleanup()
        }
    }

    // MARK: - Private

    private func cleanup() {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
    }
}
