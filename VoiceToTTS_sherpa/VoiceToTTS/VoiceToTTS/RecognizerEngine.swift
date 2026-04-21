// RecognizerEngine.swift
// Manages the streaming ASR recognizer: model loading, audio feeding, result publishing.
// Runs inference on a background actor; publishes text back to @MainActor for UI.

import Foundation
import AVFoundation

// MARK: - Engine State

enum RecognizerState: Equatable {
    case idle
    case loading
    case listening
    case recognizing
    case error(String)

    static func == (lhs: RecognizerState, rhs: RecognizerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.listening, .listening), (.recognizing, .recognizing):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Recognized Message

struct RecognizedMessage: Identifiable {
    let id: UUID
    let text: String
    let isFinal: Bool
    let timestamp: Date

    init(id: UUID = UUID(), text: String, isFinal: Bool, timestamp: Date) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
        self.timestamp = timestamp
    }
}

// MARK: - RecognizerEngine

@MainActor
final class RecognizerEngine: ObservableObject {
    @Published var state: RecognizerState = .idle
    @Published var messages: [RecognizedMessage] = []
    @Published var currentText: String = ""

    private var recognizer: SherpaOnnxRecognizer?
    private let recorder = AudioRecorder()

    // Track the latest incomplete message so we can update it in-place
    private var currentMessageID: UUID?

    // MARK: - Load Model

    func load() {
        guard recognizer == nil else { return }
        state = .loading

        guard
            let modelPath = Bundle.main.path(forResource: "model.int8", ofType: "onnx"),
            let tokensPath = Bundle.main.path(forResource: "tokens", ofType: "txt")
        else {
            state = .error("Model files not found in app bundle.\nPlease add model.int8.onnx and tokens.txt to Copy Bundle Resources.")
            return
        }

        // Optional: bbpe.model may be needed for some models
        let bpePath = Bundle.main.path(forResource: "bbpe", ofType: "model") ?? ""

        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        let zipformerConfig = sherpaOnnxOnlineZipformer2CtcModelConfig(model: modelPath)
        let modelConfig = sherpaOnnxOnlineModelConfig(
            tokens: tokensPath,
            zipformer2Ctc: zipformerConfig,
            numThreads: 2,
            provider: "cpu",
            debug: 0,
            bpeVocab: bpePath
        )

        var config = sherpaOnnxOnlineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            enableEndpoint: true,
            rule1MinTrailingSilence: 2.4,
            rule2MinTrailingSilence: 1.2,
            rule3MinUtteranceLength: 30,
            decodingMethod: "greedy_search",
            maxActivePaths: 4
        )

        recognizer = SherpaOnnxRecognizer(config: &config)
        state = .idle
    }

    // MARK: - Start/Stop Listening

    func startListening() async {
        guard let recognizer = recognizer else {
            state = .error("Model not loaded. Call load() first.")
            return
        }

        let granted = await recorder.requestPermission()
        guard granted else {
            state = .error("Microphone permission denied. Please enable it in Settings.")
            return
        }

        // Reset recognizer state for a new session
        recognizer.reset()
        currentText = ""
        currentMessageID = nil
        state = .listening

        recorder.startRecording { [weak self] samples in
            guard let self = self else { return }
            Task { @MainActor in
                self.processAudioChunk(samples: samples)
            }
        }
    }

    func stopListening() {
        recorder.stopRecording()
        recognizer?.inputFinished()

        // Final decode pass
        if let recognizer = recognizer {
            while recognizer.isReady() {
                recognizer.decode()
            }
            if let result = recognizer.getResult() {
                let text = result.text
                if !text.isEmpty {
                    self.finalizeCurrentText(text)
                }
            }
        }

        state = .idle
        currentText = ""
        currentMessageID = nil
    }

    // MARK: - Process Audio Chunk

    private func processAudioChunk(samples: [Float]) {
        guard let recognizer = recognizer else { return }
        guard state == .listening || state == .recognizing else { return }

        recognizer.acceptWaveform(samples: samples, sampleRate: 16000)

        // Decode while ready
        while recognizer.isReady() {
            recognizer.decode()
        }

        // Get incremental result
        if let result = recognizer.getResult() {
            let text = result.text
            if !text.isEmpty {
                self.currentText = text
                self.updateOrCreateMessage(text: text, isFinal: false)
            }
        }

        // Check endpoint — user stopped speaking
        if recognizer.isEndpoint() {
            // Finalize the current utterance
            if let result = recognizer.getResult() {
                let text = result.text
                if !text.isEmpty {
                    self.finalizeCurrentText(text)
                }
            }
            // Reset for next utterance
            recognizer.reset()
            currentText = ""
            currentMessageID = nil
        }
    }

    // MARK: - Message Management

    private func updateOrCreateMessage(text: String, isFinal: Bool) {
        if let id = currentMessageID,
           let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = RecognizedMessage(id: id, text: text, isFinal: isFinal, timestamp: messages[index].timestamp)
        } else {
            let newMsg = RecognizedMessage(text: text, isFinal: isFinal, timestamp: Date())
            currentMessageID = newMsg.id
            messages.append(newMsg)
        }
    }

    private func finalizeCurrentText(_ text: String) {
        if let id = currentMessageID,
           let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = RecognizedMessage(id: id, text: text, isFinal: true, timestamp: messages[index].timestamp)
        } else if !text.isEmpty {
            let newMsg = RecognizedMessage(text: text, isFinal: true, timestamp: Date())
            messages.append(newMsg)
        }
        currentMessageID = nil
        currentText = ""
    }

    // MARK: - Clear

    func clearMessages() {
        messages.removeAll()
        currentText = ""
        currentMessageID = nil
    }

    var errorMessage: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }
}
