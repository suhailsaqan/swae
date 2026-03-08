import MWDATCamera
import SwiftUI

struct MetaGlassesSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject private var manager: MetaGlassesManager

    init() {
        // Will be replaced in body via onAppear, but need a default for init
        self._manager = ObservedObject(wrappedValue: AppCoordinator.shared.model.metaGlassesManager ?? MetaGlassesManager())
    }

    var body: some View {
        Form {
            Section {
                HCenter {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                }
            }

            connectionSection(manager: manager)
            if manager.isRegistered {
                streamSection(manager: manager)
                pipSection
                photoCaptureSection(manager: manager)
                previewSection(manager: manager)
            }
            errorSection(manager: manager)

            setupGuideSection
        }
        .navigationTitle("Meta Glasses")
        .settingsCloseButton()
        .onDisappear {
            // Stop preview-only stream when leaving settings
            // (scene/PiP consumers keep it alive if needed)
            if model.isMetaGlassesPreviewActive {
                model.stopMetaGlassesPreview()
            }
        }
        .sheet(isPresented: $manager.showPhotoPreview) {
            if let photo = manager.capturedPhoto {
                MetaGlassesPhotoPreviewView(
                    photo: photo,
                    onSave: { manager.savePhotoToLibrary() },
                    onDismiss: { manager.dismissPhotoPreview() }
                )
            }
        }
    }

    @ViewBuilder
    private func connectionSection(manager: MetaGlassesManager) -> some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                if manager.isRegistered {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Connected").foregroundStyle(.green)
                    }
                } else if manager.isRegistering {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.7)
                        Text("Connecting...").foregroundStyle(.orange)
                    }
                } else {
                    Text("Not connected").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Active Device")
                Spacer()
                Text(manager.hasActiveDevice ? "Ready" : "None")
                    .foregroundStyle(manager.hasActiveDevice ? .green : .secondary)
            }
            if manager.devices.count > 0 {
                HStack {
                    Text("Devices Found")
                    Spacer()
                    Text("\(manager.devices.count)").foregroundStyle(.secondary)
                }
            }
            if manager.isRegistered && manager.hasActiveDevice {
                Button("Disconnect", role: .destructive) {
                    Task { await manager.disconnect() }
                }
            } else if !manager.isRegistering {
                Button("Connect Glasses") {
                    Task { await manager.connect() }
                }
            }
        } header: {
            Text("Connection")
        }
    }

    @ViewBuilder
    private func streamSection(manager: MetaGlassesManager) -> some View {
        Section {
            HStack {
                Text("Stream Status")
                Spacer()
                Text(manager.streamingStatus)
                    .foregroundStyle(statusColor(for: manager.streamingStatus))
            }
            if manager.isStreaming {
                HStack {
                    Text("Frames")
                    Spacer()
                    Text("\(manager.frameCount)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if model.isMetaGlassesPreviewActive {
                Button("Stop Preview", role: .destructive) {
                    model.stopMetaGlassesPreview()
                }
                .disabled(model.isMetaGlassesNeededByScene)
            } else if manager.hasActiveDevice {
                Button("Start Preview") {
                    model.startMetaGlassesPreview()
                }
            }
            if model.isMetaGlassesNeededByScene {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Active scene is using Meta Glasses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Video Stream")
        } footer: {
            Text("To use as your main camera, select \"Meta Glasses\" in your scene's camera picker.")
        }
    }

    private var pipSection: some View {
        Section {
            Toggle("Picture-in-Picture", isOn: Binding(
                get: { model.isMetaGlassesPipEnabled },
                set: { enabled in
                    if enabled {
                        model.enableMetaGlassesPip()
                    } else {
                        model.disableMetaGlassesPip()
                    }
                }
            ))
        } header: {
            Text("PiP Mode")
        } footer: {
            Text("Overlay the glasses camera on your phone camera stream.")
        }
    }

    @ViewBuilder
    private func photoCaptureSection(manager: MetaGlassesManager) -> some View {
        Section {
            Button {
                manager.capturePhoto()
            } label: {
                Label("Capture Photo", systemImage: "camera.fill")
            }
            .disabled(!manager.isStreaming)
        } header: {
            Text("Photo")
        } footer: {
            Text("Take a photo from the glasses camera. Stream must be active.")
        }
    }

    @ViewBuilder
    private func previewSection(manager: MetaGlassesManager) -> some View {
        if let frame = manager.previewFrame {
            Section {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } header: {
                Text("Preview")
            }
        }
    }

    @ViewBuilder
    private func errorSection(manager: MetaGlassesManager) -> some View {
        if let error = manager.error {
            Section {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error).font(.subheadline)
                }
                Button("Dismiss") { manager.dismissError() }
            } header: {
                Text("Error")
            }
        }
    }

    private var setupGuideSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Install Meta AI app on your iPhone", systemImage: "1.circle")
                Label("Open Meta AI → Settings → App Info", systemImage: "2.circle")
                Label("Tap version number 5 times to enable Developer Mode", systemImage: "3.circle")
                Label("Pair your glasses in the Meta AI app", systemImage: "4.circle")
                Label("Tap \"Connect Glasses\" above", systemImage: "5.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } header: {
            Text("Setup Guide")
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Streaming": return .green
        case "Stopped", "Permission denied", "Permission error": return .secondary
        case "Waiting for reconnect...", "Waiting for glasses...", "Paused": return .orange
        default: return .blue
        }
    }
}

// MARK: - Photo Preview Sheet

struct MetaGlassesPhotoPreviewView: View {
    let photo: UIImage
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                HStack(spacing: 20) {
                    Button {
                        onSave()
                        onDismiss()
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    ShareLink(
                        item: Image(uiImage: photo),
                        preview: SharePreview("Meta Glasses Photo", image: Image(uiImage: photo))
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Captured Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}
