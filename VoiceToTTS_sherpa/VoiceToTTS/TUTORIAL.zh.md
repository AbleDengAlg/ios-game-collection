# VoiceToTTS 教案 — 基于 sherpa-onnx 的 iOS 离线中文语音识别

> 从零开始学习如何使用 SwiftUI、AVAudioEngine 和 sherpa-onnx 流式 ASR 构建 iOS 离线语音转文字应用。

---

## 第1节：项目概览

### 文件结构

```
VoiceToTTS/
|-- VoiceToTTSApp.swift              # 应用入口 — 启动 ContentView
|-- ContentView.swift                # 主界面 — 聊天式 UI、麦克风按钮
|-- RecognizerEngine.swift           # 核心引擎 — 加载模型、处理音频、发布文字
|-- AudioRecorder.swift              # 麦克风采集 — 16kHz 单声道转换
|-- SherpaOnnx.swift                 # C API 封装 — 配置构造器 + 识别器类
|-- SherpaOnnx-Bridging-Header.h     # 将 sherpa-onnx/c-api/c-api.h 暴露给 Swift
|-- Info.plist                       # 应用包配置 + 麦克风隐私描述
|-- Assets.xcassets/                 # 应用图标和颜色
```

### 数据流图

```
+------------+     +----------------+     +------------------+
|   用户     |     |   麦克风       |     |  AVAudioEngine   |
|   说话     | --> |  (48kHz 立体声)| --> |  + 格式转换器     |
+------------+     +----------------+     |  (转 16kHz 单声道)|
                                          +--------+---------+
                                                   |
                                                   v
+------------+     +------------------+     +------------------+
|  SwiftUI   | <-- |  RecognizerEngine| <-- |  [Float] 采样点  |
|  聊天界面  |     |  (发布文字)      |     +--------+---------+
+------------+     +------------------+              |
                            ^                        v
                            |               +------------------+
                            |               | SherpaOnnxRecognizer
                            |               | (C API 封装)     |
                            |               +--------+---------+
                            |                        |
                            |                        v
                            |               +------------------+
                            +---------------| sherpa-onnx C API|
                                getResult() | (ONNX 推理)      |
                                            +------------------+
```

---

## 第2节：程序入口

**文件：** [VoiceToTTSApp.swift](VoiceToTTS/VoiceToTTSApp.swift)

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

| 标号 | 说明 |
|------|------|
| ① | 导入 SwiftUI 框架，用于声明式 UI。 |
| ② | `@main` 标记应用入口点。应用启动时 Swift 自动调用此处。 |
| ③ | `body` 是计算属性，返回应用的场景层级。 |
| ④ | `ContentView()` 是根视图。每个 SwiftUI 应用都以 `WindowGroup` 内的一个根视图开始。 |

**关键语法：**

| 语法 | 作用 |
|------|------|
| `@main` | 入口点属性 — 告诉 Swift 执行从这里开始。 |
| `App` 协议 | 定义应用场景的结构体需遵循此协议。 |
| `WindowGroup` | 创建窗口的场景。在 iPhone 上创建一个全屏窗口。 |

---

## 第3节：核心引擎

### 3.1 RecognizerState 枚举

**文件：** [RecognizerEngine.swift](VoiceToTTS/RecognizerEngine.swift)

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

| 标号 | 说明 |
|------|------|
| ① | `enum` 将相关状态归类。`: Equatable` 让 Swift 可以用 `==` 比较两个状态。 |
| ② | 五种可能状态。`error(String)` 携带关联的错误信息。 |
| ③ | 自定义 `==` 实现，因为编译器无法为带关联值的枚举自动合成 `Equatable`。 |
| ④ | 如果两边是相同的简单 case，则相等。 |
| ⑤ | 对于 `.error`，解包关联的 `String` 值并比较。 |
| ⑥ | 其他任意组合（如 `.idle` 和 `.loading`）不相等。 |

---

### 3.2 RecognizedMessage 结构体

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

| 标号 | 说明 |
|------|------|
| ① | `Identifiable` 协议要求提供 `id` 属性，SwiftUI 用它高效追踪列表项。 |
| ② | 属性存储消息内容、完成状态和创建时间。 |
| ③ | 显式初始化器允许原地更新时保留 `id`。若无此设计，每次更新都会重新生成 `id`，破坏列表动画。 |

---

### 3.3 RecognizerEngine 类

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

| 标号 | 说明 |
|------|------|
| ① | `@MainActor` 保证所有发布属性的更新都在主线程。`final` 禁止子类化以提升性能。`ObservableObject` 让 SwiftUI 可以观察变化。 |
| ② | `@Published` 标记变化时会触发 UI 刷新的属性。`state` 驱动麦克风按钮颜色和图标；`messages` 供给聊天列表。 |
| ③ | `recognizer` 持有 ONNX 模型封装。`recorder` 采集麦克风音频。`currentMessageID` 追踪当前未完成的消息，用于增量更新。 |

---

### 3.4 load() — 模型加载

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

| 标号 | 说明 |
|------|------|
| ① | 若已加载则跳过。设置状态让 UI 显示加载指示。 |
| ② | `Bundle.main.path` 定位复制到应用包中的文件。这些文件必须在 Xcode 的 "Copy Bundle Resources" 中添加。 |
| ③ | `bbpe.model` 对某些模型是可选的。`?? ""` 提供安全的空字符串回退。 |
| ④ | 构建模型配置：16kHz 采样率、80 维特征、Zipformer2-CTC 架构、CPU 推理、2 线程。 |
| ⑤ | `enableEndpoint: true` 开启端点检测 — 模型会自动检测你何时停止说话。三条规则配置静音时长阈值。 |
| ⑥ | 用 `&config`（按引用传递，C API 要求）创建识别器。然后将状态设为 idle，准备录音。 |

**最重要的函数：** `load()` 是整个应用的门户。没有它，ONNX 模型无法初始化，识别也就无从谈起。`enableEndpoint` 标志至关重要 — 它让应用自动将语音切分为独立句子。

---

### 3.5 startListening() — 开始录音

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

| 标号 | 说明 |
|------|------|
| ① | 确保模型已加载再开始，防止崩溃。 |
| ② | `await` 挂起直到用户授予或拒绝麦克风权限。系统会弹出权限对话框。 |
| ③ | 重置识别器以开始新会话。清除之前的不完整结果。 |
| ④ | `[weak self]` 防止闭包和引擎之间的循环引用。`Task { @MainActor in ... }` 确保 UI 更新在主线程执行。 |

---

### 3.6 processAudioChunk() — 识别循环

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

| 标号 | 说明 |
|------|------|
| ① | 防护 nil 识别器和意外状态。 |
| ② | 将 16kHz Float32 音频采样点送入流式识别器。 |
| ③ | `isReady()` 检查是否已积累足够音频进行解码。`decode()` 运行神经网络推理。 |
| ④ | `getResult()` 返回当前部分转录。原地更新 UI 消息，让用户看到实时反馈。 |
| ⑤ | `isEndpoint()` 检测静音/语音结束。触发时，完成当前话语并为下一句重置。 |

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

| 标号 | 说明 |
|------|------|
| ① | 若当前话语已有消息，则原地更新。保留 `id` 和 `timestamp`，避免 SwiftUI 将其视为新项。 |
| ② | 否则创建新消息，并将其 ID 记录为"当前"消息。 |
| ③ | `finalizeCurrentText` 将消息标记为 `isFinal: true`，UI 中虚线边框消失。然后清除追踪状态，准备下一句。 |

---

## 第4节：UI 层

### 4.1 ContentView — 主界面

**文件：** [ContentView.swift](VoiceToTTS/ContentView.swift)

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

| 标号 | 说明 |
|------|------|
| ① | `@StateObject` 创建并拥有 `RecognizerEngine` 实例。SwiftUI 在视图生命周期内保持其存活。 |
| ② | `messagesList` 是计算属性，显示聊天气泡。 |
| ③ | `errorBanner` 仅在 `engine.errorMessage` 非 nil 时显示。 |
| ④ | `controlBar` 包含底部麦克风按钮。 |
| ⑤ | `.stack` 强制经典导航栈样式（iOS 15 兼容需要）。`.task` 在视图出现时异步运行 `load()`。 |

---

### 4.2 messagesList — 自动滚动聊天

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

| 标号 | 说明 |
|------|------|
| ① | `ScrollViewReader` 提供 `proxy` 用于编程式滚动。新消息到达时，动画滚动到不可见的 "bottom" 锚点。 |

---

### 4.3 MessageBubble — 聊天气泡组件

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

| 标号 | 说明 |
|------|------|
| ① | `overlay` 在 `isFinal == false` 时添加虚线边框。话语完成后边框消失，提供文字仍在更新的视觉反馈。 |

---

## 第5节：语法速查

| 关键字 | 作用 | 本项目中的使用 |
|--------|------|---------------|
| `@main` | 应用入口点 | `VoiceToTTSApp.swift` |
| `@StateObject` | 拥有可观察对象 | `ContentView` 拥有 `RecognizerEngine` |
| `@Published` | 变化时触发 UI 更新 | `state`、`messages`、`currentText` |
| `@MainActor` | 强制在主线程执行 | `RecognizerEngine` 类 |
| `ObservableObject` | 响应式数据模型协议 | `RecognizerEngine`、`AudioRecorder` |
| `Identifiable` | 为列表提供稳定 ID | `RecognizedMessage` |
| `async / await` | 异步函数 | `startListening()`、`requestPermission()` |
| `Task { @MainActor in }` | 从闭包派发到主线程 | `processAudioChunk` 回调 |
| `guard let` | 可选值为 nil 时提前退出 | 检查模型路径、识别器存在性 |
| `weak self` | 避免闭包中的循环引用 | 录音器音频块回调 |
| `withAnimation` | 动画化状态驱动的 UI 变化 | 自动滚动到底部 |
| `ScrollViewReader` | 编程式滚动控制 | 聊天自动滚动 |
| `LazyVStack` | 懒加载垂直列表 | 消息列表 |
| `.task` | 出现时运行异步代码 | `engine.load()` |
| `WindowGroup` | 应用场景容器 | `VoiceToTTSApp` |

### 布局图

```
+------------------------------------------+
|  导航栏    "Voice Recognition"            |
+------------------------------------------+
|                                          |
|  +------------------------------------+  |
|  |  消息气泡（右对齐）                 |  |
|  +------------------------------------+  |
|  +------------------------------------+  |
|  |  消息气泡（虚线 = 未完成）          |  |
|  +------------------------------------+  |
|                                          |
|  [ ScrollView + LazyVStack ]             |
|                                          |
+------------------------------------------+
|  错误横幅（条件显示）                     |
+------------------------------------------+
|  +------------------------------------+  |
|  |        [ O 麦克风按钮 O ]           |  |
|  +------------------------------------+  |
|  [ 控制栏 — 安全区填充 ]                  |
+------------------------------------------+
```

---

## 第6节：新手注意事项

### 1. 查询输入格式前必须先激活音频会话

❌ **错误：**
```swift
let inputFormat = inputNode.outputFormat(forBus: 0)
// ... 创建转换器 ...
try session.setActive(true)  // 太晚了！
```

✅ **正确：**
```swift
try session.setCategory(.playAndRecord, mode: .default)
try session.setActive(true)
let inputFormat = inputNode.outputFormat(forBus: 0)
```

**原因：** `AVAudioInputNode` 在会话配置前不知道自己的格式。激活前创建转换器会返回 nil。

---

### 2. `@Published` 更新必须在主线程

❌ **错误：**
```swift
recorder.startRecording { samples in
    self.messages.append(...) // 崩溃！后台线程
}
```

✅ **正确：**
```swift
recorder.startRecording { [weak self] samples in
    Task { @MainActor in
        self?.processAudioChunk(samples: samples)
    }
}
```

**原因：** SwiftUI 只能在主线程观察 `@Published` 变化。音频回调在后台音频线程运行。

---

### 3. 逃逸闭包中始终使用 `[weak self]`

❌ **错误：**
```swift
recorder.startRecording { samples in
    self.processAudioChunk(samples: samples)
}
```

✅ **正确：**
```swift
recorder.startRecording { [weak self] samples in
    guard let self = self else { return }
    ...
}
```

**原因：** 闭包强捕获 `self`。若录音时视图被销毁，强引用阻止释放，造成内存泄漏。

---

### 4. 原地更新时保留消息 ID

❌ **错误：**
```swift
messages[index] = RecognizedMessage(text: text, isFinal: false, timestamp: Date())
```

✅ **正确：**
```swift
messages[index] = RecognizedMessage(
    id: id, text: text, isFinal: false,
    timestamp: messages[index].timestamp
)
```

**原因：** 创建新 `UUID` 会破坏 SwiftUI 的列表差分算法。气泡会闪烁或跳动，而非平滑更新。

---

### 5. 模型文件必须在 "Copy Bundle Resources" 中

❌ **错误：** 模型文件拖入项目但未添加到应用目标。

✅ **正确：** 在 Xcode 中，选中 `model.int8.onnx`、`tokens.txt`、`bbpe.model` → Target Membership → 勾选 "VoiceToTTS"。

**原因：** `Bundle.main.path(forResource:)` 只能找到构建时复制到应用包中的文件。

---

## 第7节：扩展练习1 — 切换识别语言/模型

**目标：** 让用户在运行时切换中文、英文或其他语言模型。

### 步骤1：在引擎中添加模型选择器

**文件：** `RecognizerEngine.swift`

添加模型配置枚举：

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

### 步骤2：修改 `load()` 接受模型参数

**修改前：**
```swift
func load() {
    guard recognizer == nil else { return }
```

**修改后：**
```swift
@Published var selectedModel: RecognitionModel = .chinese

func load(model: RecognitionModel = .chinese) {
    // 销毁旧识别器
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
    // ... 其余配置保持不变
```

### 步骤3：在 ContentView 中添加选择器

**文件：** `ContentView.swift`

在工具栏中添加选择器：

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

### 效果

导航栏下拉菜单可让用户切换语言。将对应的 ONNX 模型和 tokens 文件放入应用包即可。

---

## 第8节：扩展练习2 — UI 重设计（波形可视化）

**目标：** 将静态消息列表替换为实时音频波形可视化。

### 用波形视图替换 messagesList

**文件：** `ContentView.swift`

**修改前：** `messagesList` 是带气泡的 `ScrollView`。

**修改后 — WaveformView：**

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

### 更新 ContentView

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

### 在引擎中存储最近采样

**文件：** `RecognizerEngine.swift`

```swift
@Published var recentSamples: [Float] = []

private func processAudioChunk(samples: [Float]) {
    // ... 现有代码 ...
    recentSamples = Array(samples.suffix(60))
}
```

---

## 第9节：更多扩展想法

| # | 扩展 | 难度 | 实现提示 |
|---|------|------|---------|
| 1 | **蓝牙智能小车控制** | 中等 | 添加 `CoreBluetooth`。解析识别文字中的指令（"前进"、"停止"、"左转"）。映射到 BLE 特征值写入。添加 `BluetoothManager.swift` 和 `CBCentralManager`。 |
| 2 | **语音指令解析器** | 简单 | 在 `RecognizerEngine` 中使用正则解析：`if text.contains("前进") { sendCommand(.forward) }`。连接到 `CommandExecutor` 协议。 |
| 3 | **文字转语音反馈** | 简单 | 导入 `AVFoundation`。使用 `AVSpeechSynthesizer` 朗读最终识别文字。在设置中添加开关。 |
| 4 | **导出转录文本** | 简单 | 添加分享按钮，导出 `messages.map { $0.text }.joined(separator: "\n")`，通过 `UIActivityViewController` 分享。 |
| 5 | **唤醒词检测** | 高级 | 集成单独的 ONNX 关键词识别模型（如"你好助手"）。并行运行轻量模型；检测到唤醒词后才激活完整 ASR。节省电量。 |
| 6 | **多语言混合** | 中等 | 加载两个识别器（中文 + 英文）。在同一音频流上同时运行。用置信度分数合并结果。 |
| 7 | **本地大语言模型集成** | 高级 | 将最终文字输入设备端 LLM（如 `llama.cpp`、`mlx-swift`）进行问答。将 LLM 回复显示为左对齐气泡。 |
| 8 | **对话历史** | 简单 | 将 `messages` 持久化到 `UserDefaults` 或 SwiftData。启动时加载历史会话。添加日期分段标题。 |

---

## 第10节：蓝牙智能小车控制 — 详细指南

本节说明如何扩展 VoiceToTTS，将语音指令通过蓝牙低功耗（BLE）发送给智能小车。

### 架构

```
语音指令（中文）
       |
       v
+---------------+     +------------------+     +------------------+
| 正则解析器    | --> | 指令枚举         | --> | BLE 管理器       |
| (如 "前进")  |     | .forward, .stop  |     | (CoreBluetooth)  |
+---------------+     +------------------+     +------------------+
                                                       |
                                                       v
                                               +---------------+
                                               | 智能小车 MCU  |
                                               +---------------+
```

### 步骤1：定义指令

创建 `CarCommand.swift`：

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

### 步骤2：创建 BluetoothManager

创建 `BluetoothManager.swift`：

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
            if characteristic.uuid.uuidString == "FFE1" {  // 常用 UART 特征值
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

### 步骤3：解析文字为指令

添加到 `RecognizerEngine.swift`：

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

### 步骤4：串联所有组件

在 `RecognizerEngine.finalizeCurrentText` 中添加：

```swift
if let command = parseCommand(from: text) {
    bluetoothManager.sendCommand(command)
}
```

### 必需的 Info.plist 条目

添加到 `Info.plist`：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to control a smart car.</string>
```

---

## 附录：Git 推送命令

编辑教程或源文件后，提交并推送：

```bash
cd /Users/able/Desktop/app_game/VoiceToTTS_sherpa

# 查看变更
git status

# 暂存新教程
git add VoiceToTTS/TUTORIAL.zh.md

# 提交
git commit -m "docs: 添加 VoiceToTTS 简体中文教案及扩展指南"

# 推送到 GitHub
git push origin main
```

---

*祝你编码愉快！如果你实现了这些扩展，欢迎分享你的分支。*
