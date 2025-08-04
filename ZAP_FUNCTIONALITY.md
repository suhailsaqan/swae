# Zap Functionality Implementation

## Overview
The zapping functionality allows users to send Bitcoin (in satoshis) to streamers and other users over the Lightning Network through the Nostr protocol.

## How to Use

### 1. Connect a Lightning Wallet
- Tap the zap button (⚡️) in the live chat
- If no wallet is connected, you'll see options to connect Alby or Coinos wallets
- Follow the wallet connection process

### 2. Send a Zap
- Once connected, tap the zap button in the live chat
- Choose an amount from the preset options or enter a custom amount
- Optionally add a message
- Tap "Send Zap" to complete the transaction

### 3. View Zap Totals
- The total zap amount for each stream is displayed in the top header
- Tap the zap amount to see debug information

## Technical Implementation

### Key Components

1. **ZapSheetView.swift** - UI for sending zaps
2. **AppState.swift** - Handles zap request creation and sending
3. **LiveChatView.swift** - Displays zap button and amounts

### Zap Flow

1. User taps zap button → ZapSheetView opens
2. User enters amount and message → sendZap() called
3. AppState creates zap request using NostrSDK
4. Zap request sent to Nostr relays
5. Lightning wallet processes payment
6. Zap receipt received and displayed

### Files Modified

- `swae/Views/LiveChatView.swift` - Added zap button and functionality
- `swae/Views/ZapSheetView.swift` - New zap UI
- `swae/Controllers/AppState.swift` - Added zap sending and receiving
- `swae/Components/AlbyButton.swift` - Wallet connection button
- `swae/Components/CoinosButton.swift` - Wallet connection button

## Troubleshooting

### Common Issues

1. **"No wallet connected"** - Connect a Lightning wallet first
2. **"No keypair available"** - Make sure you're signed in with a Nostr key
3. **Zap not appearing** - Check relay connections and wallet status

### Debug Information

- Tap the zap amount in the header to see debug logs
- Check console for zap request/receipt logs
- Verify wallet connection status in AppState

## Future Enhancements

- [ ] Implement actual wallet connections for Alby and Coinos
- [ ] Add zap notifications and sounds
- [ ] Support for custom zap amounts
- [ ] Zap history and analytics
- [ ] Integration with more Lightning wallets 