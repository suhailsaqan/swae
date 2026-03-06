//
//  BalanceView.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import SwiftUI

struct BalanceView: View {
    var balance: Int64?
    @Binding var hideBalance: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("Current Balance")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let balance = balance {
                NumericalBalanceView(
                    balance: balance,
                    hideBalance: $hideBalance
                )
            } else {
                // Show loading state
                Text("•••••")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundColor(.orange)
                    .redacted(reason: .placeholder)
                    .shimmer(true)
            }
        }
        .padding(.vertical, 20)
    }
}

struct NumericalBalanceView: View {
    let balance: Int64
    @Binding var hideBalance: Bool

    var body: some View {
        Group {
            if hideBalance {
                Text("•••••")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundColor(.orange)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatSats(balance / 1000))
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundColor(.orange)

                    Text("sats")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
            }
        }
        .onTapGesture {
            hideBalance.toggle()
        }
        .animation(.easeInOut(duration: 0.2), value: hideBalance)
    }
}

// MARK: - Helper Functions

func formatSats(_ sats: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
}

#Preview {
    VStack(spacing: 20) {
        BalanceView(balance: 1_234_567, hideBalance: .constant(false))
        BalanceView(balance: nil, hideBalance: .constant(false))
        BalanceView(balance: 50000, hideBalance: .constant(true))
    }
    .padding()
    .background(Color.black)
}
