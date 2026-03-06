import SwiftUI

struct StreamWizardCustomSrtSettingsView: View {
    @EnvironmentObject private var model: Model
    @ObservedObject var createStreamWizard: CreateStreamWizard
    var onComplete: (() -> Void)? = nil
    
    @State var urlError = ""

    private var canCreate: Bool {
        !createStreamWizard.customSrtUrl.isEmpty &&
        !createStreamWizard.customSrtStreamId.isEmpty &&
        urlError.isEmpty &&
        !createStreamWizard.name.isEmpty
    }

    private func updateUrlError() {
        let url = cleanUrl(url: createStreamWizard.customSrtUrl)
        if url.isEmpty {
            urlError = ""
        } else {
            urlError = isValidUrl(url: url, allowedSchemes: ["srt", "srtla"]) ?? ""
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("srt://107.32.12.132:5000", text: $createStreamWizard.customSrtUrl)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: createStreamWizard.customSrtUrl) { _ in
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
                    "#!::r=stream/-NDZ1WPA4zjMBTJTyNwU,m=publish,...",
                    text: $createStreamWizard.customSrtStreamId
                )
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            } header: {
                Text("Stream ID")
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
            createStreamWizard.customProtocol = .srt
            createStreamWizard.name = makeUniqueName(name: String(localized: "Custom SRT"),
                                                     existingNames: model.database.streams)
        }
        .navigationTitle("SRT(LA)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
