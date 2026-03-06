<p align="center">
  <img src="swae/Assets.xcassets/SwaeLogo.imageset/swae-particle-1600x400.png" alt="Swae Logo" width="400"/>
</p>

<h1 align="center">Swae</h1>

<p align="center">
  <strong>Professional live streaming from your iPhone, powered by Nostr and Bitcoin.</strong>
</p>

<p align="center">
  <a href="https://github.com/suhailsaqan/swae/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue.svg" alt="License: GPL-3.0"/></a>
  <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+"/></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-17.0+-lightgrey.svg" alt="iOS 17.0+"/></a>
  <a href="https://swae.live"><img src="https://img.shields.io/badge/web-swae.live-purple.svg" alt="Website"/></a>
</p>

<p align="center">
  <a href="#-what-is-swae">What is Swae?</a> •
  <a href="#-features">Features</a> •
  <a href="#-getting-started">Getting Started</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#-contributing">Contributing</a> •
  <a href="#-roadmap">Roadmap</a>
</p>

---

## 🎬 What is Swae?

Swae is the only professional-grade IRL streaming app on iOS built natively on the [Nostr](https://nostr.com/) protocol. It turns your iPhone into a complete broadcast studio — GPU-accelerated video effects, on-stream chat overlays, hardware integrations, scene management, and real-time Lightning payments — all in a single free app.

No desktop. No capture card. No OBS. No expensive equipment. Just your iPhone.

**Why Nostr?** Your identity is your keypair, portable across every Nostr client. Your audience follows you across relays, not locked to a single server. Your income arrives as Lightning zaps — settled instantly, no platform cut, no minimum payouts, no bank account required, and no one can freeze or censor your earnings.

**Why Bitcoin?** Streamers are among the most frequently deplatformed creators on the internet. Platforms like Twitch, YouTube, and TikTok wipe out channels, audiences, and income overnight. Swae gives creators financial sovereignty: instant, borderless payments that no centralized processor can withhold.

> 📖 For a deep dive into the codebase, see the **[Architecture Guide](docs/ARCHITECTURE.md)** and **[Video Pipeline Guide](docs/VIDEO-PIPELINE.md)**.

---

## ✨ Features

### 📡 Live Streaming

- **RTMP, SRT, and HLS** protocol support
- **Adaptive bitrate** — real-time adjustment for unstable cellular networks
- **SRTLA** (SRT Link Aggregation) — bonds WiFi + cellular for redundant delivery
- **Multi-destination RTMP** — stream to Nostr and Twitch/Kick/YouTube simultaneously
- **Background streaming** — keep broadcasting when the app is backgrounded
- **Landscape and portrait** orientation support
- **Configurable metadata** — title, description, cover image, tags, content warnings, categories
- **Real-time stats** — uptime, bitrate, FPS, viewer count

### 🎨 Video Effects & Widgets

Over 30 GPU-accelerated video effects composited directly into the broadcast output:

| Effect | Description |
|--------|-------------|
| **Chat Overlay** | Renders live Nostr chat on-stream with full visual customization |
| **Zap Plasma** | Custom Metal shader — plasma tendrils converge on the stream when zaps arrive |
| **Guest PiP** | WebRTC remote video composited as picture-in-picture |
| **Browser Widget** | Embed any web content (alerts, overlays, dashboards) |
| **Beauty / Face** | Real-time face detection and beauty filters |
| **LUT** | Color grading with lookup tables |
| **Text / Image / Shape** | Custom overlays with positioning |
| **Map** | Live location map overlay |
| **QR Code** | Dynamic QR code generation on-stream |
| **Remove Background** | AI-powered background removal |
| **VTuber** | Virtual avatar driven by face tracking |
| **Draw on Stream** | Freehand drawing directly on the video |
| **Poll** | Interactive polls rendered into the broadcast |
| **Replay** | Instant replay effect |
| **Twin / Triple** | Multi-camera split effects |
| **Pixellate / Pinch / Whirlpool** | Distortion effects |
| **Grayscale / Sepia / Opacity** | Color manipulation |
| **Slideshow / Movie** | Media playback overlays |
| **360° Dewarp** | Spherical video correction |
| **Scoreboard** | Sports scoreboard overlay |

All effects run on the GPU via Core Image and MetalPetal — no frame drops, even with multiple widgets active.

**Scene Management** — configure different widget layouts and switch between them live, just like OBS scenes.

### ⚡ Lightning Payments & Wallet

- **Send and receive zaps** during live streams
- **Built-in Lightning wallet** with NWC (Nostr Wallet Connect) support
- **One-click Coinos wallet** creation from your Nostr identity
- **Auto-topup** — automatically fund streaming costs from your wallet
- **Invoice generation** and payment with QR codes
- **Balance tracking** with runway estimation
- **Transaction history** and zap receipt tracking
- **Zap feed** — real-time activity of incoming zaps

### 🤝 Live Collaboration (WebRTC)

- **Invite a guest** onto your stream with a single tap
- **Picture-in-picture** video composited directly into the broadcast
- **Mixed audio** — guest audio mixed into the RTMP output
- **Signaled over Nostr** — NIP-04 encrypted DMs, no centralized server
- **Heartbeat monitoring** — automatic detection of connection loss
- **ICE restart** — graceful recovery from network changes

### 📱 Hardware Integrations

| Device | Capability |
|--------|------------|
| **GoPro** | Use as stream source via WiFi |
| **DJI Drones** | Stream aerial footage directly |
| **External Display** | Monitor your stream on a second screen |

### 🔍 Discovery & Social

- **Hero section** — featured live streams with parallax scrolling
- **Category browsing** — IRL, Gaming, Music, Talk, Art, Gambling, Sports, Cooking, Education, Tech, and more
- **Search** — find streams and users with Trie-based instant search + Profilestr API
- **Most Zapped Streamers** — rankings by Lightning tips
- **Following feed** — streams from people you follow
- **Twitter/X-style profiles** — banner, profile pic, bio, follow/unfollow, zap button
- **QR code sharing** — share your Nostr profile via QR

### ⌚ Apple Watch Companion

- View live chat on your wrist
- Stream monitoring and controls
- Chat preview with emote support

### 🎛️ Streamer Dashboard

- **Control panel** with live chat and quick actions
- **OBS WebSocket** remote control support
- **Stream key management** for scheduled and recurring streams
- **Ingest server** — run a local RTMP/SRT/RIST ingest

### 🔐 Security

- Private keys stored in the iOS Keychain with hardware-backed encryption
- Face ID / Touch ID required to view or copy keys
- Sensitive data automatically cleared from clipboard
- No key material ever logged

---

## 🚀 Getting Started

### Prerequisites

- **Xcode 15.0+** (latest recommended)
- **iOS 17.0+** deployment target
- **Swift 5.9+**
- An Apple Developer account (for device testing)

### Installation

```bash
# Clone the repository
git clone https://github.com/suhailsaqan/swae.git
cd swae

# Open in Xcode
open swae.xcodeproj
```

1. Xcode will automatically resolve Swift Package Manager dependencies
2. Select your target device or simulator
3. Build and run (⌘R)

### Configuration

**Coinos API Key** (optional, for wallet creation):
- Copy `swae/Services/CoinosApiKey.example` to `swae/Services/CoinosApiKey.swift`
- Add your Coinos API key

### First Launch

1. **Create an account** — generate a new Nostr keypair, or sign in with an existing one
2. **Connect a wallet** — link a Lightning wallet via NWC or create one with Coinos
3. **Go live** — tap the camera tab, configure your stream, and hit the Go Live orb

---

## 🏗️ Architecture

> 📖 Full details in **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**

### Project Structure

```
swae/
├── swaeApp.swift                    # App entry point (UIApplicationDelegate + SceneDelegate)
├── AppCoordinator.swift             # Singleton — initializes SwiftData, AppState, Model
├── RootViewController.swift         # UIKit root hosting SwiftUI content
├── ContentView.swift                # SwiftUI content view
│
├── Controllers/                     # UIKit view controllers
│   ├── AppState.swift               # Global Nostr protocol state (relays, events, wallet)
│   ├── ModernTabBarController.swift # iOS 18+ tab bar with Liquid Glass
│   ├── ProfileViewController.swift  # Twitter/X-style profile
│   ├── Camera/                      # Camera & streaming UI
│   ├── ControlPanel/                # Streamer dashboard
│   ├── Onboarding/                  # Sign up / sign in flow
│   └── Profile/                     # Edit profile, following list
│
├── Various/Model/                   # Core streaming model
│   ├── Model.swift                  # Stream config, effects, camera, widgets
│   ├── ModelNostrChat.swift         # Chat bridge (AppState → NostrChatEffect)
│   ├── ModelCollab.swift            # WebRTC collaboration state
│   └── ModelGoProDevice.swift       # GoPro device state
│
├── Models/                          # Data models & view models
│   ├── NostrEventStore.swift        # Centralized NIP-16/33/53 deduplication
│   ├── WalletModel.swift            # NWC wallet state
│   ├── CollabCallState.swift        # WebRTC call lifecycle
│   ├── SearchViewModel.swift        # Search with Trie + Profilestr
│   ├── StreamCategory.swift         # Category definitions
│   └── ...
│
├── Services/                        # Business logic services
│   ├── WebRTCService.swift          # WebRTC peer connection management
│   ├── NWCClient.swift              # Actor-based Nostr Wallet Connect
│   ├── AudioMixerService.swift      # Audio mixing for collab
│   ├── ZapService.swift             # Lightning zap operations
│   ├── LNURLService.swift           # LNURL protocol
│   ├── CoinosClient.swift           # Coinos API integration
│   └── ...
│
├── VideoEffects/                    # 30+ GPU-accelerated effects
│   ├── NostrChatEffect.swift        # Chat overlay rendering
│   ├── ZapPlasmaEffect.swift        # Metal shader zap visualization
│   ├── GuestVideoCompositor.swift   # WebRTC PiP compositing
│   └── ...
│
├── Metal/                           # Custom Metal shaders
│   ├── ZapPlasmaShaders.metal       # Plasma tendril animation
│   ├── BubblyOrbShaders.metal       # Animated orb button
│   ├── ParticleCompute.metal        # GPU particle simulation
│   └── ...
│
├── Components/                      # Reusable UI components
│   ├── LiquidGlass/                 # iOS 26-style morphing glass modals
│   ├── StreamCard/                  # Stream card cells
│   ├── ZapButton.swift              # Zap interaction button
│   └── ...
│
├── Views/                           # SwiftUI + UIKit views
│   ├── VideoListViewController.swift # Home feed with hero + carousels
│   ├── StreamCamera/                # Camera, settings, stream views
│   ├── Wallet/                      # Wallet UI (balance, send, receive)
│   ├── Onboarding/                  # Onboarding flow
│   └── ...
│
├── Integrations/                    # External hardware & services
│   ├── GoPro/                       # Bluetooth + WiFi GoPro control
│   ├── Dji/                         # DJI drone integration
│   ├── Tesla/                       # Tesla vehicle integration
│   ├── ZapStreamCore/               # zap.stream API client
│   └── ...
│
├── Media/HaishinKit/                # Forked streaming engine
│   └── Media/
│       ├── Video/VideoUnit.swift    # Camera capture + effects pipeline
│       └── Audio/AudioUnit.swift    # Microphone + audio encoding
│
├── GenericLivePlayer/               # Video player for watching streams
├── Obs/                             # OBS WebSocket integration
├── RemoteControl/                   # Remote control via relay
├── Notify/                          # Push notifications
└── Util/                            # Keychain, orientation, parsing, etc.

Swae Watch Watch App/                # watchOS companion
├── View/Chat/                       # Watch chat display
├── View/Control/                    # Stream controls
└── View/Preview/                    # Stream preview

Swae Screen Recording/               # ReplayKit extension
├── SampleHandler.swift              # Screen capture handler
└── Shared/                          # IPC buffer transport

Common/                              # Shared utilities
├── Various/                         # Audio/video buffer extensions
└── View/                            # Shared overlay views
```

### Key Design Patterns

- **Singleton Coordinator** — `AppCoordinator` initializes and owns all global state
- **Observable Objects** — `AppState`, `Model`, `WalletModel` drive reactive UI via Combine
- **Actor Concurrency** — `NWCClient`, `BackgroundPersistenceActor` for thread-safe async operations
- **GPU Pipeline** — Video effects chain using `CIFilter.sourceOverCompositing` (CIImage) and `MTIMultilayerCompositingFilter` (MetalPetal)
- **Strict Threading** — encoding on `processorPipelineQueue`, chat on `nostrChatQueue`, audio on lock queue, UI on main thread only
- **O(1) Deduplication** — Set-based duplicate detection for chat messages, zaps, raids, clips
- **Trie Search** — `SwiftTrie` for instant prefix-based search across events, profiles, and live activities

### Nostr Protocol Support

| NIP | Description | Usage |
|-----|-------------|-------|
| NIP-01 | Basic protocol | Event creation, relay communication |
| NIP-04 | Encrypted DMs | WebRTC call signaling |
| NIP-16 | Replaceable events | Metadata, follow lists |
| NIP-33 | Parameterized replaceable | Live activities (kind 30311) |
| NIP-40 | Expiration | Event TTL handling |
| NIP-51 | Lists | Mute lists, bookmarks |
| NIP-53 | Live Activities | Stream metadata, chat (1311), raids (1312), clips (1313) |
| NIP-57 | Lightning Zaps | Zap requests and receipts |
| NIP-98 | HTTP Auth | zap.stream API authentication |

### Dependencies

| Package | Purpose |
|---------|---------|
| [NostrSDK](https://github.com/nostr-sdk) | Nostr protocol implementation |
| [WebRTC](https://webrtc.org/) | Real-time peer-to-peer communication |
| [HaishinKit](https://github.com/shogo4405/HaishinKit.swift) | RTMP/SRT streaming engine (forked) |
| [MetalPetal](https://github.com/MetalPetal/MetalPetal) | GPU image processing |
| [Kingfisher](https://github.com/onevcat/Kingfisher) | Image caching and loading |
| [SDWebImage](https://github.com/SDWebImage/SDWebImage) | Web image loading (WebP) |
| [TrueTime](https://github.com/instacart/TrueTime.swift) | NTP time synchronization |
| [SwiftTrie](https://github.com/nicklama/swift-trie) | Prefix search data structure |
| [AlertToast](https://github.com/elai950/AlertToast) | Toast notifications |

---

## 🤝 Contributing

Contributions are welcome. To get started:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Build and test in Xcode
5. Commit (`git commit -m 'feat: add my feature'`)
6. Push (`git push origin feature/my-feature`)
7. Open a Pull Request

Please follow [Conventional Commits](https://www.conventionalcommits.org/) for commit messages.

---

## 📄 License

This project is licensed under the **GPL-3.0 License**. See the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

Built by [Suhail Saqan](https://github.com/suhailsaqan).

Swae builds on the work of the Nostr protocol community, the Bitcoin Lightning Network, and open-source projects including HaishinKit, WebRTC, MetalPetal, and NostrSDK.

---

<p align="center">
  <strong>Stream free. Get paid in Bitcoin. Own your audience.</strong>
</p>
