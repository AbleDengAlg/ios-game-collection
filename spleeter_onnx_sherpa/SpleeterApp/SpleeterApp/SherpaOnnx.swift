// SherpaOnnx.swift
// Source-separation subset of the sherpa-onnx Swift wrapper.
// Covers: AudioData, SourceSeparationConfig, SourceSeparator.
// Copyright (c) 2026 Xiaomi Corporation (adapted for SpleeterApp)

import Foundation
import AVFoundation

// MARK: - AudioData

/// Holds multi-channel float audio (channels interleaved flat: [ch0s0, ch0s1, …, ch1s0, …]).
struct AudioData {
    private enum Storage {
        case owned([Float])
        case wrapped(ManagedWave)
    }

    private class ManagedWave {
        let pointer: UnsafePointer<SherpaOnnxMultiChannelWave>
        init(_ p: UnsafePointer<SherpaOnnxMultiChannelWave>) { self.pointer = p }
        deinit { SherpaOnnxFreeMultiChannelWave(pointer) }
    }

    private let storage: Storage
    let channelCount: Int
    let samplesPerChannel: Int
    let sampleRate: Int

    /// Create from a flat interleaved sample array.
    init(samples: [Float], channelCount: Int, sampleRate: Int) {
        self.storage = .owned(samples)
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.samplesPerChannel = channelCount > 0 ? samples.count / channelCount : 0
    }

    /// Load from a WAV file path via the sherpa-onnx multi-channel reader.
    init?(filename: String) {
        guard let ptr = SherpaOnnxReadWaveMultiChannel(filename) else { return nil }
        self.storage = .wrapped(ManagedWave(ptr))
        self.channelCount = Int(ptr.pointee.num_channels)
        self.samplesPerChannel = Int(ptr.pointee.num_samples)
        self.sampleRate = Int(ptr.pointee.sample_rate)
    }

    /// Load from an AVAudioFile URL, resampling to targetSampleRate (stereo) if needed.
    /// Spleeter requires 2-channel (stereo) input at 44100 Hz.
    init?(url: URL, targetSampleRate: Int = 44100) {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let srcFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        // Output format: Float32, stereo (2ch), 44100 Hz — Spleeter requirement
        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(targetSampleRate),
            channels: 2,
            interleaved: false
        ) else { return nil }

        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount),
              let converter = AVAudioConverter(from: srcFormat, to: dstFormat)
        else { return nil }

        do { try audioFile.read(into: srcBuffer) } catch { return nil }

        let ratio = Double(targetSampleRate) / srcFormat.sampleRate
        let dstFrames = AVAudioFrameCount(Double(frameCount) * ratio + 1)
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: dstFrames) else { return nil }

        var convError: NSError?
        var inputDone = false
        let status = converter.convert(to: dstBuffer, error: &convError) { _, outStatus in
            if inputDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputDone = true
            return srcBuffer
        }

        guard status != .error, let channelData = dstBuffer.floatChannelData else { return nil }
        let n = Int(dstBuffer.frameLength)
        // ch0 + ch1 stored flat: [ch0s0, ch0s1, ..., ch1s0, ch1s1, ...]
        var flat = [Float](repeating: 0, count: 2 * n)
        flat.withUnsafeMutableBufferPointer { buf in
            (buf.baseAddress!).initialize(from: channelData[0], count: n)
            (buf.baseAddress! + n).initialize(from: channelData[1], count: n)
        }
        self.storage = .owned(flat)
        self.channelCount = 2
        self.samplesPerChannel = n
        self.sampleRate = targetSampleRate
    }

    func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Float>) -> R) -> R {
        switch storage {
        case .owned(let array):
            return array.withUnsafeBufferPointer(body)
        case .wrapped(let managed):
            let total = Int(managed.pointer.pointee.num_channels * managed.pointer.pointee.num_samples)
            return body(UnsafeBufferPointer(start: managed.pointer.pointee.samples[0], count: total))
        }
    }

    /// Save this AudioData as a WAV file at `filename`. Returns true on success.
    @discardableResult
    func save(to filename: String) -> Bool {
        return withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return false }
            var ptrs: [UnsafePointer<Float>?] = (0..<channelCount).map {
                UnsafePointer(base + ($0 * samplesPerChannel))
            }
            return SherpaOnnxWriteWaveMultiChannel(
                &ptrs,
                Int32(samplesPerChannel),
                Int32(sampleRate),
                Int32(channelCount),
                filename
            ) == 1
        }
    }
}

// MARK: - SourceSeparationConfig

struct SourceSeparationConfig {
    struct Spleeter {
        var vocals: String
        var accompaniment: String
    }

    var spleeter: Spleeter?
    var numThreads: Int = 2
    var debug: Bool = false
    var provider: String = "cpu"

    func withCConfig<R>(
        _ body: (UnsafePointer<SherpaOnnxOfflineSourceSeparationConfig>) -> R
    ) -> R {
        var cConfig = SherpaOnnxOfflineSourceSeparationConfig()
        cConfig.model.num_threads = Int32(numThreads)
        cConfig.model.debug = debug ? 1 : 0

        // Keep C strings alive for the duration of the call
        var storage: [String: [Int8]] = [:]
        func pin(_ key: String, _ value: String?) -> UnsafePointer<Int8>? {
            guard let v = value else { return nil }
            storage[key] = Array(v.utf8CString)
            return storage[key]!.withUnsafeBufferPointer { $0.baseAddress }
        }

        cConfig.model.provider = pin("provider", provider)
        cConfig.model.spleeter.vocals = pin("vocals", spleeter?.vocals)
        cConfig.model.spleeter.accompaniment = pin("accompaniment", spleeter?.accompaniment)

        return body(&cConfig)
    }
}

// MARK: - SourceSeparator

final class SourceSeparator {
    private var engine: OpaquePointer?

    init?(config: SourceSeparationConfig) {
        self.engine = config.withCConfig {
            SherpaOnnxCreateOfflineSourceSeparation($0)
        }
        if engine == nil { return nil }
    }

    deinit {
        if let e = engine {
            SherpaOnnxDestroyOfflineSourceSeparation(e)
        }
    }

    /// Run source separation. Returns an array of AudioData stems (index 0 = vocals, 1 = accompaniment).
    func process(buffer: AudioData) -> [AudioData]? {
        guard let engine = engine else { return nil }

        return buffer.withUnsafeBufferPointer { flatBuf in
            guard let base = flatBuf.baseAddress else { return nil }
            var ptrs: [UnsafePointer<Float>?] = (0..<buffer.channelCount).map {
                UnsafePointer(base + ($0 * buffer.samplesPerChannel))
            }

            guard let raw = SherpaOnnxOfflineSourceSeparationProcess(
                engine,
                &ptrs,
                Int32(buffer.channelCount),
                Int32(buffer.samplesPerChannel),
                Int32(buffer.sampleRate)
            ) else { return nil }

            let stemCount = Int(raw.pointee.num_stems)
            let result = (0..<stemCount).map { i -> AudioData in
                let stem = raw.pointee.stems[i]
                let chs = Int(stem.num_channels)
                let n = Int(stem.n)
                var flat = [Float](repeating: 0, count: chs * n)
                for c in 0..<chs {
                    if let src = stem.samples[c] {
                        let offset = c * n
                        flat.withUnsafeMutableBufferPointer { dest in
                            (dest.baseAddress! + offset).initialize(from: src, count: n)
                        }
                    }
                }
                return AudioData(
                    samples: flat,
                    channelCount: chs,
                    sampleRate: Int(raw.pointee.sample_rate)
                )
            }

            SherpaOnnxDestroySourceSeparationOutput(raw)
            return result
        }
    }
}
