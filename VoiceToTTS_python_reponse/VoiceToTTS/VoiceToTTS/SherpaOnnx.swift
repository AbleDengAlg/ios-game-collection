// SherpaOnnx.swift
// Streaming ASR wrapper for sherpa-onnx C API.
// Adapted from swift-api-examples for VoiceToTTS.

import Foundation

// MARK: - Helpers

private func toCPointer(_ s: String) -> UnsafePointer<Int8>! {
    let cs = (s as NSString).utf8String
    return UnsafePointer<Int8>(cs)
}

// MARK: - Config Builders

func sherpaOnnxOnlineZipformer2CtcModelConfig(model: String = "") -> SherpaOnnxOnlineZipformer2CtcModelConfig {
    return SherpaOnnxOnlineZipformer2CtcModelConfig(model: toCPointer(model))
}

func sherpaOnnxOnlineModelConfig(
    tokens: String,
    zipformer2Ctc: SherpaOnnxOnlineZipformer2CtcModelConfig = sherpaOnnxOnlineZipformer2CtcModelConfig(),
    numThreads: Int = 2,
    provider: String = "cpu",
    debug: Int = 0,
    modelType: String = "",
    modelingUnit: String = "cjkchar",
    bpeVocab: String = ""
) -> SherpaOnnxOnlineModelConfig {
    return SherpaOnnxOnlineModelConfig(
        transducer: sherpaOnnxOnlineTransducerModelConfig(),
        paraformer: sherpaOnnxOnlineParaformerModelConfig(),
        zipformer2_ctc: zipformer2Ctc,
        tokens: toCPointer(tokens),
        num_threads: Int32(numThreads),
        provider: toCPointer(provider),
        debug: Int32(debug),
        model_type: toCPointer(modelType),
        modeling_unit: toCPointer(modelingUnit),
        bpe_vocab: toCPointer(bpeVocab),
        tokens_buf: toCPointer(""),
        tokens_buf_size: 0,
        nemo_ctc: sherpaOnnxOnlineNemoCtcModelConfig(),
        t_one_ctc: sherpaOnnxOnlineToneCtcModelConfig()
    )
}

func sherpaOnnxOnlineTransducerModelConfig(encoder: String = "", decoder: String = "", joiner: String = "") -> SherpaOnnxOnlineTransducerModelConfig {
    return SherpaOnnxOnlineTransducerModelConfig(encoder: toCPointer(encoder), decoder: toCPointer(decoder), joiner: toCPointer(joiner))
}

func sherpaOnnxOnlineParaformerModelConfig(encoder: String = "", decoder: String = "") -> SherpaOnnxOnlineParaformerModelConfig {
    return SherpaOnnxOnlineParaformerModelConfig(encoder: toCPointer(encoder), decoder: toCPointer(decoder))
}

func sherpaOnnxOnlineNemoCtcModelConfig(model: String = "") -> SherpaOnnxOnlineNemoCtcModelConfig {
    return SherpaOnnxOnlineNemoCtcModelConfig(model: toCPointer(model))
}

func sherpaOnnxOnlineToneCtcModelConfig(model: String = "") -> SherpaOnnxOnlineToneCtcModelConfig {
    return SherpaOnnxOnlineToneCtcModelConfig(model: toCPointer(model))
}

func sherpaOnnxFeatureConfig(sampleRate: Int = 16000, featureDim: Int = 80) -> SherpaOnnxFeatureConfig {
    return SherpaOnnxFeatureConfig(sample_rate: Int32(sampleRate), feature_dim: Int32(featureDim))
}

func sherpaOnnxOnlineRecognizerConfig(
    featConfig: SherpaOnnxFeatureConfig,
    modelConfig: SherpaOnnxOnlineModelConfig,
    enableEndpoint: Bool = true,
    rule1MinTrailingSilence: Float = 2.4,
    rule2MinTrailingSilence: Float = 1.2,
    rule3MinUtteranceLength: Float = 30,
    decodingMethod: String = "greedy_search",
    maxActivePaths: Int = 4
) -> SherpaOnnxOnlineRecognizerConfig {
    return SherpaOnnxOnlineRecognizerConfig(
        feat_config: featConfig,
        model_config: modelConfig,
        decoding_method: toCPointer(decodingMethod),
        max_active_paths: Int32(maxActivePaths),
        enable_endpoint: enableEndpoint ? 1 : 0,
        rule1_min_trailing_silence: rule1MinTrailingSilence,
        rule2_min_trailing_silence: rule2MinTrailingSilence,
        rule3_min_utterance_length: rule3MinUtteranceLength,
        hotwords_file: toCPointer(""),
        hotwords_score: 1.5,
        ctc_fst_decoder_config: SherpaOnnxOnlineCtcFstDecoderConfig(graph: toCPointer(""), max_active: 3000),
        rule_fsts: toCPointer(""),
        rule_fars: toCPointer(""),
        blank_penalty: 0.0,
        hotwords_buf: toCPointer(""),
        hotwords_buf_size: 0,
        hr: SherpaOnnxHomophoneReplacerConfig(dict_dir: toCPointer(""), lexicon: toCPointer(""), rule_fsts: toCPointer(""))
    )
}

// MARK: - Recognition Result

class SherpaOnnxOnlineRecognitionResult {
    private let result: UnsafePointer<SherpaOnnxOnlineRecognizerResult>

    private lazy var _text: String = {
        guard let cstr = result.pointee.text else { return "" }
        return String(cString: cstr)
    }()

    var text: String { _text }

    init(result: UnsafePointer<SherpaOnnxOnlineRecognizerResult>) {
        self.result = result
    }

    deinit {
        SherpaOnnxDestroyOnlineRecognizerResult(result)
    }
}

// MARK: - Recognizer

class SherpaOnnxRecognizer {
    private let recognizer: OpaquePointer
    private var stream: OpaquePointer
    private let lock = NSLock()

    init(config: UnsafePointer<SherpaOnnxOnlineRecognizerConfig>) {
        self.recognizer = SherpaOnnxCreateOnlineRecognizer(config)
        self.stream = SherpaOnnxCreateOnlineStream(recognizer)
    }

    deinit {
        SherpaOnnxDestroyOnlineStream(stream)
        SherpaOnnxDestroyOnlineRecognizer(recognizer)
    }

    func acceptWaveform(samples: [Float], sampleRate: Int = 16000) {
        SherpaOnnxOnlineStreamAcceptWaveform(stream, Int32(sampleRate), samples, Int32(samples.count))
    }

    func isReady() -> Bool {
        return SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0
    }

    func decode() {
        SherpaOnnxDecodeOnlineStream(recognizer, stream)
    }

    func getResult() -> SherpaOnnxOnlineRecognitionResult? {
        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else { return nil }
        return SherpaOnnxOnlineRecognitionResult(result: result)
    }

    func isEndpoint() -> Bool {
        return SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0
    }

    func reset() {
        SherpaOnnxOnlineStreamReset(recognizer, stream)
    }

    func inputFinished() {
        SherpaOnnxOnlineStreamInputFinished(stream)
    }
}
