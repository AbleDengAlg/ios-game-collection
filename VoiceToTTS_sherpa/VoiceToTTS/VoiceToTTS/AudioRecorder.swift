// AudioRecorder.swift
// Real-time microphone capture at 16 kHz mono using AVAudioEngine.
// Feeds audio chunks to a callback for streaming ASR.

import AVFoundation
import Combine

@MainActor
final class AudioRecorder: ObservableObject {
    @Published var isRecording = false

    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var onAudioChunk: (([Float]) -> Void)?

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Start Recording

    func startRecording(onChunk: @escaping ([Float]) -> Void) {
        guard !isRecording else { return }

        self.onAudioChunk = onChunk

        // 1. Configure audio session FIRST — input format depends on this
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("AudioRecorder: Session error: \(error)")
            return
        }

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        self.inputNode = inputNode

        // 2. Query input format AFTER session is active
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("AudioRecorder: Input format: \(inputFormat)")

        // Guard against invalid simulator format (sampleRate == 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            print("AudioRecorder: Invalid input format — sampleRate or channelCount is zero. Is a microphone available?")
            return
        }

        // Target format: 16kHz mono Float32 — required by the ASR model
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            print("AudioRecorder: Failed to create target format")
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("AudioRecorder: Failed to create converter from \(inputFormat) to \(targetFormat)")
            return
        }

        // Install tap on input node to capture microphone data
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Convert to 16kHz mono
            guard let converted = self.convert(buffer: buffer, converter: converter) else { return }
            guard let channelData = converted.floatChannelData else { return }

            let frameLength = Int(converted.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

            DispatchQueue.main.async {
                self.onAudioChunk?(samples)
            }
        }

        do {
            try engine.start()
            isRecording = true
        } catch {
            print("AudioRecorder: Engine start error: \(error)")
        }
    }

    // MARK: - Stop Recording

    func stopRecording() {
        guard isRecording else { return }
        engine?.stop()
        inputNode?.removeTap(onBus: 0)
        engine = nil
        inputNode = nil
        onAudioChunk = nil
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("AudioRecorder: Session deactivate error: \(error)")
        }
    }

    // MARK: - Format Conversion

    private func convert(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let inputFormat = buffer.format
        let outputFormat = converter.outputFormat

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: estimatedFrames) else {
            return nil
        }

        var error: NSError?
        var inputDone = false

        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputDone = true
            return buffer
        }

        guard status != .error else {
            if let err = error { print("AudioRecorder: Conversion error: \(err)") }
            return nil
        }

        return outputBuffer
    }
}
