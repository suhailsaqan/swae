//
//  GetBitcoinView.swift
//  swae
//
//  Created by Suhail Saqan on 3/21/26.
//

import SwiftUI

struct GetBitcoinView: View {
    let lud16: String?
    let onReceiveViaTapped: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        headerSection
                        if lud16 != nil { lightningAddressCard }
                        servicesSection
                        howItWorksSection
                        receiveViaInvoiceSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.orange)
            }
            Text("Get Bitcoin")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text("Fund your wallet in minutes")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.top, 16)
    }

    // MARK: - Lightning Address Card

    private var lightningAddressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR LIGHTNING ADDRESS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
                .tracking(0.5)

            if let lud16 {
                Button(action: copyAddress) {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.orange)

                        Text(lud16)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(copied ? .green : .gray)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(copied ? Color.green.opacity(0.5) : Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(copied ? "Copied to clipboard!" : "Send Bitcoin to this address from any app below")
                    .font(.system(size: 13))
                    .foregroundColor(copied ? .green : .gray)
                    .animation(.easeInOut(duration: 0.2), value: copied)
            }
        }
    }

    // MARK: - Services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECOMMENDED APPS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
                .tracking(0.5)

            VStack(spacing: 0) {
                ForEach(Array(services.enumerated()), id: \.element.name) { index, service in
                    serviceRow(service)
                    if index < services.count - 1 {
                        Divider().background(Color.gray.opacity(0.2)).padding(.leading, 60)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    private func serviceRow(_ service: BitcoinService) -> some View {
        Button(action: { openAppStore(service.appStoreURL) }) {
            HStack(spacing: 14) {
                Image(service.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(service.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - How It Works

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOW IT WORKS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 16) {
                stepRow(number: "1", text: "Open any app above")
                stepRow(number: "2", text: "Buy Bitcoin (if you don't have any)")
                stepRow(number: "3", text: "Send to your Lightning address above")
                stepRow(number: "4", text: "Sats arrive in seconds ⚡")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(0.15))
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white)
        }
    }

    // MARK: - Receive via Invoice

    private var receiveViaInvoiceSection: some View {
        VStack(spacing: 12) {
            Text("Already have Bitcoin?")
                .font(.system(size: 14))
                .foregroundColor(.gray)

            Button(action: {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onReceiveViaTapped()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 16, weight: .medium))
                    Text("Receive via Invoice")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Actions

    private func copyAddress() {
        guard let lud16 else { return }
        UIPasteboard.general.string = lud16
        withAnimation(.easeInOut(duration: 0.2)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) { copied = false }
        }
    }

    private func openAppStore(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Service Model

private struct BitcoinService {
    let name: String
    let imageName: String
    let subtitle: String
    let appStoreURL: String
}

private let services: [BitcoinService] = [
    .init(
        name: "Cash App",
        imageName: "cashapp-logo",
        subtitle: "Buy BTC & send to Lightning",
        appStoreURL: "https://apps.apple.com/app/cash-app/id711923939"
    ),
    .init(
        name: "Coinbase",
        imageName: "coinbase-logo",
        subtitle: "Buy BTC & send to Lightning",
        appStoreURL: "https://apps.apple.com/app/coinbase-buy-bitcoin-ether/id886427730"
    ),
    .init(
        name: "Strike",
        imageName: "strike-logo",
        subtitle: "Buy BTC & send to Lightning",
        appStoreURL: "https://apps.apple.com/app/strike-bitcoin-payments/id1488724463"
    ),
    .init(
        name: "River",
        imageName: "river-logo",
        subtitle: "Bitcoin-only, Lightning support",
        appStoreURL: "https://apps.apple.com/app/river-buy-bitcoin/id1536176542"
    ),
]

#Preview {
    GetBitcoinView(
        lud16: "abc123def456@coinos.io",
        onReceiveViaTapped: {}
    )
}
