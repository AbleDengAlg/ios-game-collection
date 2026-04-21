// ContentView.swift
// Main SwiftUI screen — works on iOS (iPhone/iPad) and macOS.
// Layout: header → file picker → separate button → results cards

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var engine = SeparatorEngine()
    @StateObject private var vocalsPlayer = AudioPlayer()
    @StateObject private var accompPlayer = AudioPlayer()

    @State private var selectedURL: URL?
    @State private var showPicker = false
    @State private var shareItem: ShareItem?

    // MARK: - Body

    var body: some View {
#if os(macOS)
        macLayout
            .frame(minWidth: 520, minHeight: 640)
#else
        iosLayout
#endif
    }

    // MARK: - iOS Layout

#if os(iOS)
    private var iosLayout: some View {
        NavigationView {
            ScrollView {
                mainContent
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showPicker) {
            AudioPicker { url in
                handlePicked(url: url)
                showPicker = false
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(url: item.url)
        }
        .task { engine.load() }
    }
#endif

    // MARK: - macOS Layout

#if os(macOS)
    private var macLayout: some View {
        ScrollView {
            mainContent
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.wav, .audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                // Must start security scope on main thread right here
                let accessed = url.startAccessingSecurityScopedResource()
                handlePicked(url: url, securityAccessed: accessed)
            case .failure:
                break
            }
        }
        .onAppear { engine.load() }
    }
#endif

    // MARK: - Shared Content

    private var mainContent: some View {
        VStack(spacing: 24) {
            headerSection
            filePickerSection
            separateSection
            if engine.state == .done {
                resultsSection
            }
            if let msg = engine.errorMessage {
                errorSection(msg)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.accentColor)
                .padding(.top, 20)
            Text("Spleeter")
                .font(.largeTitle.bold())
            Text("Offline Vocal & Accompaniment Separation")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - File Picker

    private var filePickerSection: some View {
        VStack(spacing: 12) {
            Button {
                showPicker = true
            } label: {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text(selectedURL == nil ? "Select WAV File" : "Change File")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            if let url = selectedURL {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(.secondary)
                    Text(url.lastPathComponent)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Separate Button

    private var separateSection: some View {
        Button {
            guard let url = selectedURL else { return }
            Task {
                vocalsPlayer.stop()
                accompPlayer.stop()
                await engine.separate(url: url)
            }
        } label: {
            HStack {
                if engine.state == .separating || engine.state == .loading {
                    ProgressView()
                        .progressViewStyle(.circular)
#if os(iOS)
                        .tint(.white)
#endif
                        .padding(.trailing, 6)
                } else {
                    Image(systemName: "scissors")
                }
                Text(buttonLabel)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(separateButtonColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(separateButtonDisabled)
        .animation(.easeInOut(duration: 0.2), value: engine.state)
    }

    private var buttonLabel: String {
        switch engine.state {
        case .loading: return "Loading Model…"
        case .separating: return "Separating…"
        default: return "Separate Audio"
        }
    }

    private var separateButtonColor: Color {
        separateButtonDisabled ? Color.secondary.opacity(0.5) : Color.indigo
    }

    private var separateButtonDisabled: Bool {
        selectedURL == nil || engine.state == .separating || engine.state == .loading
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(spacing: 16) {
            if let vocals = engine.vocalsData {
                StemCard(
                    title: "Vocals",
                    iconName: "mic.fill",
                    color: .purple,
                    player: vocalsPlayer,
                    data: vocals,
                    filename: "vocals_separated.wav",
                    onShare: { url in shareItem = ShareItem(url: url) }
                )
            }
            if let accomp = engine.accompanimentData {
                StemCard(
                    title: "Accompaniment",
                    iconName: "music.quarternote.3",
                    color: .teal,
                    player: accompPlayer,
                    data: accomp,
                    filename: "accompaniment_separated.wav",
                    onShare: { url in shareItem = ShareItem(url: url) }
                )
            }
        }
    }

    // MARK: - Error

    private func errorSection(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func handlePicked(url: URL, securityAccessed: Bool = false) {
        selectedURL = url
        // Store whether we opened security scope so we can release it later if needed
        // (For simplicity on macOS, we keep it open until next pick)
        engine.reset()
        vocalsPlayer.stop()
        accompPlayer.stop()
    }
}

// MARK: - StemCard

struct StemCard: View {
    let title: String
    let iconName: String
    let color: Color
    @ObservedObject var player: AudioPlayer
    let data: AudioData
    let filename: String
    let onShare: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(color)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(data.samplesPerChannel / max(data.sampleRate, 1))s")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    if player.isPlaying { player.stop() } else { player.play(data: data) }
                } label: {
                    Label(
                        player.isPlaying ? "Stop" : "Play",
                        systemImage: player.isPlaying ? "stop.fill" : "play.fill"
                    )
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(color.opacity(0.15))
                    .foregroundColor(color)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button { saveAndShare() } label: {
                    Label("Save", systemImage: "arrow.down.circle")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
#if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
#else
        .background(Color(.windowBackgroundColor).opacity(0.5))
#endif
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func saveAndShare() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent(filename)
        if data.save(to: dest.path) {
            onShare(dest)
        }
    }
}

// MARK: - ActivityView (iOS share sheet)

#if os(iOS)
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - ShareItem (Identifiable for .sheet)

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
