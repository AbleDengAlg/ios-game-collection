# 📖 Metronome 项目教学文档

> 从零开始，逐行理解这个节拍器 App 的每一行代码

---

## 目录

1. [项目总览](#1-项目总览)
2. [程序入口：MetronomeApp.swift](#2-程序入口metronomeappswift)
3. [核心引擎：MetronomeEngine.swift](#3-核心引擎metronomeengineswift)
4. [用户界面：ContentView.swift](#4-用户界面contentviewswift)
5. [重要语法知识速查](#5-重要语法知识速查)
6. [新手注意事项](#6-新手注意事项)
7. [扩展练习：改成 3/4 拍](#7-扩展练习改成-34-拍)
8. [扩展练习：横条改竖条](#8-扩展练习横条改竖条)
9. [更多扩展思路](#9-更多扩展思路)

---

## 1. 项目总览

```
Metronome/
├── Metronome/
│   ├── MetronomeApp.swift        ← 程序入口（第2节讲）
│   ├── MetronomeEngine.swift     ← 音频+计时引擎（第3节讲）
│   ├── ContentView.swift         ← UI 界面（第4节讲）
│   ├── Resources/
│   │   ├── rim.raw               ← 鼓边音源（16-bit PCM）
│   │   └── cowbell.raw           ← 牛铃声音源（16-bit PCM）
│   └── Assets.xcassets/          ← 图标和颜色资源
└── Metronome.xcodeproj/          ← Xcode 工程文件
```

**运行流程简图：**

```
用户点击 Start
    ↓
ContentView 调用 engine.togglePlay()
    ↓
MetronomeEngine.start()
    ↓
┌─ 播放第1拍声音（Rim 鼓边）
├─ 启动定时器
│   ↓ 每 (60/BPM) 秒
├─ 播放下一个音（Cowbell 牛铃）
├─ 更新 currentBeat → UI 自动刷新
└─ 循环直到用户点 Stop
```

---

## 2. 程序入口：MetronomeApp.swift

```swift
import SwiftUI                          // ① 导入 SwiftUI 框架

@main                                   // ② 标记这是程序入口
struct MetronomeApp: App {              // ③ 遵循 App 协议
    var body: some Scene {              // ④ 必须实现的 body 属性
        WindowGroup {                   // ⑤ 创建一个窗口组
            ContentView()              // ⑥ 在窗口中显示 ContentView
        }
    }
}
```

### 逐行讲解

| 编号 | 代码 | 说明 |
|:---:|---|---|
| ① | `import SwiftUI` | SwiftUI 是 Apple 的 UI 框架，提供按钮、文字、滑动条等组件 |
| ② | `@main` | 告诉系统"从这个结构体开始运行"，一个 App 只能有一个 `@main` |
| ③ | `struct MetronomeApp: App` | `struct` 是值类型；`App` 是协议，要求必须有 `body` |
| ④ | `var body: some Scene` | `some Scene` 表示"某种 Scene 类型"，Swift 自动推断具体类型 |
| ⑤ | `WindowGroup` | 管理应用窗口，iOS 上是全屏，macOS 上可以多窗口 |
| ⑥ | `ContentView()` | 创建我们自定义的主界面视图 |

### 关键语法

- **`struct` vs `class`**：SwiftUI 的 View 都用 `struct`（轻量、值语义）；引擎/数据模型用 `class`（引用语义，可共享状态）
- **`some` 关键字**：不透明返回类型，隐藏具体类型但保证一致性，SwiftUI 中大量使用
- **`@main`**：Swift 5.3+ 的入口标记，替代了以前的 `@UIApplicationMain`

---

## 3. 核心引擎：MetronomeEngine.swift

这是整个项目最核心的文件，分为 6 个区域。

### 3.1 属性声明

```swift
class MetronomeEngine: ObservableObject {
    @Published var isPlaying = false        // ① 是否正在播放
    @Published var currentBeat: Int = -1    // ② 当前拍号 (-1=停止, 0-3=第1-4拍)
    @Published var bpm: Double = 120        // ③ 每分钟拍数
    @Published var volume: Float = 10       // ④ 音量 0-20

    private let audioEngine = AVAudioEngine()           // ⑤ 音频引擎
    private let playerNode = AVAudioPlayerNode()        // ⑥ 播放节点
    private var rimBuffer: AVAudioPCMBuffer?            // ⑦ 鼓边音效缓冲
    private var cowbellBuffer: AVAudioPCMBuffer?        // ⑧ 牛铃音效缓冲
    private var timer: DispatchSourceTimer?             // ⑨ 精确计时器
    private let timerQueue = DispatchQueue(label: "metronome.tick", qos: .userInteractive)
                                                        // ⑩ 高优先级队列
```

| 编号 | 代码 | 说明 |
|:---:|---|---|
| ① | `@Published var isPlaying` | `@Published` 让 UI 自动监听变化，值改变时界面自动刷新 |
| ② | `currentBeat = -1` | -1 表示停止状态，0-3 表示当前播放到哪一拍 |
| ⑤ | `AVAudioEngine` | Apple 的底层音频引擎，比 AVAudioPlayer 更精确 |
| ⑨ | `DispatchSourceTimer` | GCD 定时器，比 Timer 更精确，适合节拍器 |
| ⑩ | `qos: .userInteractive` | 最高优先级，确保节拍准时触发 |

**关键语法：`@Published`**
```swift
// @Published 做了两件事：
// 1. 属性值变化时，自动发送通知（类似发布-订阅模式）
// 2. SwiftUI 的 View 监听到通知后，自动重新渲染 UI
// 这就是为什么 currentBeat 变化时，界面上的横条会自动亮起
```

### 3.2 初始化

```swift
init() {
    setupAudioSession()    // ① 配置音频会话
    setupAudioEngine()     // ② 配置音频引擎
    loadSounds()           // ③ 加载音效文件
}

deinit {                   // ④ 对象销毁时自动调用
    stop()
}
```

### 3.3 音频会话配置

```swift
private func setupAudioSession() {
    #if os(iOS)            // ① 条件编译：仅在 iOS 上执行
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
    try? AVAudioSession.sharedInstance().setActive(true)
    #endif
}
```

| 语法 | 说明 |
|---|---|
| `#if os(iOS)` | 条件编译，iOS 和 macOS 用不同的音频 API |
| `.playback` | 告诉系统"我要播放音频"，即使静音模式也会响 |
| `.mixWithOthers` | 允许和其他 App 的音频共存 |
| `try?` | 尝试执行，如果出错不崩溃，返回 nil |

### 3.4 音频引擎配置

```swift
private func setupAudioEngine() {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!  // ①
    audioEngine.attach(playerNode)                    // ② 把播放节点挂到引擎上
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)  // ③ 连接到混音器
    try? audioEngine.start()                          // ④ 启动引擎
}
```

| 编号 | 说明 |
|:---:|---|
| ① | 44100Hz 采样率，单声道。`!` 强制解包（因为参数合法，不会为 nil） |
| ② | `attach` 类似"插线"，把节点接入音频处理图 |
| ③ | `connect` 把播放节点连到混音器输出，format 指定音频格式 |
| ④ | 引擎必须 `start()` 才能工作 |

### 3.5 加载音效（最重要的函数之一）

```swift
private func loadPCMBuffer(resource name: String, extension ext: String) -> AVAudioPCMBuffer? {
    // 第1步：从 Bundle 中找到文件
    guard let url = Bundle.main.url(forResource: name, withExtension: ext),
          let data = try? Data(contentsOf: url) else {
        print("Failed to load \(name).\(ext)")
        return nil
    }

    // 第2步：计算采样数（每个采样占2字节=16bit）
    let sampleCount = data.count / 2

    // 第3步：创建 PCM 缓冲区
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
        return nil
    }

    // 第4步：Int16 转 Float（-32767~32767 → -1.0~1.0）
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
```

**数据转换流程：**
```
原始 C 头文件 (Rim.h)          Python 转换            Swift 加载
┌─────────────────┐      ┌──────────────┐      ┌──────────────────┐
│ short DRim[] = { │ ──→  │ rim.raw      │ ──→  │ AVAudioPCMBuffer │
│   0,108,171,...  │      │ (二进制文件)  │      │ (Float 格式)     │
│ }                │      │              │      │                  │
│ Int16: -32768    │      │ 2字节/采样    │      │ Float: -1.0~1.0  │
│       ~32767     │      │              │      │                  │
└─────────────────┘      └──────────────┘      └──────────────────┘
```

**关键语法：`withUnsafeBytes`**
- Swift 默认是内存安全的，但处理原始音频数据需要直接操作内存
- `withUnsafeBytes` 提供一个闭包，在闭包内可以安全地访问原始字节
- `assumingMemoryBound(to: Int16.self)` 告诉编译器"把这些字节当作 Int16 数组来读"

### 3.6 播放控制

```swift
func togglePlay() {          // 切换播放/停止
    if isPlaying { stop() } else { start() }
}

func start() {
    guard !isPlaying, rimBuffer != nil, cowbellBuffer != nil else { return }  // ① 安全检查

    isPlaying = true
    currentBeat = 0           // 从第1拍开始
    playerNode.play()          // 开始播放
    playCurrentBeat()          // 立刻播放第1拍
    startTimer()               // 启动定时器，之后每拍自动触发
}

func stop() {
    isPlaying = false
    currentBeat = -1           // -1 表示停止
    timer?.cancel()            // 停止定时器
    timer = nil                // 释放定时器
    playerNode.stop()          // 停止播放节点
}
```

**关键语法：`guard`**
```swift
guard !isPlaying, rimBuffer != nil, cowbellBuffer != nil else { return }
// 等价于：
// if isPlaying { return }
// if rimBuffer == nil { return }
// if cowbellBuffer == nil { return }
// guard 更简洁，把"不满足条件就退出"写在前面，让正常逻辑保持在主路径
```

### 3.7 定时器（节拍器的核心！）

```swift
private func startTimer() {
    timer?.cancel()                                    // ① 先停掉旧定时器
    let interval = 60.0 / bpm                          // ② 计算每拍间隔（秒）
    timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)  // ③ 创建严格定时器
    timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))  // ④
    timer?.setEventHandler { [weak self] in             // ⑤ 设置回调
        guard let self, self.isPlaying else { return }
        let next = (self.currentBeat + 1) % 4          // ⑥ 计算下一拍
        self.playBeat(next)                             // ⑦ 播放声音
        DispatchQueue.main.async {                      // ⑧ 回到主线程更新 UI
            self.currentBeat = next
        }
    }
    timer?.resume()                                     // ⑨ 启动定时器
}
```

| 编号 | 说明 |
|:---:|---|
| ② | `60.0 / 120 = 0.5秒`，即 120BPM 时每0.5秒一拍 |
| ③ | `.strict` 标志让定时器尽量精确；`timerQueue` 是高优先级队列 |
| ④ | `leeway: .milliseconds(1)` 允许1毫秒误差，比默认更精确 |
| ⑤ | `[weak self]` 防止循环引用，避免内存泄漏 |
| ⑥ | `% 4` 取模运算，0→1→2→3→0→1... 循环 |
| ⑧ | **UI 更新必须在主线程！** 计时器在后台线程执行 |

**关键语法：`[weak self]`**
```swift
// 闭包会强引用 self，self 也持有 timer，形成循环引用：
// self → timer → closure → self → timer → ...
// [weak self] 打破循环：闭包弱引用 self，self 可以被释放
// 用 guard let self 解包，如果 self 已销毁就安全退出
```

### 3.8 播放声音

```swift
private func playBeat(_ beat: Int) {
    let buffer = beat == 0 ? rimBuffer : cowbellBuffer   // ① 三元运算符
    guard let buffer else { return }                       // ② 可选值解包
    playerNode.volume = volume / 20.0                      // ③ 音量映射
    playerNode.scheduleBuffer(buffer, at: nil, options: []) // ④ 调度播放
}
```

| 编号 | 说明 |
|:---:|---|
| ① | `beat == 0 ? rimBuffer : cowbellBuffer`：第1拍用鼓边，其余用牛铃 |
| ③ | `10 / 20.0 = 0.5`，把 0-20 映射到 0.0-1.0 |
| ④ | `scheduleBuffer` 把音频数据排队等待播放，`at: nil` 表示立即播放 |

---

## 4. 用户界面：ContentView.swift

### 4.1 主视图结构

```swift
struct ContentView: View {                    // ① 遵循 View 协议
    @StateObject private var engine = MetronomeEngine()  // ② 创建并持有引擎

    var body: some View {                    // ③ 必须实现的 body
        ZStack {                             // ④ 层叠布局
            Color.black.ignoresSafeArea()    // ⑤ 全黑背景

            VStack(spacing: 28) {            // ⑥ 垂直排列，间距28
                Spacer()                     // ⑦ 弹性空间（推到中间）

                // 标题区域
                // 节拍指示条
                // BPM 控制
                // 音量控制
                // 播放按钮

                Spacer()
            }
        }
    }
}
```

**关键语法：`@StateObject` vs `@ObservedObject`**
```swift
@StateObject   → 自己创建并拥有这个对象（整个生命周期保持）
@ObservedObject → 别人传给我的对象（不负责创建和销毁）

// 这里 ContentView 创建引擎，所以用 @StateObject
// 如果引擎从父视图传入，就用 @ObservedObject
```

### 4.2 BPM 滑动条

```swift
Slider(value: $engine.bpm, in: 40...240, step: 1) { editing in
    if !editing { engine.setBPM(engine.bpm) }
}
```

**关键语法：`$` 绑定**
```swift
// engine.bpm 是普通属性，读取值
// $engine.bpm 是"绑定"（Binding），双向连接：
//   - 滑动条改变 → 自动更新 engine.bpm
//   - engine.bpm 改变 → 滑动条位置自动更新
// `editing` 参数：true=用户正在拖动，false=用户松手
// 只在松手时调用 setBPM()，避免拖动时频繁重启定时器
```

### 4.3 BeatBar 组件

```swift
struct BeatBar: View {
    let beat: Int           // 拍号 1-4
    let isActive: Bool      // 是否当前拍
    let isAccent: Bool      // 是否重拍（第1拍）

    private var activeColor: Color {    // 计算属性
        isAccent ? .orange : .cyan      // 重拍橙色，普通拍青色
    }

    var body: some View {
        HStack(spacing: 14) {          // 水平排列
            Circle()                    // 圆点指示器
                .fill(isActive ? Color.white : Color.gray.opacity(0.3))
                .frame(width: 14, height: 14)
                .shadow(color: isActive ? activeColor : .clear, radius: 8)

            Text("\(beat)")             // 拍号文字
                .font(.title3.bold())
                .foregroundColor(isActive ? .white : .gray)

            Spacer()                    // 填充剩余空间
        }
        .padding(.horizontal, 20)       // 内边距
        .padding(.vertical, 14)
        .background(                    // 背景
            RoundedRectangle(cornerRadius: 14)
                .fill(isActive ? activeColor.opacity(0.35) : Color.white.opacity(0.06))
        )
        .overlay(                       // 边框
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? activeColor.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1.5)
        )
        .scaleEffect(isActive ? 1.04 : 1.0)     // 激活时放大4%
        .animation(.easeInOut(duration: 0.1), value: isActive)  // 动画
    }
}
```

**关键语法：SwiftUI 修饰符链**
```swift
// SwiftUI 用"修饰符链"来配置视图，从上到下依次应用：
Text("Hello")
    .font(.title)           // 设置字体
    .foregroundColor(.white) // 设置颜色
    .padding()               // 添加内边距
    .background(Color.blue)  // 设置背景

// 注意顺序！padding 在 background 前面，
// 意味着蓝色背景会包含 padding 的空间
```

---

## 5. 重要语法知识速查

### 5.1 Swift 关键字表

| 关键字 | 作用 | 本项目用法 |
|---|---|---|
| `@main` | 标记程序入口 | `MetronomeApp` |
| `@Published` | 属性变化时自动通知 UI | `isPlaying`, `currentBeat`, `bpm`, `volume` |
| `@StateObject` | 创建并持有可观察对象 | `engine = MetronomeEngine()` |
| `some` | 隐藏具体类型 | `some View`, `some Scene` |
| `guard` | 条件不满足就提前退出 | `guard !isPlaying else { return }` |
| `private` | 只在当前类型内可见 | 所有内部函数 |
| `let` vs `var` | 常量 vs 变量 | `let beat`（不变），`var bpm`（可变） |
| `?` | 可选值（可能为 nil） | `rimBuffer: AVAudioPCMBuffer?` |
| `!` | 强制解包 | `format!`（确定不为 nil 时用） |
| `$` | 创建绑定 | `$engine.bpm` |

### 5.2 SwiftUI 核心布局

```
VStack  → 垂直排列（竖着排）     ┃ 1 ┃
                                 ┃ 2 ┃
                                 ┃ 3 ┃

HStack  → 水平排列（横着排）     ┃ 1 ┃ 2 ┃ 3 ┃

ZStack  → 层叠排列（叠起来）     ┃ 底层 ┃
                                 ┃ 中层 ┃
                                 ┃ 顶层 ┃

Spacer  → 弹性空白              ┃      大空白      ┃
```

---

## 6. 新手注意事项

### ⚠️ 必须记住的 5 件事

1. **UI 更新必须在主线程**
   ```swift
   // ❌ 错误：定时器在后台线程，直接改 UI 属性可能崩溃
   self.currentBeat = next

   // ✅ 正确：回到主线程再更新
   DispatchQueue.main.async {
       self.currentBeat = next
   }
   ```

2. **避免循环引用**
   ```swift
   // ❌ 错误：闭包强引用 self，造成内存泄漏
   timer?.setEventHandler { self.playBeat(next) }

   // ✅ 正确：用 [weak self] 打破循环
   timer?.setEventHandler { [weak self] in
       guard let self else { return }
       self.playBeat(next)
   }
   ```

3. **音频文件必须加入项目**
   - `rim.raw` 和 `cowbell.raw` 必须在 Xcode 的项目导航器中可见
   - 如果用文件系统直接复制，要在 Xcode 中右键 → Add Files
   - 确认 Target Membership 勾选了 Metronome

4. **`try?` vs `try!` vs `try`**
   ```swift
   try?  // 出错返回 nil，不崩溃（适合初始化等非关键操作）
   try!  // 出错直接崩溃（只在100%确定不会出错时用）
   try   // 必须配合 do-catch 处理错误
   ```

5. **Slider 的 `editing` 回调很重要**
   ```swift
   // 如果不加 editing 判断，用户拖动 BPM 滑条时会疯狂重启定时器
   // 导致节拍不稳甚至卡顿
   Slider(value: $engine.bpm, in: 40...240) { editing in
       if !editing { engine.setBPM(engine.bpm) }  // 只在松手时更新
   }
   ```

---

## 7. 扩展练习：改成 3/4 拍

3/4 拍 = 每小节 3 拍（圆舞曲节奏），只需改 3 个地方：

### 改动 1：MetronomeEngine.swift — 循环取模

```swift
// 原代码（第110行）：
let next = (self.currentBeat + 1) % 4    // 0→1→2→3→0 循环

// 改成：
let next = (self.currentBeat + 1) % 3    // 0→1→2→0 循环（3拍循环）
```

### 改动 2：ContentView.swift — 显示3个节拍条

```swift
// 原代码（第25行）：
ForEach(0..<4, id: \.self) { i in

// 改成：
ForEach(0..<3, id: \.self) { i in
```

### 改动 3：让拍数可配置（进阶）

更好的做法是让 `beatsPerBar` 成为一个可配置属性：

**MetronomeEngine.swift 添加：**
```swift
@Published var beatsPerBar: Int = 4    // 每小节拍数，默认4/4拍
```

**startTimer 中用 beatsPerBar 替代硬编码的 4：**
```swift
let next = (self.currentBeat + 1) % self.beatsPerBar
```

**ContentView 中用 beatsPerBar：**
```swift
ForEach(0..<engine.beatsPerBar, id: \.self) { i in
```

**添加拍数选择器（UI）：**
```swift
Picker("拍数", selection: $engine.beatsPerBar) {
    Text("2/4").tag(2)
    Text("3/4").tag(3)
    Text("4/4").tag(4)
    Text("6/8").tag(6)
}
.pickerStyle(.segmented)
```

---

## 8. 扩展练习：横条改竖条

把水平的 4 条改成竖直的 4 条并排，类似 DJ 打碟机的视觉效果。

### 改动：ContentView.swift — BeatBar 组件

把原来的 `BeatBar` 替换为新的 `BeatColumn`：

```swift
// ============ 替换原来的 BeatBar ============

struct BeatColumn: View {
    let beat: Int
    let isActive: Bool
    let isAccent: Bool

    private var activeColor: Color {
        isAccent ? .orange : .cyan
    }

    var body: some View {
        VStack(spacing: 6) {              // 改为垂直排列
            // 拍号
            Text("\(beat)")
                .font(.caption.bold())
                .foregroundColor(isActive ? .white : .gray)

            // 竖条
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? activeColor : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? activeColor.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1)
                )
                .frame(width: 50, height: isActive ? 140 : 120)   // 激活时更高
                .shadow(color: isActive ? activeColor.opacity(0.5) : .clear, radius: 10)
                .animation(.easeInOut(duration: 0.1), value: isActive)
        }
    }
}
```

然后在 `ContentView` 的节拍指示区替换为：

```swift
// 替换原来的 VStack + BeatBar 部分：
HStack(spacing: 16) {                                    // 改为水平排列竖条
    ForEach(0..<4, id: \.self) { i in
        BeatColumn(
            beat: i + 1,
            isActive: engine.isPlaying && engine.currentBeat == i,
            isAccent: i == 0
        )
    }
}
.padding(.horizontal, 24)
.frame(height: 180)                                      // 给竖条留足高度
```

### 视觉对比

```
原来（横条）：              改后（竖条）：
┌──────────────────┐       ┌──┐ ┌──┐ ┌──┐ ┌──┐
│ ● 1              │       │ 1│ │ 2│ │ 3│ │ 4│
└──────────────────┘       │  │ │  │ │  │ │  │
┌──────────────────┐       │  │ │  │ │  │ │  │
│   2              │       │██│ │  │ │  │ │  │  ← 第1拍亮起
└──────────────────┘       └──┘ └──┘ └──┘ └──┘
┌──────────────────┐
│   3              │       像DJ打碟机的竖条效果
└──────────────────┘       重拍更高、更亮
┌──────────────────┐
│   4              │
└──────────────────┘
```

---

## 9. 更多扩展思路

| 扩展方向 | 实现思路 |
|---|---|
| 添加更多音色 | 在 `Resources/` 放入更多 .raw 文件，用 `loadPCMBuffer` 加载 |
| 摇摆节奏（Swing） | 偶数拍延迟一点播放，修改 `startTimer` 中的 interval |
| 节拍细分（8分音符） | 让定时器频率翻倍，每2次触发算1拍 |
| 保存预设 | 用 `UserDefaults` 保存用户常用的 BPM 和音量 |
| Tap Tempo | 添加一个按钮，连续点击自动计算 BPM |
| 闪烁动画 | 用 `.opacity()` 和 `.animation()` 让节拍条有渐隐效果 |
| Apple Watch 版 | 用 WatchKit 框架，界面更简洁 |
| 蓝牙踏板控制 | 通过 CoreBluetooth 连接蓝牙踏板来启停 |

---

## 附录：上传到 GitHub 的命令

完成修改后，在终端依次执行：

```bash
# 1. 进入项目根目录
cd /Users/able/Desktop/app_game

# 2. 查看改了哪些文件（可选，确认一下）
git status

# 3. 暂存所有更改
git add .

# 4. 提交，写上你做了什么
git commit -m "你的提交说明，比如：Add tutorial document and 3/4 time signature"

# 5. 推送到 GitHub
git push
```

---

> 💡 **学习建议**：不要只看代码，动手改！改一个数字、换一个颜色、增加一个按钮，观察效果。编程最有效的学习方式就是 **实验**。
