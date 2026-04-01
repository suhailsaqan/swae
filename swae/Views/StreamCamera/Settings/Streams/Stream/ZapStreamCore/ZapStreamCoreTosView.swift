//
//  ZapStreamCoreTosView.swift
//  swae
//
//  TOS acceptance card for new zap.stream users.
//  Matches the app's existing card patterns (see errorView, noIdentityView).
//

import Combine
import SwiftUI

struct ZapStreamCoreTosView: View {
    @EnvironmentObject private var model: Model
    @EnvironmentObject private var appState: AppState
    let stream: SettingsStream

    @State private var accepted = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()

    private var apiClient: ZapStreamCoreApiClient {
        ZapStreamCoreApiClient(config: ZapStreamCoreConfig(
            baseUrl: stream.zapStreamCoreBaseUrl
        ))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Terms of Service")
                        .font(.subheadline.weight(.semibold))
                    Text("Please accept the terms to start streaming.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Checkbox row with link
            HStack(spacing: 10) {
                Image(systemName: accepted ? "checkmark.square.fill" : "square")
                    .foregroundColor(accepted ? .green : .secondary)
                    .font(.title3)
                    .onTapGesture { accepted.toggle() }

                Text("I agree to zap.stream's ") +
                Text("terms and conditions")
                    .foregroundColor(.accentColor)
                    .underline()
            }
            .font(.caption)
            .onTapGesture {
                if let link = model.zapStreamCoreTosLink,
                   let url = URL(string: link) {
                    UIApplication.shared.open(url)
                }
            }

            Button {
                submitTos()
            } label: {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                    Text("Accept & Continue")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accepted ? Color.accentColor : Color.gray.opacity(0.3))
                )
            }
            .disabled(!accepted || isSubmitting)

            if let error = errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    private func submitTos() {
        isSubmitting = true
        errorMessage = nil

        apiClient.updateAccount(appState: appState, acceptTos: true)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isSubmitting = false
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { _ in
                    model.zapStreamCoreTosAccepted = true
                    model.refreshZapStreamCoreBalance()
                }
            )
            .store(in: &cancellables)
    }
}
