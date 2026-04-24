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
    let isUser: Bool

    init(id: UUID = UUID(), text: String, isFinal: Bool, timestamp: Date, isUser: Bool = true) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
        self.timestamp = timestamp
        self.isUser = isUser
    }
}

// MARK: - RecognizerEngine

@MainActor
final class RecognizerEngine: ObservableObject {
    @Published var state: RecognizerState = .idle
    @Published var messages: [RecognizedMessage] = []
    @Published var currentText: String = ""
    @Published var draftText: String = ""
    @Published var isSending: Bool = false
    @Published var serverURL: String = ""
    @Published var apiToken: String = ""

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
        draftText = ""
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

        // Get incremental result — show in draft text for user to preview and edit
        if let result = recognizer.getResult() {
            let text = result.text
            if !text.isEmpty {
                self.currentText = text
                self.draftText = text
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
        draftText = text
        currentMessageID = nil
        currentText = ""
    }

    // MARK: - Server Communication

    func sendDraft() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        guard !serverURL.isEmpty else {
            addServerMessage(text: "⚠️ 请先在上方输入服务器地址")
            return
        }

        // Add user message to chat
        let userMsg = RecognizedMessage(text: text, isFinal: true, timestamp: Date(), isUser: true)
        messages.append(userMsg)

        // Clear draft
        draftText = ""

        // Send to AI server
        sendToServer(text: text)
    }

    private func sendToServer(text: String) {
        guard !serverURL.isEmpty,
              let url = URL(string: serverURL + "/send_msg") else { return }

        isSending = true

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 130
        sessionConfig.timeoutIntervalForResource = 130
        let session = URLSession(configuration: sessionConfig)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiToken.isEmpty {
            request.setValue(apiToken, forHTTPHeaderField: "X-API-Token")
        }
        let body: [String: String] = ["message": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            defer {
                Task { @MainActor [weak self] in
                    self?.isSending = false
                }
            }

            if let error = error as NSError? {
                let msg: String
                switch error.code {
                case NSURLErrorTimedOut:
                    msg = "❌ 请求超时：AI 响应超过 130 秒"
                case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                    msg = "❌ 连接失败：无法连接到服务器"
                default:
                    msg = "❌ 网络错误：\(error.localizedDescription)"
                }
                Task { @MainActor [weak self] in
                    self?.addServerMessage(text: msg)
                }
                return
            }

            guard let data = data else {
                Task { @MainActor [weak self] in
                    self?.addServerMessage(text: "❌ 未收到服务器数据")
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let code = json["code"] as? Int
                    let aiReply = json["后端回复"] as? String
                    let errorMsg = json["error"] as? String

                    if code == 200, let reply = aiReply {
                        Task { @MainActor [weak self] in
                            self?.addServerMessage(text: reply)
                        }
                    } else {
                        let err = errorMsg ?? "未知错误 (code: \(code ?? -1))"
                        Task { @MainActor [weak self] in
                            self?.addServerMessage(text: "⚠️ 服务端错误：\(err)")
                        }
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.addServerMessage(text: "❌ 无法解析服务器响应")
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.addServerMessage(text: "❌ JSON 解析失败")
                }
            }
        }.resume()
    }

    private func addServerMessage(text: String) {
        let msg = RecognizedMessage(text: text, isFinal: true, timestamp: Date(), isUser: false)
        messages.append(msg)
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
