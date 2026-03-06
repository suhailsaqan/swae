//
//  EmoteManagementView.swift
//  swae
//
//  Streamer emote management — view/add/remove custom emotes.
//  Publishes kind 10030 (emoji list) events to Nostr.
//

import NostrSDK
import SDWebImageSwiftUI
import SwiftUI

struct EmoteManagementView: View {
    @ObservedObject var appState: AppState
    @State private var emotes: [EmoteItem] = []
    @State private var showingImagePicker = false
    @State private var showingShortcodePrompt = false
    @State private var pendingImageData: Data?
    @State private var newShortcode = ""
    @State private var isUploading = false
    @State private var errorMessage: String?

    struct EmoteItem: Identifiable {
        let id = UUID()
        let shortcode: String
        let url: URL
    }

    var body: some View {
        List {
            Section {
                if emotes.isEmpty {
                    Text("No custom emotes yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(emotes) { emote in
                        HStack(spacing: 12) {
                            WebImage(url: emote.url)
                                .resizable()
                                .frame(width: 32, height: 32)
                            Text(":\(emote.shortcode):")
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                        }
                    }
                    .onDelete(perform: deleteEmotes)
                }
            } header: {
                Text("Your Emotes")
            } footer: {
                Text("Emotes are visible to viewers in your stream chat. Type :\\(name): to use them.")
            }

            Section {
                Button {
                    showingImagePicker = true
                } label: {
                    Label("Add Emote", systemImage: "plus.circle.fill")
                }
                .disabled(isUploading)

                if isUploading {
                    HStack {
                        ProgressView()
                        Text("Uploading...")
                            .foregroundColor(.secondary)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Emotes")
        .onAppear { loadCurrentEmotes() }
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerView { data in
                pendingImageData = data
                showingShortcodePrompt = true
            }
        }
        .alert("Emote Shortcode", isPresented: $showingShortcodePrompt) {
            TextField("e.g. KEKW", text: $newShortcode)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {
                pendingImageData = nil
                newShortcode = ""
            }
            Button("Add") { uploadAndAddEmote() }
        } message: {
            Text("Enter a name for this emote (letters, numbers, underscores only)")
        }
    }

    private func loadCurrentEmotes() {
        guard let service = appState.emojiPackService else { return }
        emotes = service.packs
            .filter { $0.authorPubkey == appState.keypair?.publicKey.hex }
            .flatMap { $0.emojis }
            .map { EmoteItem(shortcode: $0.shortcode, url: $0.imageURL) }
    }

    private func deleteEmotes(at offsets: IndexSet) {
        let toRemove = offsets.map { emotes[$0].shortcode }
        emotes.remove(atOffsets: offsets)
        publishEmojiList(removing: Set(toRemove))
    }

    private func uploadAndAddEmote() {
        guard let data = pendingImageData else { return }
        let shortcode = newShortcode.trimmingCharacters(in: .whitespaces)
        guard !shortcode.isEmpty,
              shortcode.range(of: "^[_a-zA-Z0-9]+$", options: .regularExpression) != nil else {
            errorMessage = "Invalid shortcode — use only letters, numbers, underscores"
            pendingImageData = nil
            newShortcode = ""
            return
        }

        isUploading = true
        errorMessage = nil

        Task {
            do {
                let result = try await NostrBuildUploadService.shared.upload(
                    imageData: data,
                    mimeType: "image/png",
                    filename: "\(shortcode).png",
                    keypair: appState.keypair
                )
                await MainActor.run {
                    emotes.append(EmoteItem(shortcode: shortcode, url: result.url))
                    publishEmojiList()
                    isUploading = false
                    pendingImageData = nil
                    newShortcode = ""
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isUploading = false
                    pendingImageData = nil
                    newShortcode = ""
                }
            }
        }
    }

    private func publishEmojiList(removing: Set<String> = []) {
        guard let keypair = appState.keypair else { return }

        var tags: [Tag] = []
        for emote in emotes where !removing.contains(emote.shortcode) {
            tags.append(Tag(name: "emoji", value: emote.shortcode, otherParameters: [emote.url.absoluteString]))
        }

        // Also preserve any existing "a" tag references to emoji sets
        if let service = appState.emojiPackService {
            for pack in service.packs where pack.authorPubkey != keypair.publicKey.hex {
                tags.append(Tag(name: "a", value: pack.id))
            }
        }

        do {
            let event = try NostrEvent(kind: .emojiList, content: "", tags: tags, signedBy: keypair)
            appState.relayWritePool.publishEvent(event)
            // Reload packs after publishing
            appState.emojiPackService?.loadPacks(userPubkey: keypair.publicKey.hex, streamerPubkey: nil)
        } catch {
            errorMessage = "Failed to publish: \(error.localizedDescription)"
        }
    }
}

// MARK: - Simple Image Picker

private struct ImagePickerView: UIViewControllerRepresentable {
    let onImagePicked: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (Data) -> Void
        init(onImagePicked: @escaping (Data) -> Void) { self.onImagePicked = onImagePicked }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage else { return }
            // Resize to 128x128 for emotes
            let size = CGSize(width: 128, height: 128)
            UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: size))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            guard let data = resized?.pngData() else { return }
            onImagePicked(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
