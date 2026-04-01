import MWDATCamera
import SwiftUI

struct MetaGlassesSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject private var manager: MetaGlassesManager

    init() {
        self._manager = ObservedObject(
            wrappedValue: AppCoordinator.shared.model.metaGlassesManager ?? MetaGlassesManager()
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroImageCard
                connectionStatusCard
                connectButton
                if let frame = manager.previewFrame {
                    previewCard(frame: frame)
                }
                if manager.isRegistered {
                    controlsSection
                }
                if let error = manager.error {
                    errorCard(error: error)
                }
                setupGuideCard
                footerTip
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Meta Glasses")
        .settingsCloseButton()
        .onDisappear {
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

    // MARK: - Hero Image

    private var heroImageCard: some View {
        VStack(spacing: 0) {
            Image("MetaGlasses")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Connection Status

    private var connectionStatusCard: some View {
        Group {
            if manager.isRegistered {
                connectedCard
            } else if manager.isRegistering {
                connectingCard
            } else {
                disconnectedCard
            }
        }
    }

    private var disconnectedCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "eyeglasses")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Not Connected")
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                Text("Tap below to pair your glasses")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var connectingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connecting...")
                    .font(.subheadline.weight(.medium))
                Text("Opening Meta AI app...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var connectedCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 4) {
                        Text("\(manager.devices.count) device\(manager.devices.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if manager.hasActiveDevice {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Ready")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                if manager.isStreaming {
                    Text("Streaming")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .cornerRadius(4)
                }
            }
            if manager.isStreaming {
                HStack {
                    Text("Frames")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(manager.frameCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            if manager.isRegistered && manager.hasActiveDevice {
                Button("Disconnect", role: .destructive) {
                    Task { await manager.disconnect() }
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Group {
            if !manager.isRegistered && !manager.isRegistering {
                Button {
                    Task { await manager.connect() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Connect Glasses")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.accentPurple)
                    )
                    .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Preview

    private func previewCard(frame: UIImage) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: frame)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTROLS")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                previewControlCard
                pipCard
                qualityCard
                photoCaptureCard
            }
        }
    }

    private var previewControlCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentPurple.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "video.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.accentPurple)
                }
                Text("Preview")
                    .font(.body.weight(.medium))
                Spacer()
                if model.isMetaGlassesPreviewActive {
                    Button("Stop", role: .destructive) {
                        model.stopMetaGlassesPreview()
                    }
                    .font(.subheadline.weight(.medium))
                    .disabled(model.isMetaGlassesNeededByScene)
                } else if manager.hasActiveDevice {
                    Button {
                        model.startMetaGlassesPreview()
                    } label: {
                        Text("Start")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.accentPurple)
                    }
                }
            }
            if model.isMetaGlassesNeededByScene {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Active scene is using Meta Glasses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var pipCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentPurple.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "rectangle.inset.bottomright.filled")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentPurple)
            }
            Text("Picture-in-Picture")
                .font(.body.weight(.medium))
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.isMetaGlassesPipEnabled },
                set: { enabled in
                    if enabled {
                        model.enableMetaGlassesPip()
                    } else {
                        model.disableMetaGlassesPip()
                    }
                }
            ))
            .tint(.accentPurple)
            .labelsHidden()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var qualityCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentPurple.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentPurple)
            }
            Text("Quality")
                .font(.body.weight(.medium))
            Spacer()
            Picker("", selection: $manager.selectedResolution) {
                Text("High").tag(StreamingResolution.high)
                Text("Medium").tag(StreamingResolution.medium)
                Text("Low").tag(StreamingResolution.low)
            }
            .labelsHidden()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var photoCaptureCard: some View {
        Button {
            manager.capturePhoto()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentPurple.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.accentPurple)
                }
                Text("Capture Photo")
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                Spacer()
                if manager.isStreaming {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                } else {
                    Text("Stream required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(!manager.isStreaming)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Error Card

    private func errorCard(error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .font(.subheadline)
            }
            Button("Dismiss") {
                manager.dismissError()
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.accentPurple)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Setup Guide

    @State private var showSetupGuide = false

    private var setupGuideCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSetupGuide.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text("Setup Guide")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: showSetupGuide ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)

            if showSetupGuide {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.vertical, 8)
                    setupStep(number: 1, text: "Install the Meta AI app on your iPhone")
                    setupStep(number: 2, text: "Open Meta AI → Settings → App Info")
                    setupStep(number: 3, text: "Tap version number 5× to enable Developer Mode")
                    setupStep(number: 4, text: "Pair your glasses in the Meta AI app")
                    setupStep(number: 5, text: "Return here and tap Connect Glasses")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundColor(Color(.separator))
        )
    }

    private func setupStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentPurple.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.accentPurple)
            }
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Footer

    private var footerTip: some View {
        Text("To use as your main camera, select \"Meta Glasses\" in your scene's camera picker.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 8)
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
