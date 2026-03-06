import SwiftUI

struct StreamWizardCustomRtmpSettingsView: View {
    @EnvironmentObject private var model: Model
    @ObservedObject var createStreamWizard: CreateStreamWizard
    var onComplete: (() -> Void)? = nil
    
    @State var urlError = ""

    private var canCreate: Bool {
        !createStreamWizard.customRtmpUrl.isEmpty &&
        !createStreamWizard.customRtmpStreamKey.isEmpty &&
        urlError.isEmpty &&
        !createStreamWizard.name.isEmpty
    }

    private func updateUrlError() {
        let url = cleanUrl(url: createStreamWizard.customRtmpUrl)
        if url.isEmpty {
            urlError = ""
        } else {
            urlError = isValidUrl(
                url: url,
                allowedSchemes: ["rtmp", "rtmps"],
                rtmpStreamKeyRequired: false
            ) ??
                ""
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("rtmp://arn03.contribute.live-video.net/app/", text: $createStreamWizard.customRtmpUrl)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: createStreamWizard.customRtmpUrl) { _ in
                        updateUrlError()
                    }
            } header: {
                Text("URL")
            } footer: {
                if !urlError.isEmpty {
                    FormFieldError(error: urlError)
                }
            }
            Section {
                TextField(
                    "live_48950233_okF4f455GRWEF443fFr23GRbt5rEv",
                    text: $createStreamWizard.customRtmpStreamKey
                )
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            } header: {
                Text("Stream Key")
            }
            Section {
                TextField("Name", text: $createStreamWizard.name)
                    .disableAutocorrection(true)
            } header: {
                Text("Stream Name")
            }
            Section {
                Button {
                    if let onComplete = onComplete {
                        onComplete()
                    } else {
                        model.createStreamFromWizard()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Create Stream")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!canCreate)
            }
        }
        .onAppear {
            createStreamWizard.customProtocol = .rtmp
            createStreamWizard.name = makeUniqueName(name: String(localized: "Custom RTMP"),
                                                     existingNames: model.database.streams)
        }
        .navigationTitle("RTMP(S)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
