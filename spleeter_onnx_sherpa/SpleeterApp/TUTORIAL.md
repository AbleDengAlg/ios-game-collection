# Spleeter App — 完整教学文档

> **适合人群**：有一点 Swift 基础、想学习如何把 AI 模型集成进 iOS/macOS App 的开发者。
> 本文档会逐行解释每一个文件，带你从零看懂整个项目。

---

## 第一节：项目总览 (Project Overview)

### 文件树

```
SpleeterApp/
├── SpleeterApp/                        ← 源码目录
│   ├── SpleeterAppApp.swift            ← ① App 入口，程序从这里启动
│   ├── ContentView.swift               ← ② 主界面，UI 逻辑全在这里
│   ├── SeparatorEngine.swift           ← ③ 核心引擎，管理 AI 推理状态
│   ├── SherpaOnnx.swift                ← ④ AI 底层封装（音频读写 + 模型调用）
│   ├── AudioPicker.swift               ← ⑤ iOS 文件选择器（系统文件浏览）
│   ├── AudioPlayer.swift               ← ⑥ 音频播放器（播放分离结果）
│   ├── SherpaOnnx-Bridging-Header.h    ← ⑦ C 与 Swift 的桥接头文件
│   └── Assets.xcassets/               ← 图标和颜色资源
├── sherpa-onnx-spleeter-2stems-int8/   ← AI 模型文件目录
│   ├── vocals.int8.onnx                ← 人声分离模型（INT8 量化版）
│   └── accompaniment.int8.onnx        ← 伴奏分离模型（INT8 量化版）
└── TUTORIAL.md                         ← 本文档
```

### 数据流图（用户选歌 → AI 分离 → 播放保存）

```
用户点击"Select WAV File"
         │
         ▼
  AudioPicker (iOS)         ← 系统文件选择器弹出
  fileImporter  (macOS)     ← macOS 原生打开面板
         │
         │  URL (文件路径)
         ▼
  ContentView.handlePicked()
         │ 存入 selectedURL
         ▼
  用户点击"Separate Audio"
         │
         ▼
  SeparatorEngine.separate(url:)
         │
         ├─ [主线程] AudioData(url: ..., targetSampleRate: 44100)
         │            用 AVFoundation 读取 WAV、重采样为立体声 44100Hz
         │
         ├─ [后台线程] SourceSeparator.process(buffer:)
         │            调用 C API → ONNX Runtime → 两个 AI 模型推理
         │
         │  返回 [AudioData] (stems[0]=vocals, stems[1]=accompaniment)
         ▼
  @Published vocalsData / accompanimentData  ← SwiftUI 自动刷新 UI
         │
         ▼
  StemCard × 2                              ← 显示人声卡片 + 伴奏卡片
    ├─ Play/Stop → AudioPlayer.play(data:)  ← 写临时 WAV → AVAudioPlayer
    └─ Save      → AudioData.save(to:)      ← 保存到 Documents 目录
```

---

## 第二节：程序入口 (SpleeterAppApp.swift)

### 完整代码（带注释编号）

```swift
// SpleeterAppApp.swift
import SwiftUI                    // ①

@main                             // ②
struct SpleeterAppApp: App {      // ③
    var body: some Scene {        // ④
        WindowGroup {             // ⑤
            ContentView()         // ⑥
        }
    }
}
```

### 注释说明表

| 编号 | 代码 | 解释 |
|------|------|------|
| ① | `import SwiftUI` | 导入 SwiftUI 框架，拥有所有 UI 组件和修饰符 |
| ② | `@main` | 告诉编译器：**这就是程序入口**，整个 App 从这里启动 |
| ③ | `struct SpleeterAppApp: App` | 符合 `App` 协议，是 SwiftUI 的 App 生命周期管理者 |
| ④ | `var body: some Scene` | 描述应用由哪些"场景(Scene)"组成 |
| ⑤ | `WindowGroup` | 创建一个标准窗口（iOS 全屏，macOS 可多窗口） |
| ⑥ | `ContentView()` | 窗口内显示的根视图，程序启动时立即显示它 |

### 关键语法

| 语法 | 含义 |
|------|------|
| `@main` | 标记唯一入口结构体，替代传统的 `main.swift` |
| `some Scene` | 不透明返回类型，编译器会推断具体类型 |
| `struct … : App` | SwiftUI App 协议，必须实现 `body` 属性 |

---

## 第三节：核心引擎 (SeparatorEngine.swift)

这是整个 App 最重要的文件。它负责：管理 AI 模型的状态、调度后台推理任务、把结果发布给 UI。

---

### 3.1 错误类型 `EngineError`

```swift
struct EngineError: Error {           // ①
    let message: String               // ②
    init(_ message: String) {         // ③
        self.message = message
    }
}
```

| 编号 | 解释 |
|------|------|
| ① | 遵守 `Error` 协议，才能用在 `Result<_, EngineError>` 的泛型里 |
| ② | 存储错误描述字符串 |
| ③| 简化构造：`EngineError("出错了")` 而不是 `EngineError(message: "出错了")` |

---

### 3.2 状态枚举 `EngineState`

```swift
enum EngineState: Equatable {         // ①
    case idle                         // ② 空闲
    case loading                      // ③ 加载模型中
    case separating                   // ④ AI 推理中
    case done                         // ⑤ 完成
    case error(String)                // ⑥ 带错误信息的状态

    static func == (lhs: EngineState, rhs: EngineState) -> Bool {  // ⑦
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading),
             (.separating, .separating), (.done, .done):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}
```

| 编号 | 解释 |
|------|------|
| ① | `Equatable` 允许用 `==` 比较，SwiftUI 动画需要它 |
| ②③④⑤ | 四种正常状态，UI 按状态切换按钮样式和文字 |
| ⑥ | 关联值枚举：`.error("描述")` 可携带额外信息 |
| ⑦ | 手动实现 `==`，因为含关联值的枚举默认不满足 Equatable |

> **为什么用枚举而不是 Bool 变量？**
> 枚举保证状态互斥，不会出现"既在 loading 又在 done"的矛盾。

---

### 3.3 引擎主体 `SeparatorEngine`（最重要的类）

```swift
@MainActor                                  // ①
final class SeparatorEngine: ObservableObject { // ②
    @Published var state: EngineState = .idle   // ③
    @Published var vocalsData: AudioData?       // ③
    @Published var accompanimentData: AudioData? // ③
    private var separator: SourceSeparator?     // ④
```

| 编号 | 解释 |
|------|------|
| ① | `@MainActor` 保证所有属性和方法都在主线程执行，UI 更新安全 |
| ② | `ObservableObject` 让 SwiftUI 能监听这个类的变化 |
| ③ | `@Published` = 值改变时自动通知 UI 刷新 |
| ④ | `private` 封装 C 语言模型对象，外部不能直接操作它 |

---

### 3.4 函数：`load()` — 加载 AI 模型

```swift
func load() {
    guard separator == nil else { return }    // ①
    state = .loading                          // ②

    guard
        let vocalsPath = Bundle.main.path(    // ③
            forResource: "vocals.int8", ofType: "onnx"),
        let accompanimentPath = Bundle.main.path(
            forResource: "accompaniment.int8", ofType: "onnx")
    else {
        state = .error("ONNX model files not found…") // ④
        return
    }

    let config = SourceSeparationConfig(      // ⑤
        spleeter: .init(vocals: vocalsPath,
                        accompaniment: accompanimentPath),
        numThreads: 2, debug: false, provider: "cpu"
    )

    guard let sep = SourceSeparator(config: config) else { // ⑥
        state = .error("Failed to initialise…")
        return
    }

    separator = sep                           // ⑦
    state = .idle                             // ⑧
}
```

| 编号 | 解释 |
|------|------|
| ① | 防止重复加载：模型已存在就直接返回 |
| ② | 切换状态 → UI 按钮显示"Loading Model…" |
| ③ | `Bundle.main.path` 从 App 包内找模型文件 |
| ④ | 找不到文件 → 设置错误状态，UI 显示红色警告 |
| ⑤ | 构建 C 层配置对象（模型路径、线程数、运行平台） |
| ⑥ | 创建 `SourceSeparator`，内部调用 C API 初始化 ONNX Runtime |
| ⑦ | 成功后保存实例 |
| ⑧ | 恢复空闲状态，按钮可用 |

---

### 3.5 函数：`separate(url:)` — 运行 AI 推理 ⭐ 最重要

```swift
func separate(url: URL) async {
    guard let sep = separator else { ... }  // ①
    state = .separating                     // ②
    vocalsData = nil
    accompanimentData = nil

    let accessed = url.startAccessingSecurityScopedResource() // ③
    guard let audio = AudioData(url: url, targetSampleRate: 44100) else { // ④
        if accessed { url.stopAccessingSecurityScopedResource() }
        state = .error("Could not read / resample…")
        return
    }
    if accessed { url.stopAccessingSecurityScopedResource() }  // ⑤

    let result: Result<[AudioData], EngineError> =
        await Task.detached(priority: .userInitiated) {        // ⑥
            guard let stems = sep.process(buffer: audio) else {
                return .failure(EngineError("Inference failed…"))
            }
            guard stems.count >= 2 else {
                return .failure(EngineError("Expected 2 stems…"))
            }
            return .success(stems)
        }.value                                                 // ⑦

    switch result {                                             // ⑧
    case .success(let stems):
        vocalsData = stems[0]
        accompanimentData = stems[1]
        state = .done
    case .failure(let err):
        state = .error(err.message)
    }
}
```

| 编号 | 解释 |
|------|------|
| ① | 防御性检查：模型未加载则报错 |
| ② | 设为 separating，按钮变菊花转圈 |
| ③ | macOS 沙箱必须"开门"才能读用户文件 |
| ④ | 用 AVFoundation 读取 WAV，自动重采样到 44100Hz 立体声 |
| ⑤ | 文件读完后立即"关门"释放权限 |
| ⑥ | `Task.detached` 把重计算扔到后台线程，不卡 UI |
| ⑦ | `.value` 等待后台任务完成，拿到 Result |
| ⑧ | 根据成功/失败，更新 @Published 属性 → SwiftUI 自动刷新 |

> **这个函数为什么是整个 App 的核心？**
> 它完成了从"用户文件 URL"到"可播放 AudioData"的全部转换，包括：文件权限管理、音频格式转换、后台线程调度、AI 推理、结果发布——每一步都有错误处理。

---

### 3.6 函数：`reset()` 和 `errorMessage`

```swift
func reset() {
    state = .idle           // 清除状态
    vocalsData = nil        // 清除结果
    accompanimentData = nil
}

var errorMessage: String? {
    if case .error(let msg) = state { return msg } // ①
    return nil
}
```

| 编号 | 解释 |
|------|------|
| ① | 模式匹配提取关联值：只有 `.error(msg)` 状态才返回字符串，其余返回 nil |

---

## 第四节：AI 底层封装 (SherpaOnnx.swift)

### 4.1 `AudioData` — 音频数据容器

这个结构体用两种方式存储音频数据：

```
AudioData.storage
  ├── .owned([Float])     ← Swift 管理的数组（我们自己创建的音频）
  └── .wrapped(ManagedWave) ← C 指针（从 sherpa-onnx C API 读取的音频）
                               ManagedWave.deinit 会自动调用 C 的释放函数
```

**`init?(url:targetSampleRate:)` — 读取并重采样音频**

```swift
init?(url: URL, targetSampleRate: Int = 44100) {
    guard let audioFile = try? AVAudioFile(forReading: url) else { return nil } // ①
    let srcFormat = audioFile.processingFormat                // ②
    let frameCount = AVAudioFrameCount(audioFile.length)      // ③

    guard let dstFormat = AVAudioFormat(                      // ④
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(targetSampleRate),
        channels: 2, interleaved: false
    ) else { return nil }

    // 创建缓冲区 + 转换器
    guard let srcBuffer = AVAudioPCMBuffer(…),
          let converter = AVAudioConverter(from: srcFormat, to: dstFormat)
    else { return nil }

    try audioFile.read(into: srcBuffer)                       // ⑤

    // 重采样到目标格式
    let status = converter.convert(to: dstBuffer, …)          // ⑥

    // 把非交错的 [ch0][ch1] 合并成交错的 [ch0+ch1] 平铺数组
    var flat = [Float](repeating: 0, count: 2 * n)            // ⑦
    flat[0..<n] = ch0 samples
    flat[n..<2n] = ch1 samples
}
```

| 编号 | 解释 |
|------|------|
| ① | 用 AVFoundation 打开任何 macOS/iOS 支持的音频格式 |
| ② | 获取源文件的原始格式（采样率、声道数） |
| ③ | 总帧数（所有声道共享同一个帧计数） |
| ④ | 目标格式：Float32，立体声，44100Hz，非交错 |
| ⑤ | 把文件数据读入内存缓冲区 |
| ⑥ | 核心重采样：自动处理 16kHz→44100Hz、单声道→立体声 等转换 |
| ⑦ | Spleeter 要求平铺格式：前半是左声道，后半是右声道 |

---

### 4.2 `SourceSeparationConfig` — AI 配置构建器

```swift
func withCConfig<R>(
    _ body: (UnsafePointer<SherpaOnnxOfflineSourceSeparationConfig>) -> R
) -> R {
    var cConfig = SherpaOnnxOfflineSourceSeparationConfig()  // ①
    // 设置模型路径（需要把 Swift String 转为 C 字符串）
    var storage: [String: [Int8]] = [:]                      // ②
    func pin(_ key: String, _ value: String?) -> UnsafePointer<Int8>? {
        guard let v = value else { return nil }
        storage[key] = Array(v.utf8CString)                  // ③
        return storage[key]!.withUnsafeBufferPointer { $0.baseAddress }
    }
    cConfig.model.spleeter.vocals = pin("vocals", spleeter?.vocals) // ④
    return body(&cConfig)                                    // ⑤
}
```

| 编号 | 解释 |
|------|------|
| ① | 创建 C 结构体（来自 sherpa-onnx 的 C API） |
| ② | `storage` 字典让 C 字符串在函数结束前保持有效 |
| ③ | `utf8CString` 把 Swift String 转为 `[Int8]`（C 字符串格式） |
| ④ | 把 Swift String 的指针传给 C 结构体字段 |
| ⑤ | 泛型回调模式（withUnsafePointer 风格），确保 C 对象的生命周期 |

---

### 4.3 `SourceSeparator.process()` — 调用 AI 模型

```swift
func process(buffer: AudioData) -> [AudioData]? {
    // 把 Swift AudioData 转为 C 所需的指针数组
    var ptrs: [UnsafePointer<Float>?] = (0..<buffer.channelCount).map {
        UnsafePointer(base + ($0 * buffer.samplesPerChannel)) // ①
    }

    // 调用 C API 执行推理
    guard let raw = SherpaOnnxOfflineSourceSeparationProcess(
        engine, &ptrs, channels, samples, sampleRate         // ②
    ) else { return nil }

    // 把 C 返回的原始结果转为 Swift AudioData
    let result = (0..<stemCount).map { i -> AudioData in      // ③
        let stem = raw.pointee.stems[i]
        // 复制 C 内存 → Swift 数组
        flat.withUnsafeMutableBufferPointer { dest in
            dest[offset...].initialize(from: src, count: n)   // ④
        }
        return AudioData(samples: flat, …)
    }

    SherpaOnnxDestroySourceSeparationOutput(raw)              // ⑤
    return result
}
```

| 编号 | 解释 |
|------|------|
| ① | 计算每个声道的起始内存地址（左声道偏移 0，右声道偏移 n） |
| ② | 调用真正的 AI 推理，内部跑 ONNX Runtime + Spleeter 模型 |
| ③ | `map` 遍历每个分离结果（stems[0]=人声，stems[1]=伴奏） |
| ④ | `initialize(from:count:)` 把 C 内存安全地复制到 Swift 数组 |
| ⑤ | **必须释放**：C API 分配的内存，Swift ARC 不管理，需手动释放 |

---

## 第五节：用户界面 (ContentView.swift)

### 5.1 视图层级结构

```
ContentView
  ├── [iOS]  iosLayout
  │     └── NavigationView
  │           └── ScrollView
  │                 └── mainContent
  │                       ├── headerSection       (图标 + 标题)
  │                       ├── filePickerSection   (选择文件按钮)
  │                       ├── separateSection     (分离按钮)
  │                       ├── resultsSection      (结果卡片×2) ← 仅完成后显示
  │                       └── errorSection        (错误提示)  ← 仅出错后显示
  │
  └── [macOS] macLayout
        └── ScrollView
              └── mainContent (同上)
```

### 5.2 状态属性

```swift
@StateObject private var engine = SeparatorEngine()     // ①
@StateObject private var vocalsPlayer = AudioPlayer()   // ②
@StateObject private var accompPlayer = AudioPlayer()   // ②
@State private var selectedURL: URL?                    // ③
@State private var showPicker = false                   // ③
@State private var shareItem: ShareItem?                // ③
```

| 编号 | 说明 |
|------|------|
| ① | `@StateObject`：由当前视图拥有并初始化，生命周期绑定视图 |
| ② | 两个独立播放器，可以同时播放人声和伴奏，互不干扰 |
| ③ | `@State`：简单值类型状态，只影响当前视图 |

### 5.3 按钮样式的计算属性

```swift
private var buttonLabel: String {        // ①
    switch engine.state {
    case .loading:    return "Loading Model…"
    case .separating: return "Separating…"
    default:          return "Separate Audio"
    }
}

private var separateButtonDisabled: Bool { // ②
    selectedURL == nil
    || engine.state == .separating
    || engine.state == .loading
}
```

| 编号 | 说明 |
|------|------|
| ① | 按状态返回不同文字，SwiftUI 会自动更新 Text 显示 |
| ② | 三个条件任一满足就禁用按钮，防止重复点击 |

### 5.4 `StemCard` — 结果卡片组件

```swift
struct StemCard: View {
    let title: String          // "Vocals" 或 "Accompaniment"
    let iconName: String       // SF Symbols 图标名
    let color: Color           // 紫色(人声) / 青色(伴奏)
    @ObservedObject var player: AudioPlayer  // ①
    let data: AudioData        // 分离后的音频数据
    let filename: String       // 保存时的文件名
    let onShare: (URL) -> Void // ② 保存完后的回调

    // Play/Stop 按钮
    Button {
        if player.isPlaying { player.stop() }
        else { player.play(data: data) }       // ③
    }

    // Save 按钮
    private func saveAndShare() {
        let docs = FileManager.default.urls(for: .documentDirectory, …)[0]
        let dest = docs.appendingPathComponent(filename)  // ④
        if data.save(to: dest.path) { onShare(dest) }     // ⑤
    }
}
```

| 编号 | 说明 |
|------|------|
| ① | `@ObservedObject`：不拥有对象，只观察父视图传入的 player |
| ② | 闭包回调模式：StemCard 不知道怎么分享，交给父视图处理 |
| ③ | 切换播放/停止，player.isPlaying 改变 → 按钮图标自动变化 |
| ④ | `documentDirectory` = 用户可访问的"文稿"目录 |
| ⑤ | 先保存，成功后才触发分享 |

---

## 第六节：音频播放器 (AudioPlayer.swift)

```swift
@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false              // ①
    private var player: AVAudioPlayer?            // ②
    private var tempURL: URL?                     // ③

    func play(data: AudioData) {
        stop()                                    // ④
        let tmp = FileManager.default             // ⑤
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard data.save(to: tmp.path) else { return } // ⑥

        #if os(iOS)
        try AVAudioSession.sharedInstance()
            .setCategory(.playback, mode: .default)   // ⑦
        #endif
        let p = try AVAudioPlayer(contentsOf: tmp)
        p.delegate = self
        p.play()
        isPlaying = true
    }

    nonisolated func audioPlayerDidFinishPlaying(…) { // ⑧
        Task { @MainActor in
            self.isPlaying = false
            self.cleanup()
        }
    }

    private func cleanup() {           // ⑨
        try? FileManager.default.removeItem(at: tempURL!)
        tempURL = nil
    }
}
```

| 编号 | 说明 |
|------|------|
| ① | UI 用 `isPlaying` 决定显示 "Play" 还是 "Stop" 图标 |
| ② | 真正的 AVAudioPlayer 实例，`private` 封装 |
| ③ | 记录临时文件路径，播放完后删除 |
| ④ | 先停止上一次播放，避免多个播放叠加 |
| ⑤ | 写入系统临时目录，用 UUID 保证文件名唯一 |
| ⑥ | AudioData → WAV 文件（AVAudioPlayer 只能读文件，不能读内存） |
| ⑦ | iOS 必须配置音频会话，macOS 不需要 |
| ⑧ | `nonisolated`：代理回调在任意线程，通过 Task 切回主线程更新 UI |
| ⑨ | `private` 清理函数：删除临时文件，释放磁盘空间 |

---

## 第七节：跨平台文件选取 (AudioPicker.swift)

| 平台 | 实现方式 | 代码位置 |
|------|---------|---------|
| iOS | `UIDocumentPickerViewController` | `AudioPicker.swift` |
| macOS | `.fileImporter(isPresented:allowedContentTypes:)` | `ContentView.swift` 内联 |

**iOS 实现核心：**

```swift
struct AudioPicker: UIViewControllerRepresentable {  // ①
    let onPick: (URL) -> Void                        // ②

    func makeUIViewController(…) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.wav, .audio],  // ③
            asCopy: true                             // ④
        )
        picker.delegate = context.coordinator
        return picker
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate { // ⑤
        func documentPicker(_, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls.first!)               // ⑥
        }
    }
}
```

| 编号 | 说明 |
|------|------|
| ① | `UIViewControllerRepresentable`：把 UIKit 控件包裹成 SwiftUI 视图 |
| ② | 回调闭包：文件选好后调用它，传入 URL |
| ③ | 只显示 WAV 和音频类型的文件 |
| ④ | `asCopy: true`：复制文件到沙箱，不需要管理权限 |
| ⑤ | `Coordinator` 是"代理人"，负责接收 UIKit 的回调事件 |
| ⑥ | 把 UIKit 回调转化为 Swift 闭包调用，完成平台桥接 |

---

## 第八节：语法速查表 (Syntax Reference)

| 关键字 / 修饰符 | 作用 | 在本项目中的应用 |
|----------------|------|----------------|
| `@main` | 标记程序入口 | `SpleeterAppApp` |
| `@MainActor` | 保证在主线程执行 | `SeparatorEngine`, `AudioPlayer` |
| `@Published` | 属性变化通知 UI | `state`, `vocalsData`, `isPlaying` |
| `@StateObject` | 视图拥有的引用类型状态 | `engine`, `vocalsPlayer` |
| `@ObservedObject` | 监听外部传入的引用类型 | `StemCard.player` |
| `@State` | 视图私有的值类型状态 | `selectedURL`, `showPicker` |
| `async/await` | 异步并发，不阻塞线程 | `separate(url:)` 函数 |
| `Task.detached` | 在后台线程执行工作 | AI 推理任务 |
| `Result<T, E>` | 显式表示成功或失败 | 推理结果传递 |
| `guard let` | 提前退出的可选绑定 | 模型加载、文件读取 |
| `ObservableObject` | 使类可被 SwiftUI 监听 | `SeparatorEngine`, `AudioPlayer` |
| `#if os(iOS)` | 编译时平台条件 | 区分 iOS/macOS 代码路径 |
| `UIViewControllerRepresentable` | UIKit → SwiftUI 桥接 | `AudioPicker`, `ActivityView` |
| `nonisolated` | 声明方法不在特定 Actor 上 | `audioPlayerDidFinishPlaying` |

### 布局容器速查

```
VStack(spacing: 24)        ← 垂直排列，间距 24pt
  ├── HStack               ← 水平排列
  │     ├── Image(systemName:)  ← SF Symbols 图标
  │     └── Text(...)
  └── ScrollView            ← 内容超出屏幕时可滚动
        └── mainContent     ← 所有卡片在这里竖向排列
```

---

## 第九节：新手注意事项 (Beginner Pitfalls)

### 1. 忘记释放 C 内存

❌ 错误：
```swift
let raw = SherpaOnnxOfflineSourceSeparationProcess(engine, …)
// 直接返回，忘记释放
return convertToSwift(raw)
```

✅ 正确：
```swift
let raw = SherpaOnnxOfflineSourceSeparationProcess(engine, …)
let result = convertToSwift(raw)
SherpaOnnxDestroySourceSeparationOutput(raw)  // ← 必须释放！
return result
```

---

### 2. 在后台线程更新 UI

❌ 错误：
```swift
Task.detached {
    let stems = sep.process(buffer: audio)
    self.vocalsData = stems[0]  // 崩溃！后台线程不能改 @Published
}
```

✅ 正确：
```swift
let stems = await Task.detached {
    return sep.process(buffer: audio)
}.value
// 回到 @MainActor 的 separate() 函数里
vocalsData = stems[0]  // 安全，在主线程
```

---

### 3. 忘记处理 macOS 安全沙箱

❌ 错误：
```swift
// macOS 下直接读用户选的文件，会被沙箱拒绝
let data = try Data(contentsOf: url)
```

✅ 正确：
```swift
let accessed = url.startAccessingSecurityScopedResource()
defer { if accessed { url.stopAccessingSecurityScopedResource() } }
let data = try Data(contentsOf: url)
```

---

### 4. `@StateObject` vs `@ObservedObject` 混用

❌ 错误：
```swift
// 子视图用 @StateObject，每次重绘都会重新创建，丢失播放状态
struct StemCard: View {
    @StateObject var player = AudioPlayer()
}
```

✅ 正确：
```swift
// 父视图创建（@StateObject），子视图只监听（@ObservedObject）
struct StemCard: View {
    @ObservedObject var player: AudioPlayer  // 接受父视图传入的实例
}
```

---

### 5. Spleeter 要求立体声 44100Hz，不能传单声道

❌ 错误：
```swift
// 只取 1 个声道
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                           sampleRate: 44100, channels: 1, ...)
```

✅ 正确：
```swift
// 必须 2 声道，Spleeter 的 C API 对声道数有硬性要求
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                           sampleRate: 44100, channels: 2, ...)
```

---

## 第十节：动手练习 1 — 修改默认线程数

**需求**：把 AI 推理线程从 2 改为 4，让分离速度更快（适合高性能设备）。

**修改文件**：`SeparatorEngine.swift`，第 63 行

| 修改前 | 修改后 |
|--------|--------|
| `numThreads: 2` | `numThreads: 4` |

```swift
// 修改前
let config = SourceSeparationConfig(
    spleeter: .init(vocals: vocalsPath,
                    accompaniment: accompanimentPath),
    numThreads: 2,   // ← 改这里
    debug: false,
    provider: "cpu"
)

// 修改后
let config = SourceSeparationConfig(
    spleeter: .init(vocals: vocalsPath,
                    accompaniment: accompanimentPath),
    numThreads: 4,   // ← 改为 4
    debug: false,
    provider: "cpu"
)
```

> **提示**：线程数不是越多越好。超过设备核心数反而会因为线程切换而变慢。iPhone 15 有 6 核，建议最多设 4。

---

## 第十一节：动手练习 2 — 改变卡片颜色主题

**需求**：把人声卡片从紫色改为橙色，伴奏卡片从青色改为绿色。

**修改文件**：`ContentView.swift`，第 211-228 行

```swift
// 修改前
StemCard(
    title: "Vocals",
    iconName: "mic.fill",
    color: .purple,       // ← 改这里
    ...
)
StemCard(
    title: "Accompaniment",
    iconName: "music.quarternote.3",
    color: .teal,         // ← 改这里
    ...
)

// 修改后
StemCard(
    title: "Vocals",
    iconName: "mic.fill",
    color: .orange,       // ← 橙色
    ...
)
StemCard(
    title: "Accompaniment",
    iconName: "music.quarternote.3",
    color: .green,        // ← 绿色
    ...
)
```

**视觉对比：**

```
修改前：                    修改后：
┌──────────────────┐       ┌──────────────────┐
│ 🎤 Vocals    [紫] │       │ 🎤 Vocals    [橙] │
│  [Play] [Save]   │       │  [Play] [Save]   │
└──────────────────┘       └──────────────────┘
┌──────────────────┐       ┌──────────────────┐
│ 🎵 Accomp   [青] │       │ 🎵 Accomp   [绿] │
│  [Play] [Save]   │       │  [Play] [Save]   │
└──────────────────┘       └──────────────────┘
```

---

## 第十二节：更多扩展方向

| 难度 | 扩展方向 | 实现提示 |
|------|---------|---------|
| ⭐ 简单 | 修改 App 标题显示 | 改 `ContentView` 的 `Text("Spleeter")` |
| ⭐ 简单 | 显示文件时长（秒） | `StemCard` 已有：`data.samplesPerChannel / data.sampleRate` |
| ⭐⭐ 中等 | 支持 MP3 输入 | `UTType.mp3` 加入 `AudioPicker` 的 contentTypes |
| ⭐⭐ 中等 | 批量处理多个文件 | `ContentView` 改 `selectedURL` 为 `[URL]`，循环调用 `separate` |
| ⭐⭐ 中等 | 显示分离进度条 | `SeparatorEngine` 加 `@Published var progress: Double` |
| ⭐⭐⭐ 较难 | 波形可视化 | 读取 `AudioData` 的 Float 数组，用 Canvas 绘制波形 |
| ⭐⭐⭐ 较难 | 4-stem 分离（鼓+贝斯+钢琴+人声） | 换 Spleeter 4stems 模型，处理 `stems.count == 4` |
| ⭐⭐⭐⭐ 高级 | 实时麦克风分离 | 用 `AVAudioEngine` 实时录音，分块送入 `SourceSeparator` |

---

## 附录：Git 提交命令

```bash
# 进入项目目录
cd /Users/able/Desktop/app_game/spleeter_onnx_sherpa

# 查看修改了哪些文件
git status

# 把所有修改加入暂存区
git add .

# 写一条清晰的提交信息
git commit -m "Add TUTORIAL.md - beginner's guide to SpleeterApp"

# 推送到远程仓库
git push
```

---

> 🎉 **恭喜！** 你已经完整阅读了 SpleeterApp 的教学文档。
> 这个 App 展示了 Swift 的很多现代特性：SwiftUI 响应式 UI、Swift Concurrency 异步并发、C 互操作性、以及跨平台（iOS + macOS）代码组织。
> 动手改改颜色、线程数，运行看看效果——这是最快的学习方式！
