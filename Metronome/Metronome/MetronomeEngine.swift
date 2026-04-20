import AVFoundation
import Combine

class MetronomeEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var currentBeat: Int = -1   // -1 = stopped, 0-3 = beat index
    @Published var bpm: Double = 120
    @Published var volume: Float = 10      // 0-20

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var rimBuffer: AVAudioPCMBuffer?
    private var cowbellBuffer: AVAudioPCMBuffer?
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "metronome.tick", qos: .userInteractive)

    // MARK: - Init

    init() {
        setupAudioSession()
        setupAudioEngine()
        loadSounds()
    }

    deinit {
        stop()
    }

    // MARK: - Audio Setup

    private func setupAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func setupAudioEngine() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        try? audioEngine.start()
    }

    // MARK: - Load Sounds

    private func loadSounds() {
        rimBuffer = loadPCMBuffer(resource: "rim", extension: "raw")
        cowbellBuffer = loadPCMBuffer(resource: "cowbell", extension: "raw")
    }

    private func loadPCMBuffer(resource name: String, extension ext: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url) else {
            print("Failed to load \(name).\(ext)")
            return nil
        }

        let sampleCount = data.count / 2
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return nil
        }

        data.withUnsafeBytes { rawPtr in
            if let base = rawPtr.baseAddress {
                let ptr = base.assumingMemoryBound(to: Int16.self)
                for i in 0..<sampleCount {
                    buffer.floatChannelData![0][i] = Float(ptr[i]) / 32767.0
                }
            }
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        return buffer
    }

    // MARK: - Playback Control

    func togglePlay() {
        if isPlaying { stop() } else { start() }
    }

    func start() {
        guard !isPlaying, rimBuffer != nil, cowbellBuffer != nil else { return }

        isPlaying = true
        currentBeat = 0
        playerNode.play()
        playCurrentBeat()
        startTimer()
    }

    func stop() {
        isPlaying = false
        currentBeat = -1
        timer?.cancel()
        timer = nil
        playerNode.stop()
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.cancel()
        let interval = 60.0 / bpm
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))
        timer?.setEventHandler { [weak self] in
            guard let self, self.isPlaying else { return }
            let next = (self.currentBeat + 1) % 4
            self.playBeat(next)
            DispatchQueue.main.async {
                self.currentBeat = next
            }
        }
        timer?.resume()
    }

    // MARK: - Beat Playback

    private func playCurrentBeat() {
        playBeat(currentBeat)
    }

    private func playBeat(_ beat: Int) {
        let buffer = beat == 0 ? rimBuffer : cowbellBuffer
        guard let buffer else { return }
        playerNode.volume = volume / 20.0
        playerNode.scheduleBuffer(buffer, at: nil, options: [])
    }

    // MARK: - Parameter Updates

    func setBPM(_ value: Double) {
        bpm = value
        if isPlaying { startTimer() }
    }

    func setVolume(_ value: Float) {
        volume = value
        if isPlaying { playerNode.volume = value / 20.0 }
    }
}
