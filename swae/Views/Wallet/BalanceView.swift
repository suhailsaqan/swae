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
    var onGetBitcoinTapped: (() -> Void)? = nil

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

                // Zero-balance nudge
                if balance == 0, let onGetBitcoinTapped {
                    Button(action: onGetBitcoinTapped) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("Fund your wallet")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.orange.opacity(0.8))
                    }
                    .padding(.top, 4)
                }
            } else {
                // Skeleton loading state
                BalanceSkeletonView()
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

// MARK: - Skeleton Views

struct BalanceSkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .frame(width: 180, height: 44)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
                .frame(width: 50, height: 16)
        }
        .opacity(isAnimating ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

struct TransactionSkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 120, height: 14)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 80, height: 12)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 60, height: 14)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 30, height: 10)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
            }
        }
        .opacity(isAnimating ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

#Preview {
    VStack(spacing: 20) {
        BalanceView(balance: 1_234_567, hideBalance: .constant(false))
        BalanceView(balance: nil, hideBalance: .constant(false))
        BalanceView(balance: 50000, hideBalance: .constant(true))
        BalanceView(balance: 0, hideBalance: .constant(false), onGetBitcoinTapped: {})
    }
    .padding()
    .background(Color.black)
}
