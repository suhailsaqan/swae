//
//  TransactionsView.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import SwiftUI

struct TransactionsView: View {
    let transactions: [WalletTransaction]?
    @Binding var hideBalance: Bool

    var sortedTransactions: [WalletTransaction] {
        transactions?.sorted(by: { $0.createdAt > $1.createdAt }) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Transactions")
                .font(.headline)
                .foregroundColor(.primary)

            Group {
                if let transactions = transactions {
                    if transactions.isEmpty {
                        emptyTransactionsView
                    } else {
                        ForEach(sortedTransactions) { transaction in
                            TransactionRowView(
                                transaction: transaction,
                                hideBalance: $hideBalance
                            )
                        }
                    }
                } else {
                    // Loading state
                    ForEach(Array(0..<3), id: \.self) { _ in
                        TransactionRowView(
                            transaction: nil,
                            hideBalance: $hideBalance
                        )
                        .redacted(reason: .placeholder)
                        .shimmer(true)
                    }
                }
            }
        }
    }

    var emptyTransactionsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 48))
                .foregroundColor(.orange.opacity(0.6))

            Text("No transactions yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Your Lightning transactions will appear here")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

struct TransactionRowView: View {
    let transaction: WalletTransaction?
    @Binding var hideBalance: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Transaction icon
            ZStack {
                Circle()
                    .fill(transactionColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: transactionIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(transactionColor)
            }

            // Transaction details
            VStack(alignment: .leading, spacing: 4) {
                Text(transactionDescription)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(transactionDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                if hideBalance {
                    Text("••••")
                        .font(.headline)
                        .foregroundColor(transactionColor)
                } else {
                    Text(amountText)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(transactionColor)
                }

                Text("sats")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Computed Properties

    private var transactionColor: Color {
        guard let transaction = transaction else { return .gray }
        return transaction.isIncoming ? .green : .orange
    }

    private var transactionIcon: String {
        guard let transaction = transaction else { return "bolt" }
        return transaction.type.icon
    }

    private var transactionDescription: String {
        guard let transaction = transaction else { return "Loading..." }
        return transaction.displayDescription
    }

    private var transactionDate: String {
        guard let transaction = transaction else { return "" }
        return transaction.formattedDate
    }

    private var amountText: String {
        guard let transaction = transaction else { return "••••" }
        let prefix = transaction.isIncoming ? "+" : "-"
        return "\(prefix)\(transaction.formattedAmount)"
    }
}

#Preview {
    VStack(spacing: 20) {
        TransactionsView(
            transactions: WalletTransaction.mockTransactions,
            hideBalance: .constant(false)
        )

        Divider()

        TransactionsView(
            transactions: [],
            hideBalance: .constant(false)
        )

        Divider()

        TransactionsView(
            transactions: nil,
            hideBalance: .constant(false)
        )
    }
    .padding()
    .background(Color.black)
}
