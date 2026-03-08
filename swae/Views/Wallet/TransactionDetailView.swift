//
//  TransactionDetailView.swift
//  swae
//
//  Full transaction detail modal sheet
//

import NostrSDK
import SwiftUI

struct TransactionDetailView: View {
    let transaction: WalletTransaction
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var copiedField: String? = nil

    private var counterpartyMetadata: UserMetadata? {
        guard let pubkey = transaction.counterpartyPubkey else { return nil }
        return appState.metadataEvents[pubkey]?.userMetadata
    }

    private var counterpartyName: String {
        if let meta = counterpartyMetadata {
            if let display = meta.displayName, !display.isEmpty { return display }
            if let name = meta.name, !name.isEmpty { return name }
        }
        return truncatedPubkey
    }

    private var truncatedPubkey: String {
        guard let pk = transaction.counterpartyPubkey, !pk.isEmpty else { return "Anonymous" }
        return String(pk.prefix(8)) + "..." + String(pk.suffix(8))
    }

    private var transactionColor: Color {
        transaction.isIncoming ? .green : .orange
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        headerSection
                        detailsCard
                        if transaction.paymentHash != nil || transaction.preimage != nil {
                            technicalCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            // Profile pic or icon
            if transaction.isZap, let pubkey = transaction.counterpartyPubkey, !pubkey.isEmpty {
                Button(action: { navigateToProfile(pubkey: pubkey) }) {
                    VStack(spacing: 10) {
                        ProfilePicView(
                            pubkey: pubkey,
                            size: 72,
                            profile: counterpartyMetadata
                        )

                        HStack(spacing: 4) {
                            Text(counterpartyName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                ZStack {
                    Circle()
                        .fill(transactionColor.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: transaction.isIncoming ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(transactionColor)
                }

                Text(transaction.isIncoming ? "Received" : "Sent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Zap message
            if let msg = transaction.zapMessage, !msg.isEmpty {
                Text("\"\(msg)\"")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Amount
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(transaction.isIncoming ? "+" : "-")\(transaction.formattedAmount)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(transactionColor)
                Text("sats")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(transactionColor.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("DETAILS")

            VStack(spacing: 0) {
                infoRow(
                    icon: transaction.isZap ? "bolt.fill" : "arrow.left.arrow.right",
                    iconColor: transaction.isZap ? .orange : .gray,
                    title: "Type",
                    value: transaction.isZap
                        ? (transaction.isIncoming ? "Received Zap" : "Sent Zap")
                        : (transaction.isIncoming ? "Received" : "Sent")
                )

                if transaction.isZap, transaction.counterpartyPubkey != nil {
                    rowDivider
                    infoRow(
                        icon: "person.fill",
                        iconColor: .accentPurple,
                        title: transaction.isIncoming ? "From" : "To",
                        value: counterpartyName
                    )
                }

                rowDivider
                infoRow(
                    icon: "calendar",
                    iconColor: .blue,
                    title: "Date",
                    value: formattedAbsoluteDate
                )

                if let fees = transaction.feesPaid, fees > 0 {
                    rowDivider
                    infoRow(
                        icon: "percent",
                        iconColor: .yellow,
                        title: "Network Fee",
                        value: "\(formatSats(fees / 1000)) sats"
                    )
                }

                if let coord = transaction.zappedEventCoordinate, !coord.isEmpty {
                    rowDivider
                    infoRow(
                        icon: "play.rectangle.fill",
                        iconColor: .red,
                        title: "Stream",
                        value: extractStreamName(from: coord)
                    )
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        }
    }

    // MARK: - Technical Card

    private var technicalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("TECHNICAL")

            VStack(spacing: 0) {
                if let hash = transaction.paymentHash {
                    copyableRow(icon: "number", iconColor: .cyan, title: "Payment Hash", value: hash)
                }
                if let pre = transaction.preimage {
                    if transaction.paymentHash != nil { rowDivider }
                    copyableRow(icon: "key.fill", iconColor: .orange, title: "Preimage", value: pre)
                }
                if let eventId = transaction.zappedEventId {
                    rowDivider
                    copyableRow(icon: "link", iconColor: .accentPurple, title: "Event ID", value: eventId)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        }
    }

    // MARK: - Reusable Components

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.gray)
            .tracking(0.5)
    }

    private var rowDivider: some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.leading, 52)
    }

    private func infoRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 24, alignment: .center)

            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.gray)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func copyableRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        Button(action: {
            UIPasteboard.general.string = value
            withAnimation(.easeInOut(duration: 0.2)) { copiedField = title }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) { copiedField = nil }
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    Text(copiedField == title ? "Copied!" : truncateHash(value))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(copiedField == title ? .green : .white)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: copiedField == title ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundColor(copiedField == title ? .green : .gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var formattedAbsoluteDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(transaction.createdAt))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func truncateHash(_ hash: String) -> String {
        guard hash.count > 20 else { return hash }
        return String(hash.prefix(12)) + "..." + String(hash.suffix(8))
    }

    private func extractStreamName(from coordinate: String) -> String {
        // Event coordinates are "kind:pubkey:d-tag" — show the d-tag
        let parts = coordinate.split(separator: ":")
        if parts.count >= 3 {
            return String(parts[2])
        }
        return String(coordinate.suffix(min(coordinate.count, 20)))
    }
    private func navigateToProfile(pubkey: String) {
        // Dismiss this detail sheet, then push profile onto the wallet tab's UIKit nav controller
        dismiss()
        
        // Small delay to let the sheet dismiss before pushing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootVC = window.rootViewController else { return }
            
            if let navController = Self.findWalletNavController(from: rootVC) {
                let profileVC = ProfileViewController(appState: appState, publicKeyHex: pubkey)
                profileVC.showBackButton = true
                navController.pushViewController(profileVC, animated: true)
            }
        }
    }
    
    /// Walks the VC hierarchy to find the UINavigationController for the currently selected tab.
    private static func findWalletNavController(from vc: UIViewController) -> UINavigationController? {
        if let tabBar = vc as? UITabBarController,
           let selected = tabBar.selectedViewController {
            return findWalletNavController(from: selected)
        }
        if let nav = vc as? UINavigationController {
            return nav
        }
        for child in vc.children {
            if let nav = findWalletNavController(from: child) {
                return nav
            }
        }
        return nil
    }
}
