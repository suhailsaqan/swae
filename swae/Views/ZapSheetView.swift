//
//  ZapSheetView.swift
//  swae
//
//  Created by Suhail Saqan on 3/7/25.
//

import SwiftUI
import NostrSDK

struct ZapSheetView: View {
    let event: LiveActivitiesEvent
    @Binding var amount: String
    @Binding var message: String
    let onSendZap: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    private let presetAmounts = [1000, 5000, 10000, 50000, 100000] // in sats
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Send Zap")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Support the streamer with Bitcoin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Amount presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("Amount (sats)")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        ForEach(presetAmounts, id: \.self) { presetAmount in
                            Button(action: {
                                amount = String(presetAmount)
                            }) {
                                Text("\(presetAmount)")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(amount == String(presetAmount) ? Color.orange : Color(.systemGray5))
                                    )
                                    .foregroundColor(amount == String(presetAmount) ? .white : .primary)
                            }
                        }
                    }
                    
                    // Custom amount input
                    TextField("Custom amount", text: $amount)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
                
                // Message input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Message (optional)")
                        .font(.headline)
                    
                    TextField("Add a message...", text: $message, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                
                Spacer()
                
                // Wallet connection status
                if appState.wallet == nil {
                    VStack(spacing: 8) {
                        Text("Connect a Lightning Wallet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            AlbyButton {
                                // TODO: Implement Alby wallet connection
                                print("Connect to Alby")
                            }
                            
                            CoinosButton {
                                // TODO: Implement Coinos wallet connection
                                print("Connect to Coinos")
                            }
                        }
                    }
                    .padding(.bottom)
                } else {
                    // Send button
                    Button(action: {
                        onSendZap()
                    }) {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Send Zap")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(amount.isEmpty || Int64(amount) == nil ? Color.gray : Color.orange)
                        )
                    }
                    .disabled(amount.isEmpty || Int64(amount) == nil)
                    .padding(.bottom)
                }
            }
            .padding(.horizontal)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
} 