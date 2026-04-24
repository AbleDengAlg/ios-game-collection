# VoiceToTTS Tutorial — Offline Chinese Speech Recognition with sherpa-onnx

> Learn to build an iOS offline voice-to-text app using SwiftUI, AVAudioEngine, and sherpa-onnx streaming ASR.

---

## Section 1: Project Overview (项目总览)

### File Tree

```
VoiceToTTS/
|-- VoiceToTTSApp.swift              # App entry point — launches ContentView
|-- ContentView.swift                # Main SwiftUI screen — chat UI, mic button
|-- RecognizerEngine.swift           # Core engine — loads model, processes audio, publishes text
|-- AudioRecorder.swift              # Microphone capture — 16kHz mono conversion
|-- SherpaOnnx.swift                 # C API wrapper — config builders + recognizer class
|-- SherpaOnnx-Bridging-Header.h     # Exposes sherpa-onnx/c-api/c-api.h to Swift
|-- Info.plist                       # App bundle config + microphone privacy description
|-- Assets.xcassets/                 # App icons and colors
```

### Data Flow Diagram

```
+------------+     +----------------+     +------------------+
|  User      |     |  Microphone    |     |  AVAudioEngine   |
|  Speaks    | --> |  (48kHz stereo)| --> |  + Converter     |
+------------+     +----------------+     |  (to 16kHz mono) |
                                          +--------+---------+
                                                   |
                                                   v
+------------+     +------------------+     +------------------+
|  SwiftUI   | <-- |  RecognizerEngine| <-- |  [Float] samples |
|  Chat UI   |     |  (published text)|     +--------+---------+
+------------+     +------------------+              |
                            ^                        v
                            |               +------------------+
                            |               | SherpaOnnxRecognizer
                            |               | (C API wrapper)  |
                            |               +--------+---------+
                            |                        |
                            |                        v
                            |               +------------------+
                            +---------------| sherpa-onnx C API|
                                getResult() | (ONNX inference) |
                                            +------------------+
```

---

## Section 2: Program Entry Point (程序入口)

**File:** [VoiceToTTSApp.swift](VoiceToTTS/VoiceToTTSApp.swift)

```swift
// ①
import SwiftUI

// ②
@main
struct VoiceToTTSApp: App {
    // ③
    var body: some Scene {
        WindowGroup {
            // ④
            ContentView()
        }
    }
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | Import SwiftUI framework for declarative UI. |
| ② | `@main` marks this as the app entry point. Swift automatically calls this when the app launches. |
| ③ | `body` is a computed property returning the app's scene hierarchy. |
| ④ | `ContentView()` is the root view. Every SwiftUI app starts with one root view inside a `WindowGroup`. |

**Key Syntax:**

| Syntax | Purpose |
|--------|---------|
| `@main` | Entry point attribute — tells Swift where execution begins. |
| `App` protocol | Conformed by the struct that defines the app's scenes. |
| `WindowGroup` | A scene that creates one or more windows. On iPhone, it creates a single full-screen window. |

---

## Section 3: Core Engine (核心引擎)

### 3.1 RecognizerState Enum

**File:** [RecognizerEngine.swift](VoiceToTTS/RecognizerEngine.swift)

```swift
// ①
enum RecognizerState: Equatable {
    // ②
    case idle
    case loading
    case listening
    case recognizing
    case error(String)

    // ③
    static func == (lhs: RecognizerState, rhs: RecognizerState) -> Bool {
        switch (lhs, rhs) {
        // ④
        case (.idle, .idle), (.loading, .loading),
             (.listening, .listening), (.recognizing, .recognizing):
            return true
        // ⑤
        case (.error(let a), .error(let b)):
            return a == b
        // ⑥
        default:
            return false
        }
    }
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | An `enum` groups related states. `: Equatable` lets Swift compare two states with `==`. |
| ② | Five possible states. `error(String)` carries an associated error message. |
| ③ | Custom `==` implementation because the compiler cannot auto-synthesize `Equatable` for enums with associated values in all cases. |
| ④ | If both sides are the same simple case, they are equal. |
| ⑤ | For `.error`, unwrap the associated `String` values and compare them. |
| ⑥ | Any other combination (e.g., `.idle` vs `.loading`) is not equal. |

---

### 3.2 RecognizedMessage Struct

```swift
// ①
struct RecognizedMessage: Identifiable {
    // ②
    let id: UUID
    let text: String
    let isFinal: Bool
    let timestamp: Date

    // ③
    init(id: UUID = UUID(), text: String, isFinal: Bool, timestamp: Date) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
        self.timestamp = timestamp
    }
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | `Identifiable` protocol requires an `id` property so SwiftUI can track list items efficiently. |
| ② | Properties store the message content, finalization state, and creation time. |
| ③ | Explicit initializer lets us preserve `id` when updating an existing message in-place. Without this, `id` would be re-generated on every update, breaking list animations. |

---

### 3.3 RecognizerEngine Class

```swift
// ①
@MainActor
final class RecognizerEngine: ObservableObject {
    // ②
    @Published var state: RecognizerState = .idle
    @Published var messages: [RecognizedMessage] = []
    @Published var currentText: String = ""

    // ③
    private var recognizer: SherpaOnnxRecognizer?
    private let recorder = AudioRecorder()
    private var currentMessageID: UUID?
```

| Annotation | Explanation |
|------------|-------------|
| ① | `@MainActor` guarantees all published property updates happen on the main thread. `final` prevents subclassing for performance. `ObservableObject` lets SwiftUI observe changes. |
| ② | `@Published` marks properties that trigger UI updates when changed. `state` drives the mic button color/icon; `messages` feeds the chat list. |
| ③ | `recognizer` holds the ONNX model wrapper. `recorder` captures microphone audio. `currentMessageID` tracks the in-progress message for incremental updates. |

---

### 3.4 load() — Model Loading

```swift
func load() {
    // ①
    guard recognizer == nil else { return }
    state = .loading

    // ②
    guard
        let modelPath = Bundle.main.path(forResource: "model.int8", ofType: "onnx"),
        let tokensPath = Bundle.main.path(forResource: "tokens", ofType: "txt")
    else {
        state = .error("Model files not found in app bundle.")
        return
    }

    // ③
    let bpePath = Bundle.main.path(forResource: "bbpe", ofType: "model") ?? ""

    // ④
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

    // ⑤
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

    // ⑥
    recognizer = SherpaOnnxRecognizer(config: &config)
    state = .idle
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | Skip loading if already loaded. Set state so UI shows a spinner. |
| ② | `Bundle.main.path` locates files copied into the app bundle. These must be added to "Copy Bundle Resources" in Xcode. |
| ③ | `bbpe.model` is optional for some models. `?? ""` provides a safe fallback empty string. |
| ④ | Build the model configuration: 16kHz sample rate, 80-dim features, Zipformer2-CTC architecture, CPU inference, 2 threads. |
| ⑤ | `enableEndpoint: true` turns on endpoint detection — the model detects when you stop speaking. The three rules configure silence duration thresholds. |
| ⑥ | Create the recognizer with `&config` (pass by reference, required by the C API). Then set state to idle, ready for recording. |

**Most Important Function:** `load()` is the gateway to the entire app. Without it, the ONNX model never initializes and no recognition can happen. The `enableEndpoint` flag is critical — it allows the app to automatically segment speech into separate utterances.

---

### 3.5 startListening() — Begin Recording

```swift
func startListening() async {
    // ①
    guard let recognizer = recognizer else {
        state = .error("Model not loaded. Call load() first.")
        return
    }

    // ②
    let granted = await recorder.requestPermission()
    guard granted else {
        state = .error("Microphone permission denied.")
        return
    }

    // ③
    recognizer.reset()
    currentText = ""
    currentMessageID = nil
    state = .listening

    // ④
    recorder.startRecording { [weak self] samples in
        guard let self = self else { return }
        Task { @MainActor in
            self.processAudioChunk(samples: samples)
        }
    }
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | Ensure model is loaded before starting. This prevents crashes. |
| ② | `await` suspends until the user grants or denies microphone permission. The OS shows a system dialog. |
| ③ | Reset the recognizer for a fresh session. Clear any previous partial results. |
| ④ | `[weak self]` prevents a retain cycle between the closure and the engine. `Task { @MainActor in ... }` ensures UI updates run on the main thread. |

---

### 3.6 processAudioChunk() — The Recognition Loop

```swift
private func processAudioChunk(samples: [Float]) {
    // ①
    guard let recognizer = recognizer else { return }
    guard state == .listening || state == .recognizing else { return }

    // ②
    recognizer.acceptWaveform(samples: samples, sampleRate: 16000)

    // ③
    while recognizer.isReady() {
        recognizer.decode()
    }

    // ④
    if let result = recognizer.getResult() {
        let text = result.text
        if !text.isEmpty {
            self.currentText = text
            self.updateOrCreateMessage(text: text, isFinal: false)
        }
    }

    // ⑤
    if recognizer.isEndpoint() {
        if let result = recognizer.getResult() {
            let text = result.text
            if !text.isEmpty {
                self.finalizeCurrentText(text)
            }
        }
        recognizer.reset()
        currentText = ""
        currentMessageID = nil
    }
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | Guard against nil recognizer and unexpected states. |
| ② | Feed the 16kHz Float32 audio samples into the streaming recognizer. |
| ③ | `isReady()` checks if enough audio has accumulated for a decode pass. `decode()` runs the neural network inference. |
| ④ | `getResult()` returns the current partial transcription. Update the UI message in-place so the user sees real-time feedback. |
| ⑤ | `isEndpoint()` detects silence/speech-end. When triggered, finalize the current utterance and reset for the next sentence. |

---

### 3.7 updateOrCreateMessage() & finalizeCurrentText()

```swift
private func updateOrCreateMessage(text: String, isFinal: Bool) {
    // ①
    if let id = currentMessageID,
       let index = messages.firstIndex(where: { $0.id == id }) {
        messages[index] = RecognizedMessage(
            id: id, text: text, isFinal: isFinal,
            timestamp: messages[index].timestamp
        )
    } else {
        // ②
        let newMsg = RecognizedMessage(text: text, isFinal: isFinal, timestamp: Date())
        currentMessageID = newMsg.id
        messages.append(newMsg)
    }
}

private func finalizeCurrentText(_ text: String) {
    // ③
    if let id = currentMessageID,
       let index = messages.firstIndex(where: { $0.id == id }) {
        messages[index] = RecognizedMessage(
            id: id, text: text, isFinal: true,
            timestamp: messages[index].timestamp
        )
    } else if !text.isEmpty {
        messages.append(RecognizedMessage(text: text, isFinal: true, timestamp: Date()))
    }
    currentMessageID = nil
    currentText = ""
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | If we already have a message for this utterance, update it in-place. Preserve `id` and `timestamp` so SwiftUI doesn't treat it as a new item. |
| ② | Otherwise, create a new message and track its ID as the "current" one. |
| ③ | `finalizeCurrentText` marks the message as `isFinal: true`, removing the dashed border in the UI. Then clear tracking state for the next utterance. |

---

## Section 4: UI Layer (用户界面)

### 4.1 ContentView — Main Screen

**File:** [ContentView.swift](VoiceToTTS/ContentView.swift)

```swift
struct ContentView: View {
    // ①
    @StateObject private var engine = RecognizerEngine()

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    messagesList          // ②
                    if let error = engine.errorMessage {
                        errorBanner(error) // ③
                    }
                    controlBar             // ④
                }
            }
            .navigationTitle("Voice Recognition")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !engine.messages.isEmpty {
                        Button("Clear") { engine.clearMessages() }
                    }
                }
            }
        }
        // ⑤
        .navigationViewStyle(.stack)
        .task { engine.load() }
    }
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | `@StateObject` creates and owns the `RecognizerEngine` instance. SwiftUI keeps it alive for the view's lifetime. |
| ② | `messagesList` is a computed property showing the chat bubbles. |
| ③ | `errorBanner` appears only when `engine.errorMessage` is non-nil. |
| ④ | `controlBar` contains the microphone button at the bottom. |
| ⑤ | `.stack` forces the classic navigation stack style (needed for iOS 15 compatibility). `.task` runs `load()` asynchronously when the view appears. |

---

### 4.2 messagesList — Auto-Scrolling Chat

```swift
private var messagesList: some View {
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(engine.messages) { message in
                    MessageBubble(text: message.text, isFinal: message.isFinal)
                        .id(message.id)
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.horizontal, 16)
        }
        // ①
        .onChange(of: engine.messages.count) { _ in
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | `ScrollViewReader` provides a `proxy` to programmatically scroll. When a new message arrives, animate-scroll to the invisible "bottom" anchor. |

---

### 4.3 MessageBubble — Chat Bubble Component

```swift
struct MessageBubble: View {
    let text: String
    let isFinal: Bool

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                )
                .foregroundColor(.primary)
                // ①
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.accentColor.opacity(isFinal ? 0.0 : 0.4), lineWidth: 1)
                )
        }
    }
}
```

| Annotation | Explanation |
|------------|-------------|
| ① | `overlay` adds a dashed-style border when `isFinal == false`. The border disappears once the utterance is finalized, giving visual feedback that the text is still being updated. |

---

## Section 5: Syntax Reference (语法速查)

| Keyword | Purpose | Usage in this project |
|---------|---------|----------------------|
| `@main` | App entry point | `VoiceToTTSApp.swift` |
| `@StateObject` | Owns an observable object | `ContentView` owns `RecognizerEngine` |
| `@Published` | Triggers UI updates on change | `state`, `messages`, `currentText` |
| `@MainActor` | Forces execution on main thread | `RecognizerEngine` class |
| `ObservableObject` | Protocol for reactive data model | `RecognizerEngine`, `AudioRecorder` |
| `Identifiable` | Provides stable ID for lists | `RecognizedMessage` |
| `async / await` | Asynchronous functions | `startListening()`, `requestPermission()` |
| `Task { @MainActor in }` | Dispatch to main thread from closure | `processAudioChunk` callback |
| `guard let` | Early exit if optional is nil | Checking model paths, recognizer existence |
| `weak self` | Avoid retain cycles in closures | Recorder audio chunk callback |
| `withAnimation` | Animate state-driven UI changes | Auto-scroll to bottom |
| `ScrollViewReader` | Programmatic scroll control | Chat auto-scroll |
| `LazyVStack` | Lazy-loading vertical list | Message list |
| `.task` | Run async code on appear | `engine.load()` |
| `WindowGroup` | App scene container | `VoiceToTTSApp` |

### Layout Diagram

```
+------------------------------------------+
|  Navigation Bar  "Voice Recognition"     |
+------------------------------------------+
|                                          |
|  +------------------------------------+  |
|  |  Message Bubble (right aligned)    |  |
|  +------------------------------------+  |
|  +------------------------------------+  |
|  |  Message Bubble (dashed = partial) |  |
|  +------------------------------------+  |
|                                          |
|  [ ScrollView + LazyVStack ]             |
|                                          |
+------------------------------------------+
|  Error Banner (conditional)              |
+------------------------------------------+
|  +------------------------------------+  |
|  |        [ O Mic Button O ]          |  |
|  +------------------------------------+  |
|  [ Control Bar — safe area padded ]      |
+------------------------------------------+
```

---

## Section 6: Beginner Pitfalls (新手注意事项)

### 1. Audio Session Must Be Active Before Querying Input Format

❌ **Wrong:**
```swift
let inputFormat = inputNode.outputFormat(forBus: 0)
// ... create converter ...
try session.setActive(true)  // Too late!
```

✅ **Correct:**
```swift
try session.setCategory(.playAndRecord, mode: .default)
try session.setActive(true)
let inputFormat = inputNode.outputFormat(forBus: 0)
```

**Why:** `AVAudioInputNode` doesn't know its format until the session is configured. Creating the converter before activation returns nil.

---

### 2. `@Published` Updates Must Happen on Main Thread

❌ **Wrong:**
```swift
recorder.startRecording { samples in
    self.messages.append(...) // Crash! Background thread
}
```

✅ **Correct:**
```swift
recorder.startRecording { [weak self] samples in
    Task { @MainActor in
        self?.processAudioChunk(samples: samples)
    }
}
```

**Why:** SwiftUI can only observe `@Published` changes on the main thread. Audio callbacks run on a background audio thread.

---

### 3. Always Use `[weak self]` in Escaping Closures

❌ **Wrong:**
```swift
recorder.startRecording { samples in
    self.processAudioChunk(samples: samples)
}
```

✅ **Correct:**
```swift
recorder.startRecording { [weak self] samples in
    guard let self = self else { return }
    ...
}
```

**Why:** The closure captures `self` strongly. If the view dismisses while recording, a strong reference prevents deallocation, causing a memory leak.

---

### 4. Preserve Message ID When Updating In-Place

❌ **Wrong:**
```swift
messages[index] = RecognizedMessage(text: text, isFinal: false, timestamp: Date())
```

✅ **Correct:**
```swift
messages[index] = RecognizedMessage(
    id: id, text: text, isFinal: false,
    timestamp: messages[index].timestamp
)
```

**Why:** Creating a new `UUID` breaks SwiftUI's list diffing. The bubble would flicker or jump position instead of smoothly updating.

---

### 5. Model Files Must Be in "Copy Bundle Resources"

❌ **Wrong:** Model files dragged into the project but not added to the app target.

✅ **Correct:** In Xcode, select `model.int8.onnx`, `tokens.txt`, `bbpe.model` → Target Membership → Check "VoiceToTTS".

**Why:** `Bundle.main.path(forResource:)` only finds files that are copied into the app bundle at build time.

---

## Section 7: Extension Exercise 1 — Switch Recognition Language/Model

**Goal:** Let the user switch between Chinese, English, or other language models at runtime.

### Step 1: Add a model selector to the engine

**File:** `RecognizerEngine.swift`

Add a model configuration enum:

```swift
enum RecognitionModel: String, CaseIterable {
    case chinese = "Chinese (Zipformer-CTC)"
    case english = "English (Zipformer-CTC)"

    var modelFile: String {
        switch self {
        case .chinese: return "model.int8"
        case .english: return "en-model.int8"
        }
    }

    var tokensFile: String {
        switch self {
        case .chinese: return "tokens"
        case .english: return "en-tokens"
        }
    }
}
```

### Step 2: Modify `load()` to accept a model parameter

**Before:**
```swift
func load() {
    guard recognizer == nil else { return }
```

**After:**
```swift
@Published var selectedModel: RecognitionModel = .chinese

func load(model: RecognitionModel = .chinese) {
    // Tear down old recognizer
    recognizer = nil
    selectedModel = model
    state = .loading

    guard
        let modelPath = Bundle.main.path(forResource: model.modelFile, ofType: "onnx"),
        let tokensPath = Bundle.main.path(forResource: model.tokensFile, ofType: "txt")
    else {
        state = .error("Model files not found for \(model.rawValue)")
        return
    }
    // ... rest of config stays the same
```

### Step 3: Add a picker to ContentView

**File:** `ContentView.swift`

Add a picker in the toolbar:

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        Picker("Model", selection: $engine.selectedModel) {
            ForEach(RecognitionModel.allCases, id: \.self) { model in
                Text(model.rawValue).tag(model)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: engine.selectedModel) { newModel in
            engine.load(model: newModel)
        }
    }
}
```

### Result

A dropdown menu in the navigation bar lets users switch languages. Place the corresponding ONNX model and tokens file in the app bundle.

---

## Section 8: Extension Exercise 2 — UI Redesign (Horizontal Waveform)

**Goal:** Replace the static message list with a live audio waveform visualization.

### Replace `messagesList` with a waveform view

**File:** `ContentView.swift`

**Before:** `messagesList` is a `ScrollView` with bubbles.

**After — WaveformView:**

```swift
struct WaveformView: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<min(samples.count, 60), id: \.self) { i in
                    let amplitude = CGFloat(abs(samples[i]))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 4, height: max(4, amplitude * geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

### Update ContentView

```swift
private var messagesList: some View {
    VStack {
        if engine.state == .listening || engine.state == .recognizing {
            WaveformView(samples: engine.recentSamples)
                .frame(height: 100)
                .padding()
        }

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(engine.messages) { message in
                        MessageBubble(text: message.text, isFinal: message.isFinal)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: engine.messages.count) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}
```

### Store recent samples in the engine

**File:** `RecognizerEngine.swift`

```swift
@Published var recentSamples: [Float] = []

private func processAudioChunk(samples: [Float]) {
    recentSamples = Array(samples.suffix(60))
}
```

---

## Section 9: More Extension Ideas

| # | Extension | Difficulty | Implementation Hint |
|---|-----------|-----------|---------------------|
| 1 | **Bluetooth Smart Car Control** | Medium | Add `CoreBluetooth`. Parse recognized text for commands ("forward", "stop", "left"). Map to BLE characteristic writes. Add `BluetoothManager.swift` with `CBCentralManager`. |
| 2 | **Voice Command Parser** | Easy | Regex-based parser in `RecognizerEngine`: `if text.contains("前进") { sendCommand(.forward) }`. Connect to a `CommandExecutor` protocol. |
| 3 | **Text-to-Speech Feedback** | Easy | Import `AVFoundation`. Use `AVSpeechSynthesizer` to speak back the final recognized text. Add a toggle in settings. |
| 4 | **Export Transcription** | Easy | Add a share button that exports `messages.map { $0.text }.joined(separator: "\n")` via `UIActivityViewController`. |
| 5 | **Wake Word Detection** | Advanced | Integrate a separate ONNX keyword spotting model (e.g., "Hey Assistant"). Run a lightweight model in parallel; only activate the full ASR after wake word is detected. Saves battery. |
| 6 | **Multi-language Mix** | Medium | Load two recognizers (Chinese + English). Run both on the same audio stream. Combine results using confidence scores. |
| 7 | **Local LLM Integration** | Advanced | Pipe final text into an on-device LLM (e.g., `llama.cpp`, `mlx-swift`) for question answering. Display LLM response as a left-aligned bubble. |
| 8 | **Conversation History** | Easy | Persist `messages` to `UserDefaults` or SwiftData. Load previous sessions on app launch. Add date-based section headers. |

---

## Section 10: Bluetooth Smart Car Control — Detailed Guide

This section explains how to extend VoiceToTTS to send voice commands to a Bluetooth Low Energy (BLE) smart car.

### Architecture

```
Voice Command (Chinese)
       |
       v
+---------------+     +------------------+     +------------------+
| Regex Parser  | --> | Command Enum     | --> | BLE Manager      |
| (e.g. "前进") |     | .forward, .stop  |     | (CoreBluetooth)  |
+---------------+     +------------------+     +------------------+
                                                       |
                                                       v
                                               +---------------+
                                               | Smart Car MCU |
                                               +---------------+
```

### Step 1: Define Commands

Create `CarCommand.swift`:

```swift
enum CarCommand: String, CaseIterable {
    case forward  = "前进"
    case backward = "后退"
    case left     = "左转"
    case right    = "右转"
    case stop     = "停止"

    var bleData: Data {
        switch self {
        case .forward:  return Data([0x01])
        case .backward: return Data([0x02])
        case .left:     return Data([0x03])
        case .right:    return Data([0x04])
        case .stop:     return Data([0x00])
        }
    }
}
```

### Step 2: Create BluetoothManager

Create `BluetoothManager.swift`:

```swift
import CoreBluetooth

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var carPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?

    @Published var isConnected = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        if peripheral.name?.contains("SmartCar") == true {
            carPeripheral = peripheral
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid.uuidString == "FFE1" {  // Common UART characteristic
                commandCharacteristic = characteristic
            }
        }
    }

    func sendCommand(_ command: CarCommand) {
        guard let peripheral = carPeripheral,
              let characteristic = commandCharacteristic else { return }
        peripheral.writeValue(command.bleData, for: characteristic, type: .withoutResponse)
    }
}
```

### Step 3: Parse Text into Commands

Add to `RecognizerEngine.swift`:

```swift
func parseCommand(from text: String) -> CarCommand? {
    for command in CarCommand.allCases {
        if text.contains(command.rawValue) {
            return command
        }
    }
    return nil
}
```

### Step 4: Wire Everything Together

In `RecognizerEngine.finalizeCurrentText`, add:

```swift
if let command = parseCommand(from: text) {
    bluetoothManager.sendCommand(command)
}
```

### Required Info.plist Entry

Add to `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to control a smart car.</string>
```

---

## Appendix: Git Push Commands

After editing the tutorial or source files, commit and push:

```bash
cd /Users/able/Desktop/app_game/VoiceToTTS_sherpa

# Check what changed
git status

# Stage the new tutorial
git add VoiceToTTS/TUTORIAL.md

# Commit
git commit -m "docs: add VoiceToTTS tutorial with extension guides"

# Push to GitHub
git push origin main
```

---

---

## Section 11: Python Backend Integration — LAN Chat

**Goal:** Send finalized speech text from the iPhone to a Python FastAPI backend on your Mac/PC via local WiFi, and display the reply in the chat UI. This sets the foundation for future LLM integration.

### Architecture

```
+------------+     WiFi LAN      +------------------+
|  iPhone    |  ---------------->|  Python FastAPI  |
|  VoiceToTTS|   HTTP POST /chat |  Backend (Mac/PC)|
|            |<----------------- |  Port 8000       |
+------------+     JSON reply    +------------------+
```

### Step 1: Python Backend

Create `python_fastapi/main.py`:

```python
from fastapi import FastAPI
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class Message(BaseModel):
    text: str

@app.post("/chat")
async def chat(msg: Message):
    print(f"[Phone] {msg.text}")
    # Fixed reply for now; will connect to LLM later
    return {"reply": "hello world!"}
```

**Install dependencies** (inside `firstpythonEnv310`):
```bash
conda activate firstpythonEnv310
pip install fastapi uvicorn
```

**Run the server**:
```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` is critical — it listens on all network interfaces so your iPhone on the same WiFi can reach it.

### Step 2: Find Your Computer's LAN IP

**macOS:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```
Or go to **System Settings → Wi-Fi → Details → IP Address**.

**Windows:**
```cmd
ipconfig
```
Look for `IPv4 Address` under your Wi-Fi adapter.

Your IP will look like `192.168.x.x` or `10.0.x.x`.

### Step 3: iOS Modifications

#### 3.1 Enable HTTP (App Transport Security)

Add to `Info.plist` to allow plain HTTP to your local server:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

#### 3.2 Update `RecognizedMessage`

Add `isUser` to distinguish who sent the message:

```swift
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
```

#### 3.3 Add Network Code to `RecognizerEngine`

Add a `@Published` property for the server URL:

```swift
@Published var serverURL: String = "http://192.168.1.100:8000"
```

After `finalizeCurrentText`, send the text to the server:

```swift
private func finalizeCurrentText(_ text: String) {
    // ... existing finalize code ...
    sendToServer(text: text)
}

private func sendToServer(text: String) {
    guard !serverURL.isEmpty,
          let url = URL(string: serverURL + "/chat") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: String] = ["text": text]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            Task { @MainActor [weak self] in
                self?.addServerMessage(text: "🌐 Error: \(error.localizedDescription)")
            }
            return
        }
        guard let data = data else { return }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let reply = json["reply"] {
            Task { @MainActor [weak self] in
                self?.addServerMessage(text: reply)
            }
        }
    }.resume()
}

private func addServerMessage(text: String) {
    let msg = RecognizedMessage(text: text, isFinal: true, timestamp: Date(), isUser: false)
    messages.append(msg)
}
```

#### 3.4 Update `ContentView`

Update `MessageBubble` to show server replies on the left (gray) and user speech on the right (accent color):

```swift
struct MessageBubble: View {
    let text: String
    let isFinal: Bool
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(text)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isUser ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.15))
                )
                .foregroundColor(.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.accentColor.opacity((isFinal || !isUser) ? 0.0 : 0.4), lineWidth: 1)
                )
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
```

Add a server URL input field above the mic button so the user can edit the IP at runtime:

```swift
HStack(spacing: 8) {
    Image(systemName: "network")
        .foregroundColor(.secondary)
        .font(.caption)
    TextField("http://192.168.x.x:8000", text: $engine.serverURL)
        .font(.caption)
        .textFieldStyle(.roundedBorder)
        .keyboardType(.URL)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
}
.padding(.horizontal, 16)
.padding(.vertical, 8)
```

### Step 4: Run Both Sides

1. **Start the Python backend** on your Mac/PC:
   ```bash
   conda activate firstpythonEnv310
   uvicorn main:app --host 0.0.0.0 --port 8000
   ```

2. **Build and run the iOS app** on your iPhone (must be on the **same WiFi**).

3. **Edit the server URL** in the app to match your computer's LAN IP (e.g., `http://192.168.1.100:8000`).

4. **Tap the mic, speak a sentence**, and watch the chat:
   - Your speech appears as a right-aligned bubble.
   - After you stop speaking, the app sends the text to the backend.
   - The backend replies `hello world!`, which appears as a left-aligned gray bubble.

---

## Section 12: Real AI Server Integration — WeChat-Style Chat

> Building on Section 11, upgrade from "auto-send with fixed reply" to a full chat experience with editable draft, manual send, AI typing indicator, and robust error handling. This section applies the Pomodoro + signal-flow methodology from the `pomodoro-project-breakdown` skill.

### 12.1 Upgraded Signal Flow

Section 11's flow was **one-way auto-push**: speech ends → auto POST → receive reply. The downside: users couldn't fix recognition errors or type directly.

The upgraded flow becomes **bidirectional controlled conversation**:

```
+------------+         +------------------+         +------------------+
|  User      |         |  draftText       |         |  User taps Send  |
|  speaks or |  -----> |  (editable       |  -----> |  sendDraft()     |
|  types     |         |   draft)         |         |                  |
+------------+         +------------------+         +--------+---------+
                                                             |
                                                             v
+------------+         +------------------+         +------------------+
|  AI reply  |  <----- |  /send_msg       |  <----- |  URLSession      |
|  bubble    |         |  X-API-Token     |         |  130s timeout    |
+------------+         +------------------+         +--------+---------+
                                                             |
                    +------------------+                   |
                    |  TypingIndicator | <-----------------+
                    |  "AI is typing"  |
                    +------------------+
```

| Node | Input | Output | Control Point |
|------|-------|--------|---------------|
| Speech Recognition | Microphone audio | `draftText` | User can edit anytime |
| Text Input | Keyboard | `draftText` | Shared input box with voice |
| Send Button | `draftText` | `messages` + HTTP POST | User decides when to send |
| Wait State | `isSending = true` | Typing indicator UI | Visual feedback |
| Network Layer | `{"message": text}` | JSON `后端回复` | 130s timeout + Token auth |
| Error Handling | NSError / HTTP / JSON | Error message bubble | Categorized user alerts |

---

### 12.2 Pomodoro Breakdown: 2 Tomatoes for This Upgrade

**Tomato 1 — Editable Draft & Manual Send (25 min)**

- Write recognition results to `draftText` instead of creating messages directly in `processAudioChunk()`
- Remove auto-send logic from `finalizeCurrentText()`
- Build a WeChat-style input bar in `ContentView`: mic button + text field + send button
- Add `sendDraft()` method: validate → add user message → clear draft → call network layer

**Tomato 2 — AI Typing Indicator & Robust Network Layer (25 min)**

- Add `@Published var isSending` to drive the typing indicator
- Create `TypingIndicatorBubble` view component
- Configure `URLSessionConfiguration` with 130s timeout (matching server's 120s limit)
- Implement categorized error handling: timeout, disconnect, HTTP error, JSON parse failure, business error
- Add `X-API-Token` request header for authentication

---

### 12.3 Core Code Walkthrough

#### Engine Layer — RecognizerEngine.swift

**New published properties:**

```swift
@Published var draftText: String = ""      // User-editable input draft
@Published var isSending: Bool = false      // Controls typing indicator
@Published var serverURL: String = ""       // Runtime config, no real address in source
@Published var apiToken: String = ""        // Runtime config, no real token in source
```

**Send draft:**

```swift
func sendDraft() {
    let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isSending else { return }
    guard !serverURL.isEmpty else {
        addServerMessage(text: "⚠️ Please enter the server address above")
        return
    }

    // 1. Add user message to chat history
    let userMsg = RecognizedMessage(text: text, isFinal: true, timestamp: Date(), isUser: true)
    messages.append(userMsg)

    // 2. Clear input box
    draftText = ""

    // 3. Send to AI server
    sendToServer(text: text)
}
```

**Key design decisions:**
- `guard !serverURL.isEmpty`: In the open-source version, defaults to empty string to prevent accidental credential commits.
- User message is added to `messages` before clearing `draftText` — so even if the network fails, the user's question remains in chat history.

**Network request — 130s timeout + token auth:**

```swift
private func sendToServer(text: String) {
    guard let url = URL(string: serverURL + "/send_msg") else { return }

    isSending = true

    // Custom timeout config (server allows 120s, client sets 130s to avoid disconnecting first)
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

        // ① Network-level errors (timeout, disconnect, etc.)
        if let error = error as NSError? {
            let msg: String
            switch error.code {
            case NSURLErrorTimedOut:
                msg = "❌ Request timed out: AI took longer than 130 seconds"
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                msg = "❌ Connection failed: unable to reach server"
            default:
                msg = "❌ Network error: \(error.localizedDescription)"
            }
            Task { @MainActor [weak self] in
                self?.addServerMessage(text: msg)
            }
            return
        }

        guard let data = data else {
            Task { @MainActor [weak self] in
                self?.addServerMessage(text: "❌ No data received from server")
            }
            return
        }

        // ② JSON parsing and business code validation
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
                    let err = errorMsg ?? "Unknown error (code: \(code ?? -1))"
                    Task { @MainActor [weak self] in
                        self?.addServerMessage(text: "⚠️ Server error: \(err)")
                    }
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.addServerMessage(text: "❌ Unable to parse server response")
                }
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.addServerMessage(text: "❌ JSON parsing failed")
            }
        }
    }.resume()
}
```

**Error handling reference table:**

| Scenario | Trigger | User Alert | Troubleshooting |
|----------|---------|------------|-----------------|
| Timeout | `NSURLErrorTimedOut` | ❌ Request timed out: AI took longer than 130s | Server inference slow, high network latency |
| Connection Failure | `CannotConnectToHost` | ❌ Connection failed: unable to reach server | Wrong IP/port, firewall, server not running |
| No Data | `data == nil` | ❌ No data received from server | Server crash, intermediate proxy issue |
| JSON Exception | Parse throws | ❌ JSON parsing failed | Server returned non-JSON (e.g., HTML error page) |
| Business Error | `code != 200` | ⚠️ Server error: xxx | Invalid token, bad parameter, server internal error |

---

#### UI Layer — ContentView.swift

**Typing indicator component:**

```swift
struct TypingIndicatorBubble: View {
    var body: some View {
        HStack {
            Spacer(minLength: 40)
            HStack(spacing: 4) {
                Text("AI is typing")
                    .font(.body)
                    .foregroundColor(.secondary)
                Text("...")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
            )
        }
    }
}
```

**Message list — conditional typing indicator:**

```swift
LazyVStack(spacing: 12) {
    ForEach(engine.messages) { message in
        MessageBubble(text: message.text, isFinal: message.isFinal, isUser: message.isUser)
            .id(message.id)
    }
    if engine.isSending {
        TypingIndicatorBubble()
            .id("typing-indicator")
    }
    Color.clear.frame(height: 1).id("bottom")
}
.onChange(of: engine.isSending) { _ in
    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
}
```

**Bottom input bar — WeChat-style layout:**

```swift
HStack(spacing: 10) {
    // Mic toggle
    Button { toggleListening() } label: {
        Image(systemName: micIconName)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(micButtonColor)
            .frame(width: 36, height: 36)
    }

    // Text input (shared by voice results and keyboard)
    TextField(engine.state == .listening ? "Listening..." : "Type a message...", text: $engine.draftText)
        .font(.body)
        .padding(8)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(18)

    // Send button
    Button { engine.sendDraft() } label: {
        Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 32))
            .foregroundColor(engine.draftText.isEmpty || engine.isSending ? Color.gray.opacity(0.5) : .accentColor)
    }
    .disabled(engine.draftText.isEmpty || engine.isSending)
}
```

**Server config area (runtime input, no secrets in code):**

```swift
HStack(spacing: 8) {
    Image(systemName: "network")
    TextField("https://api.example.com", text: $engine.serverURL)
        .keyboardType(.URL)
}
HStack(spacing: 8) {
    Image(systemName: "key.fill")
    SecureField("API Token", text: $engine.apiToken)
}
```

> **Security tip:** The open-source code defaults `serverURL` and `apiToken` to empty strings. Fill them in the App UI at runtime, or hardcode in your local fork and add to `.gitignore`.

---

### 12.4 Configuration & Run

#### Server API Contract

Your AI backend must satisfy this interface contract:

| Item | Requirement |
|------|-------------|
| Endpoint | `POST /send_msg` |
| Headers | `Content-Type: application/json`; optional `X-API-Token: YOUR_TOKEN` |
| Body | `{"message": "user input text"}` |
| Success Response | `{"code": 200, "后端回复": "AI answer content"}` |
| Error Response | `{"code": non-200, "error": "error description"}` |
| Timeout Limit | Server should allow at least 120 seconds (DeepSeek etc. may need longer) |

#### Client Configuration Steps

1. **Build and run the iOS App**
2. **Enter the server address** at the top, e.g., `http://your-server-ip:10000` (**do not append `/send_msg`**)
3. **Enter the API token** in the Token field (if your server requires auth)
4. **Tap the mic and speak** — recognition results appear in the input box
5. **Edit the recognized text** (if errors), or type directly from keyboard
6. **Tap the send button** and wait for the AI reply bubble

---

### 12.5 Evolution from Section 11 to Section 12

| Dimension | Section 11 (LAN Demo) | Section 12 (Real AI Chat) |
|-----------|----------------------|---------------------------|
| Send Timing | Auto-send after speech ends | User manually taps send |
| Text Correction | Not possible | Speech results go to input box, editable |
| Direct Input | Not supported | Keyboard direct input supported |
| Wait Feedback | None | "AI is typing..." indicator |
| Backend Endpoint | `/chat` returns fixed `"hello world!"` | `/send_msg` returns real AI inference |
| Authentication | None | `X-API-Token` header |
| Timeout | Default 60s | Custom 130s |
| Error Messages | Simple `localizedDescription` | Categorized: timeout, disconnect, JSON, business code |

---

*Happy coding! If you build any of these extensions, consider sharing your fork.*
