//
//  StreamCoverImageView.swift
//  swae
//
//  Reusable cover image picker area with upload state management.
//  Shows placeholder → uploading → preview states.
//

import NostrSDK
import SwiftUI

struct StreamCoverImageView: View {
    @Binding var imageURL: String
    @EnvironmentObject private var appState: AppState

    @State private var uploadState: StreamCoverImageCoordinator.UploadState = .idle
    @State private var coordinator = StreamCoverImageCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cover Image")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            Button {
                presentImagePicker()
            } label: {
                coverContent
            }
            .buttonStyle(.plain)

            if case .failed(let error) = uploadState {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Retry") { presentImagePicker() }
                        .font(.caption.weight(.medium))
                }
            }

            Text("16:9 landscape recommended")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var coverContent: some View {
        if !imageURL.isEmpty, let url = URL(string: imageURL) {
            // Uploaded state: show preview
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                Button {
                    imageURL = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .padding(8)
            }
        } else if case .uploading = uploadState {
            // Uploading state
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemGroupedBackground))
                .frame(height: 140)
                .overlay {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Uploading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
        } else {
            // Empty state: dashed placeholder
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8]))
                .foregroundColor(Color(.separator))
                .frame(height: 140)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Add Cover Image")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
        }
    }

    private func presentImagePicker() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        coordinator.onComplete = { url in
            imageURL = url?.absoluteString ?? ""
        }
        coordinator.onStateChanged = { state in
            uploadState = state
        }
        coordinator.present(
            from: topVC,
            keypair: appState.keypair,
            hasExistingImage: !imageURL.isEmpty
        )
    }
}
