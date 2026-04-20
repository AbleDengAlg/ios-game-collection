import SwiftUI

struct ContentView: View {
    @StateObject private var engine = MetronomeEngine()

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Title
                VStack(spacing: 4) {
                    Text("🎵")
                        .font(.system(size: 48))
                    Text("Metronome")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                // Beat indicators
                VStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { i in
                        BeatBar(
                            beat: i + 1,
                            isActive: engine.isPlaying && engine.currentBeat == i,
                            isAccent: i == 0
                        )
                    }
                }
                .padding(.horizontal, 24)

                // BPM Display & Control
                VStack(spacing: 8) {
                    Text("\(Int(engine.bpm))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("BPM")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Slider(value: $engine.bpm, in: 40...240, step: 1) { editing in
                        if !editing { engine.setBPM(engine.bpm) }
                    }
                    .tint(.orange)
                    .padding(.horizontal, 24)

                    HStack {
                        Text("40").foregroundColor(.gray).font(.caption)
                        Spacer()
                        Text("240").foregroundColor(.gray).font(.caption)
                    }
                    .padding(.horizontal, 28)
                }

                // Volume Control
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundColor(.gray)
                        Text("Volume: \(Int(engine.volume))")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }

                    Slider(value: $engine.volume, in: 0...20, step: 1) { editing in
                        if !editing { engine.setVolume(engine.volume) }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 24)

                    HStack {
                        Text("0").foregroundColor(.gray).font(.caption)
                        Spacer()
                        Text("20").foregroundColor(.gray).font(.caption)
                    }
                    .padding(.horizontal, 28)
                }

                // Play / Stop Button
                Button(action: { engine.togglePlay() }) {
                    HStack(spacing: 10) {
                        Image(systemName: engine.isPlaying ? "stop.fill" : "play.fill")
                            .font(.title2)
                        Text(engine.isPlaying ? "Stop" : "Start")
                            .font(.title2.bold())
                    }
                    .foregroundColor(.white)
                    .frame(width: 200, height: 54)
                    .background(engine.isPlaying ? Color.red : Color.green)
                    .cornerRadius(27)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Beat Bar View

struct BeatBar: View {
    let beat: Int
    let isActive: Bool
    let isAccent: Bool

    private var activeColor: Color {
        isAccent ? .orange : .cyan
    }

    var body: some View {
        HStack(spacing: 14) {
            // Indicator dot
            Circle()
                .fill(isActive ? Color.white : Color.gray.opacity(0.3))
                .frame(width: 14, height: 14)
                .shadow(color: isActive ? activeColor : .clear, radius: 8)

            // Beat number
            Text("\(beat)")
                .font(.title3.bold())
                .foregroundColor(isActive ? .white : .gray)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isActive ? activeColor.opacity(0.35) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? activeColor.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1.5)
        )
        .scaleEffect(isActive ? 1.04 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
