// AudioPicker.swift
// Cross-platform WAV file picker.
// iOS/iPadOS: UIDocumentPickerViewController
// macOS: NSOpenPanel via fileImporter SwiftUI modifier (handled in ContentView)
// This file provides the iOS UIViewControllerRepresentable implementation only.

import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit

struct AudioPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.wav, .audio],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioPicker
        init(_ parent: AudioPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
#endif
