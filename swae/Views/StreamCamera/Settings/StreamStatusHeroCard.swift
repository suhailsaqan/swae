//
//  StreamStatusHeroCard.swift
//  swae
//
//  A prominent status card at the top of Settings that shows streaming readiness
//  and provides direct actions for stream setup.
//

import SwiftUI

// MARK: - Stream Status State

enum StreamStatusState {
    case notConfigured
    case configured
    case live
    
    var title: String {
        switch self {
        case .notConfigured:
            return String(localized: "Not Ready to Stream")
        case .configured:
            return String(localized: "Ready to Stream")
        case .live:
            return String(localized: "Live Now")
        }
    }
    
    var icon: String {
        switch self {
        case .notConfigured:
            return "exclamationmark.triangle.fill"
        case .configured:
            return "checkmark.circle.fill"
        case .live:
            return "dot.radiowaves.left.and.right"
        }
    }
    
    var color: Color {
        switch self {
        case .notConfigured:
            return .orange
        case .configured:
            return .green
        case .live:
            return .red
        }
    }
}

// MARK: - Stream Status Hero Card

struct StreamStatusHeroCard: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var appState: AppState
    
    @State private var isPulsing = false
    
    private var statusState: StreamStatusState {
        if model.isLive {
            return .live
        } else if model.isStreamConfigured() {
            return .configured
        } else {
            return .notConfigured
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Status Header
            statusHeader
            
            // Content based on state
            switch statusState {
            case .notConfigured:
                notConfiguredContent
            case .configured:
                configuredContent
            case .live:
                liveContent
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Status Header
    
    private var statusHeader: some View {
        HStack(spacing: 12) {
            // Status icon with animation for live state
            ZStack {
                Circle()
                    .fill(statusState.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                if statusState == .live {
                    Circle()
                        .fill(statusState.color.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .opacity(isPulsing ? 0 : 0.5)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                        .onAppear { isPulsing = true }
                }
                
                Image(systemName: statusState.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(statusState.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(statusState.title)
                    .font(.headline)
                    .foregroundColor(statusState.color)
                
                Text(statusSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var statusSubtitle: String {
        switch statusState {
        case .notConfigured:
            return String(localized: "Set up a stream destination to go live")
        case .configured:
            if model.stream.zapStreamCoreEnabled {
                return "zap.stream"
            } else {
                return model.stream.name
            }
        case .live:
            return model.stream.name
        }
    }
    
    // MARK: - Not Configured Content
    
    private var notConfiguredContent: some View {
        VStack(spacing: 12) {
            // Primary CTA - NavigationLink to simplified stream setup (Zap Stream Core)
            NavigationLink {
                StreamSetupView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("Set Up Stream")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.yellow.opacity(0.9), Color.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            
            // Secondary info
            Text("Stream to Nostr with Zap Stream Core")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Configured Content
    
    private var configuredContent: some View {
        NavigationLink {
            StreamSettingsView(database: model.database, stream: model.stream)
        } label: {
            VStack(spacing: 12) {
                if model.stream.zapStreamCoreEnabled {
                    zapStreamInfo
                } else {
                    customStreamInfo
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var zapStreamInfo: some View {
        HStack(spacing: 16) {
            // Zap Stream icon
            Image(systemName: "bolt.fill")
                .font(.title2)
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.stream.zapStreamCoreStreamTitle.isEmpty 
                     ? model.stream.name 
                     : model.stream.zapStreamCoreStreamTitle)
                    .font(.subheadline.weight(.medium))
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    private var customStreamInfo: some View {
        HStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.stream.name)
                    .font(.subheadline.weight(.medium))
                
                Text(streamProtocolDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    private var streamProtocolDescription: String {
        let proto = model.stream.getProtocol()
        switch proto {
        case .rtmp:
            return "RTMP"
        case .srt:
            return "SRT"
        case .rist:
            return "RIST"
        }
    }
    
    // MARK: - Live Content
    
    private var liveContent: some View {
        VStack(spacing: 12) {
            // Live stats
            HStack(spacing: 20) {
                liveStatItem(
                    icon: "clock",
                    value: model.streamUptime.uptime,
                    label: "Duration"
                )
                
                liveStatItem(
                    icon: "arrow.up.circle",
                    value: model.bitrate.speedMbpsOneDecimal + " Mbps",
                    label: "Bitrate"
                )
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(10)
            
            // Stream name
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(.red)
                Text(model.stream.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func liveStatItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        Form {
            Section {
                StreamStatusHeroCard()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
    .environmentObject(Model())
}
