# 🎮 iOS Game Collection

A collection of classic mini-games and tools built with SwiftUI. Currently featuring **Guess Number** and **Metronome**, with more coming soon!

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-iOS%2017+-blue.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 🎯 Games Included

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
```

3. Build and run (⌘+R) on your iOS Simulator or device

## 📱 Screenshots

| Guess Number | Metronome |
|:---:|:---:|
| 🎯 | 🎵 |

## 🗺️ Roadmap

- [x] Guess Number (猜数字)
- [x] Metronome (节拍器)
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
- **Audio:** AVAudioEngine (Metronome)
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
