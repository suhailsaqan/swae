import SwiftUI

// MARK: - Wizard Helper Views

struct WizardNextButtonView: View {
    var body: some View {
        HCenter {
            Text("Next")
                .foregroundColor(.accentColor)
        }
    }
}

struct WizardSkipButtonView: View {
    var body: some View {
        HCenter {
            Text("Skip")
                .foregroundColor(.accentColor)
        }
    }
}

struct CreateStreamWizardToolbar: ToolbarContent {
    @ObservedObject var createStreamWizard: CreateStreamWizard

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack {
                Button {
                    createStreamWizard.isPresenting = false
                    createStreamWizard.isPresentingSetup = false
                } label: {
                    Text("Close")
                }
            }
        }
    }
}

// MARK: - Stream Option Card (Button-based for sheets)

struct StreamOptionCardButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    var benefits: [String]? = nil
    var isRecommended: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack(alignment: .top, spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundColor(iconColor)
                    }
                    
                    // Title and description
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            if isRecommended {
                                Text("Recommended")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                
                // Benefits list (for recommended option)
                if let benefits = benefits, !benefits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(benefits, id: \.self) { benefit in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                Text(benefit)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 60)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isRecommended ? Color.green.opacity(0.4) : Color(.separator).opacity(0.3),
                        lineWidth: isRecommended ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Zap Stream Core Wizard Sheet
/// Wraps the Zap Stream Core setup in a NavigationStack for sheet presentation
/// Now uses StreamSetupView instead of the deprecated wizard view

struct ZapStreamCoreWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: Model
    @EnvironmentObject var appState: AppState
    @ObservedObject var createStreamWizard: CreateStreamWizard
    var onStreamCreated: (() -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            StreamSetupView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Custom Server Wizard Sheet
/// Wraps the Custom Server wizard in a NavigationStack for sheet presentation

struct CustomServerWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: Model
    @ObservedObject var createStreamWizard: CreateStreamWizard
    var onStreamCreated: (() -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            StreamWizardCustomSettingsView(
                createStreamWizard: createStreamWizard,
                onComplete: {
                    model.createStreamFromWizard()
                    dismiss()
                    onStreamCreated?()
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Stream Wizard Settings View

struct StreamWizardSettingsView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var appState: AppState
    @ObservedObject var createStreamWizard: CreateStreamWizard
    @Environment(\.dismiss) private var dismiss
    
    @State private var showZapStreamSheet = false
    @State private var showCustomServerSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Choose how you want to stream")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Text("Select a streaming destination to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                
                // Zap Stream Core Card (Recommended) - Opens sheet
                StreamOptionCardButton(
                    icon: "bolt.fill",
                    iconColor: .yellow,
                    title: "Zap Stream Core",
                    description: "Stream to Nostr with your identity. Receive zaps directly from viewers.",
                    benefits: [
                        "Free to start streaming",
                        "Built-in zap support",
                        "Uses your Nostr identity"
                    ],
                    isRecommended: true
                ) {
                    model.resetWizard()
                    showZapStreamSheet = true
                }
                
                // Divider with "or"
                HStack {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                    Text("or")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                }
                .padding(.vertical, 4)
                
                // Custom Card - Opens sheet
                StreamOptionCardButton(
                    icon: "slider.horizontal.3",
                    iconColor: .blue,
                    title: "Custom Server",
                    description: "Connect to any RTMP, SRT, or RIST server with your own URL and stream key.",
                    isRecommended: false
                ) {
                    model.resetWizard()
                    showCustomServerSheet = true
                }
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .settingsCloseButton()
        .sheet(isPresented: $showZapStreamSheet) {
            ZapStreamCoreWizardSheet(
                createStreamWizard: createStreamWizard,
                onStreamCreated: {
                    // After stream is created, also dismiss this page
                    dismiss()
                }
            )
            .environmentObject(model)
            .environmentObject(appState)
        }
        .sheet(isPresented: $showCustomServerSheet) {
            CustomServerWizardSheet(
                createStreamWizard: createStreamWizard,
                onStreamCreated: {
                    // After stream is created, also dismiss this page
                    dismiss()
                }
            )
            .environmentObject(model)
        }
    }
}
