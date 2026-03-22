//
//  TransactionsView.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import NostrSDK
import SwiftUI

enum TransactionFilter: String, CaseIterable {
    case all = "All"
    case received = "Received"
    case sent = "Sent"
    case zaps = "Zaps"
}

struct TransactionsView: View {
    let transactions: [WalletTransaction]?
    @Binding var hideBalance: Bool
    @State private var filter: TransactionFilter = .all

    var sortedTransactions: [WalletTransaction] {
        transactions?.sorted(by: { $0.createdAt > $1.createdAt }) ?? []
    }

    var filteredTransactions: [WalletTransaction] {
        switch filter {
        case .all: return sortedTransactions
        case .received: return sortedTransactions.filter { $0.isIncoming }
        case .sent: return sortedTransactions.filter { !$0.isIncoming }
        case .zaps: return sortedTransactions.filter { $0.isZap }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Transactions")
                .font(.headline)
                .foregroundColor(.primary)
            if let txs = transactions, !txs.isEmpty { filterTabs }
            Group {
                if let _ = transactions {
                    if filteredTransactions.isEmpty {
                        emptyView
                    } else {
                        ForEach(filteredTransactions) { tx in
                            TransactionRowView(transaction: tx, hideBalance: $hideBalance)
                        }
                    }
                } else {
                    TransactionSkeletonView()
                }
            }
        }
    }

    private var filterTabs: some View {
        HStack(spacing: 8) {
            ForEach(TransactionFilter.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { filter = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: filter == tab ? .semibold : .medium))
                        .foregroundColor(filter == tab ? .white : .gray)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(filter == tab ? Color.accentPurple : Color.primary.opacity(0.08)))
                }
            }
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle").font(.system(size: 48)).foregroundColor(.orange.opacity(0.6))
            Text(filter == .all ? "No transactions yet" : "No \(filter.rawValue.lowercased()) transactions")
                .font(.headline).foregroundColor(.secondary)
            if filter == .all {
                Text("Your Lightning transactions will appear here")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Transaction Row

struct TransactionRowView: View {
    let transaction: WalletTransaction?
    @Binding var hideBalance: Bool
    @EnvironmentObject var appState: AppState
    @State private var showDetail = false

    private var metadata: UserMetadata? {
        guard let pk = transaction?.counterpartyPubkey else { return nil }
        return appState.metadataEvents[pk]?.userMetadata
    }
    private var displayName: String? {
        guard let m = metadata else { return nil }
        if let d = m.displayName, !d.isEmpty { return d }
        if let n = m.name, !n.isEmpty { return n }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            // Profile pic — tap pushes profile page via UIKit (same as feed)
            if let tx = transaction, tx.isZap, let pk = tx.counterpartyPubkey, !pk.isEmpty {
                Button { pushProfile(pubkey: pk) } label: {
                    ProfilePicView(pubkey: pk, size: 44, profile: metadata)
                }.buttonStyle(.plain)
            } else {
                ZStack {
                    Circle().fill(txColor.opacity(0.2)).frame(width: 44, height: 44)
                    Image(systemName: txIcon).font(.system(size: 18, weight: .medium)).foregroundColor(txColor)
                }
            }
            // Rest of row — tap opens detail sheet
            Button { if transaction != nil { showDetail = true } } label: {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
                        if let msg = transaction?.zapMessage, !msg.isEmpty {
                            Text(msg).font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Text(date).font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if hideBalance {
                            Text("••••").font(.system(size: 16, weight: .semibold)).foregroundColor(txColor)
                        } else {
                            Text(amount).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(txColor)
                        }
                        Text("sats").font(.system(size: 11)).foregroundColor(.gray)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
        .sheet(isPresented: $showDetail) {
            if let tx = transaction { TransactionDetailView(transaction: tx).environmentObject(appState) }
        }
    }

    // MARK: - UIKit Profile Push (same pattern as VideoListViewController)

    private func pushProfile(pubkey: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let root = window.rootViewController else { return }
        guard let tabBar = Self.findTabBar(from: root),
              let nav = tabBar.selectedViewController as? UINavigationController else { return }
        let vc = ProfileViewController(appState: appState, publicKeyHex: pubkey)
        vc.showBackButton = true
        nav.pushViewController(vc, animated: true)
    }

    private static func findTabBar(from vc: UIViewController) -> UITabBarController? {
        if let tb = vc as? UITabBarController { return tb }
        for child in vc.children { if let f = findTabBar(from: child) { return f } }
        return nil
    }

    // MARK: - Helpers

    private var txColor: Color {
        guard let t = transaction else { return .gray }; return t.isIncoming ? .green : .orange
    }
    private var txIcon: String { transaction?.type.icon ?? "bolt" }
    private var label: String {
        guard let t = transaction else { return "Loading..." }
        if let n = displayName { return n }
        if t.isZap, let pk = t.counterpartyPubkey, !pk.isEmpty { return String(pk.prefix(8)) + "..." }
        if t.isZap { return t.isIncoming ? "Anonymous Zap" : "Zap" }
        return t.displayDescription
    }
    private var date: String { transaction?.formattedDate ?? "" }
    private var amount: String {
        guard let t = transaction else { return "••••" }
        return "\(t.isIncoming ? "+" : "-")\(t.formattedAmount)"
    }
}
