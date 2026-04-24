// ContentView.swift
// Main SwiftUI screen — iOS 15+ chat-style voice recognition UI.
// Adapts to notch/Dynamic Island safe area.

import SwiftUI

struct ContentView: View {
    @StateObject private var engine = RecognizerEngine()

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Messages list
                    messagesList

                    // Error banner
                    if let error = engine.errorMessage {
                        errorBanner(error)
                    }

                    // Bottom control bar
                    controlBar
                }
            }
            .navigationTitle("Voice Recognition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !engine.messages.isEmpty {
                        Button("Clear") {
                            engine.clearMessages()
                        }
                        .disabled(engine.state == .listening || engine.state == .recognizing)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            engine.load()
        }
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(engine.messages) { message in
                        MessageBubble(text: message.text, isFinal: message.isFinal, isUser: message.isUser)
                            .id(message.id)
                    }
                    if engine.isSending {
                        TypingIndicatorBubble()
                            .id("typing-indicator")
                    }
                    // Invisible spacer at bottom for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: engine.messages.count) { _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: engine.isSending) { _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 0) {
            Divider()

            // Server config
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("https://api.example.com", text: $engine.serverURL)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // API Token
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
                SecureField("API Token", text: $engine.apiToken)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Chat input bar
            HStack(spacing: 10) {
                // Mic button
                Button {
                    toggleListening()
                } label: {
                    Image(systemName: micIconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(micButtonColor)
                        .frame(width: 36, height: 36)
                }
                .disabled(engine.state == .loading)

                // Text input
                TextField(engine.state == .listening ? "正在听写..." : "输入消息...", text: $engine.draftText)
                    .font(.body)
                    .padding(8)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(18)

                // Send button
                Button {
                    engine.sendDraft()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(engine.draftText.isEmpty || engine.isSending ? Color.gray.opacity(0.5) : .accentColor)
                }
                .disabled(engine.draftText.isEmpty || engine.isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: - Helpers

    private var micIconName: String {
        switch engine.state {
        case .listening, .recognizing:
            return "stop.fill"
        default:
            return "mic.fill"
        }
    }

    private var micButtonColor: Color {
        switch engine.state {
        case .listening, .recognizing:
            return .red
        case .loading:
            return .gray
        default:
            return .accentColor
        }
    }

    private func toggleListening() {
        switch engine.state {
        case .listening, .recognizing:
            engine.stopListening()
        case .idle:
            Task {
                await engine.startListening()
            }
        default:
            break
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let text: String
    let isFinal: Bool
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 40)
            }

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

            if !isUser {
                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorBubble: View {
    var body: some View {
        HStack {
            Spacer(minLength: 40)
            HStack(spacing: 4) {
                Text("AI 正在输入")
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

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
