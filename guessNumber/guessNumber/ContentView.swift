import SwiftUI

// MARK: - Game State
// 三种游戏状态：开始、进行中、胜利
enum GameState {
    case start
    case playing
    case won
}

// MARK: - Main View
struct ContentView: View {
    @State private var gameState: GameState = .start
    @State private var targetNumber: Int = 0
    @State private var inputText: String = ""
    @State private var guessHistory: [GuessRecord] = []
    @State private var message: String = ""

    var body: some View {
        ZStack {
            // Background
            Color(.gray.opacity(0.1))
                .ignoresSafeArea()

            switch gameState {
            case .start:
                startView
            case .playing:
                playingView
            case .won:
                wonView
            }
        }
    }

    // MARK: - Start View
    var startView: some View {
        VStack(spacing: 30) {
            Spacer()

            Text("🎯")
                .font(.system(size: 80))

            Text("猜数字游戏")
                .font(.system(size: 36, weight: .bold))

            Text("电脑想了一个 1~200 的数字\n你来猜猜看！")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: startGame) {
                Text("开始游戏")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .frame(width: 200, height: 50)
                    .background(Color.green)
                    .cornerRadius(25)
            }

            Spacer()
        }
    }

    // MARK: - Playing View
    var playingView: some View {
        VStack(spacing: 20) {
            // Message
            Text(message)
                .font(.title2.bold())
                .foregroundColor(messageColor)
                .frame(height: 40)
                .padding(.top, 20)

            // Input area
            HStack {
                TextField("输入 1~200", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 150)
                    .font(.title3)

                Button("猜!") {
                    submitGuess()
                }
                .font(.title3.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(10)
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal)

            // Guess history
            if !guessHistory.isEmpty {
                List {
                    Section(header: Text("猜测记录")) {
                        ForEach(guessHistory) { record in
                            HStack {
                                Text("#\(record.id)")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40)
                                Text("\(record.number)")
                                    .font(.title3.bold())
                                    .frame(width: 50)
                                Text(record.hint)
                                    .foregroundColor(record.color)
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            Spacer()
        }
    }

    // MARK: - Won View
    var wonView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🎉")
                .font(.system(size: 80))

            Text("太棒了！")
                .font(.system(size: 36, weight: .bold))

            Text("答案就是 \(targetNumber)")
                .font(.title2)

            Text("你一共猜了 \(guessHistory.count) 次")
                .font(.title3)
                .foregroundColor(.secondary)

            // Show history summary
            VStack(alignment: .leading, spacing: 8) {
                Text("猜测过程:")
                    .font(.headline)
                ScrollView {
                    ForEach(guessHistory) { record in
                        HStack {
                            Text("#\(record.id)")
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)
                            Text("\(record.number)")
                                .bold()
                                .frame(width: 40, alignment: .leading)
                            Text(record.hint)
                                .foregroundColor(record.color)
                        }
                        .font(.subheadline)
                    }
                }
                .frame(maxHeight: 200)
            }
            .padding()
            .background(Color(.gray.opacity(0.1)))
            .cornerRadius(12)
            .padding(.horizontal)

            Button("再来一局") {
                resetGame()
            }
            .font(.title2.bold())
            .foregroundColor(.white)
            .frame(width: 200, height: 50)
            .background(Color.blue)
            .cornerRadius(25)

            Spacer()
        }
    }

    // MARK: - Game Logic

    func startGame() {
        targetNumber = Int.random(in: 1...200)
        guessHistory = []
        message = "我已经想好了，开始猜吧！"
        inputText = ""
        gameState = .playing
    }

    func submitGuess() {
        guard let guess = Int(inputText), guess >= 1, guess <= 200 else {
            message = "请输入 1~200 的数字"
            return
        }

        let hint: String
        let color: Color

        if guess < targetNumber {
            hint = "⬆️ 太小了"
            color = .blue
            message = "太小了，再大一点！"
        } else if guess > targetNumber {
            hint = "⬇️ 太大了"
            color = .red
            message = "太大了，再小一点！"
        } else {
            hint = "✅ 正确！"
            color = .green
            guessHistory.append(GuessRecord(id: guessHistory.count + 1, number: guess, hint: hint, color: color))
            gameState = .won
            inputText = ""
            return
        }

        guessHistory.append(GuessRecord(id: guessHistory.count + 1, number: guess, hint: hint, color: color))
        inputText = ""
    }

    func resetGame() {
        gameState = .start
    }

    var messageColor: Color {
        if message.contains("小") { return .green }
        if message.contains("大") { return .red }
        return .primary
    }
}

// MARK: - Guess Record Model
struct GuessRecord: Identifiable {
    let id: Int
    let number: Int
    let hint: String
    let color: Color
}

// MARK: - Preview
#Preview {
    ContentView()
}

