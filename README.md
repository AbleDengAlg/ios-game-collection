# 🎮 iOS Game & Tool Collection

A collection of classic mini-games and AI-powered tools built with SwiftUI. Currently featuring **Guess Number**, **Metronome**, **Spleeter App** (Audio Separation), **VoiceToTTS** (Speech-to-Text), and **VoiceToTTS AI Chat** (Cross-platform AI Assistant), with more coming soon!

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-iOS%2017+-blue.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20macOS-lightgrey.svg)](https://developer.apple.com)

## 🎯 Projects Included

### 1. Guess Number (猜数字)
A classic number guessing game where you try to guess a randomly generated number between 1 and 200.

**Features:**
- 🎲 Random number generation (1-200)
- 📊 Guess history tracking
- 💡 Hints (too high / too low)
- 🏆 Victory celebration with attempt count
- 🎨 Clean, modern SwiftUI interface

**How to Play:**
1. Tap "开始游戏" (Start Game)
2. Enter your guess (1-200)
3. Get hints and keep guessing
4. Try to guess the number in as few attempts as possible!

### 2. Metronome (节拍器)
A professional metronome with real drum sounds (Rim & Cowbell), accurate timing, and a sleek dark UI.

**Features:**
- 🥁 Real drum sounds (Rim accent + Cowbell)
- ⏱️ Precise timing with DispatchSource timer
- 🎵 4/4 time signature with beat indicators
- 🔊 Volume control (0-20)
- 🏃 BPM range: 40-240
- 🎨 Dark theme with animated beat bars
- 📱 Works on iPhone, iPad, and Mac

**How to Use:**
1. Adjust BPM and Volume with the sliders
2. Tap "Start" to begin
3. Beat 1 (accent) plays a Rim sound, beats 2-4 play Cowbell
4. Watch the beat bars light up in rhythm!

📖 [Metronome Tutorial / 项目教学文档](Metronome/TUTORIAL.md) — Learn the code line by line!

### 3. Spleeter App (音频分离)
An offline AI-powered vocal & accompaniment separation app. Uses Spleeter INT8 ONNX models via sherpa-onnx C API + ONNX Runtime.

**Features:**
- 🎤 AI vocal/accompaniment separation (Spleeter 2-stems INT8)
- 🔒 Fully offline — no internet required
- 📱 Dual platform: iOS (iPhone/iPad) + macOS
- 🎵 WAV file input, play & save separated stems
- ⚡ Background thread inference, smooth UI
- 🎨 Platform-adaptive layouts (iOS scroll + macOS windowed)

**How to Use:**
1. Tap "Select WAV File" to choose an audio file
2. Tap "Separate Audio" to run AI inference
3. Listen to separated Vocals & Accompaniment independently
4. Save stems to your Documents folder

**⚠️ Note:** Requires downloading Spleeter INT8 ONNX models (~50MB) before first use.

📖 [Spleeter Tutorial / 项目教学文档](spleeter_onnx_sherpa/SpleeterApp/TUTORIAL.md) — Learn the code line by line!

### 4. VoiceToTTS (语音转文字)
An offline real-time Chinese speech-to-text app using sherpa-onnx streaming Zipformer-CTC INT8 model. Speak into the microphone and see text appear in chat bubbles instantly.

**Features:**
- 🎙️ Real-time streaming ASR — text appears as you speak
- 🔒 Fully offline — no network, no cloud, all local inference
- 📱 iOS 15+ with notch/Dynamic Island safe area support
- 💬 Chat-style UI with incremental and finalized message bubbles
- 🧠 Endpoint detection — automatically segments sentences
- ⚡ 16kHz mono audio processing with AVAudioEngine

**How to Use:**
1. Launch the app (model loads automatically on startup)
2. Tap the microphone button to start listening
3. Speak in Chinese — text appears in real-time bubbles
4. Stop speaking to finalize the current sentence
5. Tap the stop button to end the session

**⚠️ Note:** Requires downloading the sherpa-onnx streaming Zipformer-CTC Chinese INT8 model (~30MB) before first use.

📖 [VoiceToTTS Tutorial / 英文教学文档](VoiceToTTS_sherpa/VoiceToTTS/TUTORIAL.md) — Learn the code line by line!

📖 [VoiceToTTS 教案 / 简体中文教学文档](VoiceToTTS_sherpa/VoiceToTTS/TUTORIAL.zh.md) — 逐行学习代码！

### 5. VoiceToTTS AI Chat (跨平台 AI 助手)
A cross-platform AI voice assistant. Speak to your iPhone, send the transcribed text to a Python FastAPI backend over LAN, and receive AI-generated replies in a WeChat-style chat interface.

**Features:**
- 🎙️ Offline speech-to-text (sherpa-onnx streaming ASR)
- 💬 WeChat-style chat UI — editable draft, send button, typing indicator
- 🌐 LAN communication between iPhone and computer (same WiFi)
- 🤖 Pluggable AI backend — swap between local FastAPI demo or real AI server
- 🔐 Token-based API authentication
- ⏱️ 130s client timeout for long AI inference
- 🐍 Python FastAPI backend with CORS support

**How to Use:**
1. Start the Python FastAPI backend: `uvicorn test_fastapi:app --host 0.0.0.0 --port 8000`
2. Enter the server IP and API Token in the iOS app
3. Tap the microphone button and speak
4. Edit the recognized text if needed, then tap send
5. Watch the AI reply appear in a left-aligned bubble

**⚠️ Note:** Requires downloading the sherpa-onnx streaming Zipformer-CTC Chinese INT8 model (~30MB). Server address and token are configured in-app (not hardcoded) to avoid leaking credentials.

📖 [Backend Tutorial / 后端教程](VoiceToTTS_python_reponse/python_fastapi/BACKEND_TUTORIAL.md) — Python setup guide!

## 🚀 Getting Started

### Prerequisites
- Xcode 15.0+
- iOS 17.0+
- macOS 14.0+

### Installation

1. Clone the repository:
```bash
git clone https://github.com/AbleDengAlg/ios-game-collection.git
```

2. Open a project in Xcode:
```bash
# Guess Number
cd ios-game-collection/guessNumber && open guessNumber.xcodeproj

# Metronome
cd ios-game-collection/Metronome && open Metronome.xcodeproj

# Spleeter App (Audio Separation)
cd ios-game-collection/spleeter_onnx_sherpa/SpleeterApp && open SpleeterApp.xcodeproj

# VoiceToTTS (Speech-to-Text)
cd ios-game-collection/VoiceToTTS_sherpa/VoiceToTTS && open VoiceToTTS.xcodeproj

# VoiceToTTS AI Chat (Cross-platform AI Assistant)
cd ios-game-collection/VoiceToTTS_python_reponse/VoiceToTTS && open VoiceToTTS.xcodeproj
```

3. Build and run (⌘+R) on your iOS Simulator or device

**⚠️ Important for Spleeter App:**
- Download Spleeter INT8 ONNX models before building
- Models must be added to `SpleeterApp` target's Copy Bundle Resources

**⚠️ Important for VoiceToTTS:**
- Download the sherpa-onnx streaming Zipformer-CTC Chinese INT8 model before building
- Add `model.int8.onnx`, `tokens.txt`, and `bbpe.model` to `VoiceToTTS` target's Copy Bundle Resources
- Microphone access requires a physical iOS device (simulator has limited audio input support)

**⚠️ Important for VoiceToTTS AI Chat:**
- Download the sherpa-onnx model as above
- Start the Python backend first before running the iOS app
- Ensure iPhone and computer are on the same WiFi network
- Enter the correct server IP and API Token in the app

## 📱 Screenshots

| Guess Number | Metronome | Spleeter App | VoiceToTTS AI Chat |
|:---:|:---:|:---:|:---:|
| 🎯 | 🎵 | 🎤 | 🤖 |

## 🗺️ Roadmap

- [x] Guess Number (猜数字)
- [x] Metronome (节拍器)
- [x] Spleeter App (音频分离)
- [x] VoiceToTTS (语音转文字)
- [x] VoiceToTTS AI Chat (跨平台 AI 助手)
- [ ] Tic-Tac-Toe (井字棋)
- [ ] 2048
- [ ] Snake (贪吃蛇)
- [ ] Flappy Bird style game
- [ ] Memory Match (记忆配对)
- [ ] Sudoku (数独)
- [ ] Minesweeper (扫雷)
- [ ] Tetris (俄罗斯方块)
- [ ] And more... (目标：100个游戏！)

## 🛠️ Tech Stack

- **Framework:** SwiftUI
- **Language:** Swift 5.9+
- **Audio:** AVAudioEngine (Metronome), AVAudioPlayer + AVFoundation (Spleeter)
- **AI Inference:** ONNX Runtime + sherpa-onnx C API (Spleeter, VoiceToTTS)
- **Backend:** Python + FastAPI (VoiceToTTS AI Chat)
- **Data Persistence:** SwiftData
- **Architecture:** MVVM

## 🤝 Contributing

Contributions are welcome! Feel free to submit issues and pull requests.

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

Created by [Able](https://github.com/AbleDengAlg)

---

⭐ Star this repo if you like it!
