// SeparatorEngine.swift
// Owns the SourceSeparator and runs inference on a background actor.
// Publishes results back to @MainActor for the UI.

import Foundation
import AVFoundation

// MARK: - EngineError

struct EngineError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

// MARK: - EngineState

enum EngineState: Equatable {
    case idle
    case loading
    case separating
    case done
    case error(String)

    static func == (lhs: EngineState, rhs: EngineState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.separating, .separating), (.done, .done):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - SeparatorEngine

@MainActor
final class SeparatorEngine: ObservableObject {
    @Published var state: EngineState = .idle
    @Published var vocalsData: AudioData?
    @Published var accompanimentData: AudioData?

    private var separator: SourceSeparator?

    // MARK: Load model

    /// Initialise the SourceSeparator from bundle ONNX resources.
    /// Must be called once before `separate(url:)`.
    func load() {
        guard separator == nil else { return }
        state = .loading

        guard
            let vocalsPath = Bundle.main.path(forResource: "vocals.int8", ofType: "onnx"),
            let accompanimentPath = Bundle.main.path(forResource: "accompaniment.int8", ofType: "onnx")
        else {
            state = .error("ONNX model files not found in app bundle.\nPlease add vocals.int8.onnx and accompaniment.int8.onnx to Copy Bundle Resources.")
            return
        }

        let config = SourceSeparationConfig(
            spleeter: .init(vocals: vocalsPath, accompaniment: accompanimentPath),
            numThreads: 2,
            debug: false,
            provider: "cpu"
        )

        guard let sep = SourceSeparator(config: config) else {
            state = .error("Failed to initialise SourceSeparator. Check ONNX model integrity.")
            return
        }

        separator = sep
        state = .idle
    }

    // MARK: Separate

    /// Read the WAV at `url`, resample to 16 kHz mono, run Spleeter, publish stems.
    func separate(url: URL) async {
        guard let sep = separator else {
            state = .error("Model not loaded. Call load() first.")
            return
        }

        state = .separating
        vocalsData = nil
        accompanimentData = nil

        // Open security-scoped resource on main actor before jumping to background
        let accessed = url.startAccessingSecurityScopedResource()

        // Load & resample audio on main actor — stereo 44100 Hz as required by Spleeter
        guard let audio = AudioData(url: url, targetSampleRate: 44100) else {
            if accessed { url.stopAccessingSecurityScopedResource() }
            state = .error("Could not read / resample audio file.\nSupported format: WAV (any sample rate).")
            return
        }

        // Release security scope after we've read the file into memory
        if accessed { url.stopAccessingSecurityScopedResource() }

        // Run heavy inference on a background thread
        let result: Result<[AudioData], EngineError> = await Task.detached(priority: .userInitiated) {
            guard let stems = sep.process(buffer: audio) else {
                return .failure(EngineError("Spleeter inference failed. File may be too short or corrupted."))
            }
            guard stems.count >= 2 else {
                return .failure(EngineError("Expected 2 stems (vocals + accompaniment), got \(stems.count)."))
            }
            return .success(stems)
        }.value

        switch result {
        case .success(let stems):
            vocalsData = stems[0]
            accompanimentData = stems[1]
            state = .done
        case .failure(let err):
            state = .error(err.message)
        }
    }

    // MARK: Reset

    func reset() {
        state = .idle
        vocalsData = nil
        accompanimentData = nil
    }

    // MARK: Error helper

    var errorMessage: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }
}
