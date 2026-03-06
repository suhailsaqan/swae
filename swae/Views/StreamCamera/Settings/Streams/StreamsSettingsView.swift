import SwiftUI

// MARK: - Stream Card View

private struct StreamCardView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var database: Database
    @ObservedObject var stream: SettingsStream
    
    private var isActive: Bool {
        stream.enabled
    }
    
    private var protocolName: String {
        if stream.zapStreamCoreEnabled {
            return "Zap Stream"
        }
        switch stream.getProtocol() {
        case .rtmp:
            return "RTMP"
        case .srt:
            return "SRT"
        case .rist:
            return "RIST"
        }
    }
    
    private var protocolIcon: String {
        if stream.zapStreamCoreEnabled {
            return "bolt.fill"
        }
        switch stream.getProtocol() {
        case .rtmp:
            return "play.rectangle.fill"
        case .srt:
            return "bolt.horizontal.fill"
        case .rist:
            return "arrow.triangle.branch"
        }
    }
    
    private var protocolColor: Color {
        if stream.zapStreamCoreEnabled {
            return .yellow
        }
        switch stream.getProtocol() {
        case .rtmp:
            return .red
        case .srt:
            return .purple
        case .rist:
            return .orange
        }
    }
    
    private var platformName: String? {
        if stream.zapStreamCoreEnabled {
            return "zap.stream"
        }
        if !stream.twitchChannelName.isEmpty {
            return "Twitch"
        }
        if !stream.kickChannelName.isEmpty {
            return "Kick"
        }
        if !stream.youTubeHandle.isEmpty {
            return "YouTube"
        }
        if !stream.afreecaTvChannelName.isEmpty {
            return "AfreecaTV"
        }
        return nil
    }
    
    private var urlPreview: String {
        let url = stream.url
        if url == defaultStreamUrl || url.isEmpty {
            return "Not configured"
        }
        // Truncate URL for display
        if let urlObj = URL(string: url) {
            return urlObj.host ?? url.prefix(30) + "..."
        }
        return String(url.prefix(30)) + (url.count > 30 ? "..." : "")
    }
    
    var body: some View {
        NavigationLink {
            StreamSettingsView(database: database, stream: stream)
        } label: {
            HStack(spacing: 12) {
                // Protocol icon
                ZStack {
                    Circle()
                        .fill(protocolColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: protocolIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(protocolColor)
                }
                
                // Stream info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(stream.name)
                            .font(.body.weight(.medium))
                            .foregroundColor(.primary)
                        
                        if isActive {
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 4) {
                        Text(protocolName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let platform = platformName {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(platform)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Active indicator or toggle area
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if !isActive, !model.isLive, !model.isRecording {
                Button {
                    model.setCurrentStream(stream: stream)
                    model.reloadStreamIfEnabled(stream: stream)
                } label: {
                    Label("Set as Active", systemImage: "checkmark.circle")
                }
            }
            
            Button {
                database.streams.append(stream.clone())
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            
            if !model.isLive, !model.isRecording {
                Button(role: .destructive) {
                    database.streams.removeAll { $0 == stream }
                    // If we deleted the active stream, set another one as active
                    // If no streams remain, this will set model.stream to fallbackStream
                    if isActive {
                        model.setCurrentStream()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Create Stream Card

private struct CreateStreamCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Create New Stream")
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                Text("Set up a new streaming destination")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundColor(Color(.separator))
        )
    }
}

// MARK: - Streams Settings View

struct StreamsSettingsView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var appState: AppState
    @ObservedObject var createStreamWizard: CreateStreamWizard
    @ObservedObject var database: Database
    
    // State to control navigation to StreamSetupView
    @State private var showStreamSetup = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Streams list
                if !database.streams.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR STREAMS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        
                        VStack(spacing: 8) {
                            ForEach(database.streams) { stream in
                                StreamCardView(database: database, stream: stream)
                            }
                        }
                    }
                }
                
                // Create new stream - go directly to simplified Zap Stream Core setup
                Button {
                    showStreamSetup = true
                } label: {
                    CreateStreamCard()
                }
                .disabled(model.isLive || model.isRecording)
                .opacity(model.isLive || model.isRecording ? 0.5 : 1)
                
                // Help text
                if !database.streams.isEmpty {
                    Text("Long press on a stream for more options")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Streams")
        .settingsCloseButton()
        .navigationDestination(isPresented: $showStreamSetup) {
            StreamSetupView()
                .environment(\.popToStreamsList) {
                    showStreamSetup = false
                }
        }
    }
}
