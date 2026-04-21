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
                        MessageBubble(text: message.text, isFinal: message.isFinal)
                            .id(message.id)
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
            .onChange(of: engine.currentText) { _ in
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

            HStack(spacing: 16) {
                Spacer()

                // Mic button
                Button {
                    toggleListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(micButtonColor)
                            .frame(width: 64, height: 64)

                        Image(systemName: micIconName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(engine.state == .loading)

                Spacer()
            }
            .padding(.vertical, 16)
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
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.accentColor.opacity(isFinal ? 0.0 : 0.4), lineWidth: 1)
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
