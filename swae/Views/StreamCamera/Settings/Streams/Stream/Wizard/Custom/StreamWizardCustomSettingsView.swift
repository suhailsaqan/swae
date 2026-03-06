import SwiftUI

struct StreamWizardCustomSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var createStreamWizard: CreateStreamWizard
    
    /// Callback when stream creation is complete (used when presented as sheet)
    var onComplete: (() -> Void)? = nil

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.blue)
                        Text("Custom Server")
                            .font(.headline)
                    }
                    
                    Text("Connect to any streaming server using RTMP, SRT, or RIST protocols.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                NavigationLink {
                    StreamWizardCustomSrtSettingsView(
                        createStreamWizard: createStreamWizard,
                        onComplete: onComplete
                    )
                } label: {
                    HStack {
                        Image(systemName: "bolt.horizontal.fill")
                            .foregroundColor(.purple)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SRT(LA)")
                                .font(.body)
                            Text("Secure Reliable Transport - best for unstable networks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                NavigationLink {
                    StreamWizardCustomRtmpSettingsView(
                        createStreamWizard: createStreamWizard,
                        onComplete: onComplete
                    )
                } label: {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.red)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RTMP(S)")
                                .font(.body)
                            Text("Real-Time Messaging Protocol - widely supported")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                NavigationLink {
                    StreamWizardCustomRistSettingsView(
                        createStreamWizard: createStreamWizard,
                        onComplete: onComplete
                    )
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RIST")
                                .font(.body)
                            Text("Reliable Internet Stream Transport")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Select Protocol")
            }
        }
        .onAppear {
            createStreamWizard.platform = .custom
            createStreamWizard.networkSetup = .none
            createStreamWizard.customProtocol = .none
            createStreamWizard.name = makeUniqueName(name: String(localized: "Custom"),
                                                     existingNames: model.database.streams)
        }
        .navigationTitle("Custom Server")
        .navigationBarTitleDisplayMode(.inline)
    }
}
