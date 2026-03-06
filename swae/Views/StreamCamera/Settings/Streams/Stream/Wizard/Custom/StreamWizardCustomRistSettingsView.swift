import SwiftUI

struct StreamWizardCustomRistSettingsView: View {
    @EnvironmentObject private var model: Model
    @ObservedObject var createStreamWizard: CreateStreamWizard
    var onComplete: (() -> Void)? = nil
    
    @State var urlError = ""

    private var canCreate: Bool {
        !createStreamWizard.customRistUrl.isEmpty &&
        urlError.isEmpty &&
        !createStreamWizard.name.isEmpty
    }

    private func updateUrlError() {
        let url = cleanUrl(url: createStreamWizard.customRistUrl)
        if url.isEmpty {
            urlError = ""
        } else {
            urlError = isValidUrl(url: url, allowedSchemes: ["rist"]) ?? ""
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("rist://120.35.234.2:2030", text: $createStreamWizard.customRistUrl)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: createStreamWizard.customRistUrl) { _ in
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
            createStreamWizard.customProtocol = .rist
            createStreamWizard.name = makeUniqueName(name: String(localized: "Custom RIST"),
                                                     existingNames: model.database.streams)
        }
        .navigationTitle("RIST")
        .navigationBarTitleDisplayMode(.inline)
    }
}
