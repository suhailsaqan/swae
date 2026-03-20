import CoreImage.CIFilterBuiltins
import MetalPetal
import SDWebImage
import SwiftUI

private let nostrChatQueue = DispatchQueue(label: "com.suhail.widget.nostrchat")

struct NostrChatDisplayItem: Identifiable {
    let id: String
    let displayName: String
    let pubkeyColorSeed: Int
    let content: String
    let isZap: Bool
    let zapAmount: Int64?
    let timestamp: Date
    let customEmojis: [String: URL]  // shortcode → imageURL (NIP-30)
}

final class NostrChatEffect: VideoEffect {
    // CIImage path
    private let filter = CIFilter.sourceOverCompositing()
    private var overlay: CIImage?
    private var image: UIImage?
    private var latestRenderedImage: UIImage?

    // MetalPetal path
    private var overlayMetalPetal: MTIImage?
    private var imageMetalPetal: UIImage?

    // Shared state (protected by nostrChatQueue)
    private var messages: [NostrChatDisplayItem] = []
    private var settings: SettingsWidgetNostrChat
    private var x: Double = 0
    private var y: Double = 0
    private var widgetWidth: Double = 25
    private var widgetHeight: Double = 50
    private var needsRedraw = true

    // Throttling
    private var nextUpdateTime = ContinuousClock.now
    private var nextUpdateTimeMetalPetal = ContinuousClock.now
    private static let updateInterval: ContinuousClock.Duration = .milliseconds(500)

    private let settingName: String

    init(widget: SettingsWidgetNostrChat, settingName: String) {
        self.settings = widget
        self.settingName = settingName
        super.init()
    }

    override func getName() -> String {
        return "\(settingName) nostr chat widget"
    }

    // MARK: - Data Input

    /// Replaces the entire message list with a pre-sorted array from the Combine bridge.
    /// Only marks dirty if content actually changed (avoids redundant renders).
    func replaceAllMessages(_ items: [NostrChatDisplayItem]) {
        // Prefetch emote images on background before taking the lock
        prefetchEmoteImages(items)
        
        nostrChatQueue.sync {
            guard items.count != messages.count || items.last?.id != messages.last?.id else { return }
            let oldCount = messages.count
            if items.count > settings.maxMessages {
                messages = Array(items.suffix(settings.maxMessages))
            } else {
                messages = items
            }
            needsRedraw = true
            if messages.count != oldCount {
                print("🎨 NostrChatEffect[\(settingName)]: replaceAllMessages \(oldCount) → \(messages.count)")
            }
        }
    }

    func updateSettings(_ newSettings: SettingsWidgetNostrChat) {
        nostrChatQueue.sync {
            settings = newSettings
            needsRedraw = true
        }
    }

    // MARK: - Position

    func setSceneWidget(sceneWidget: SettingsSceneWidget?) {
        nostrChatQueue.sync {
            if let sceneWidget {
                self.x = sceneWidget.x
                self.y = sceneWidget.y
                self.widgetWidth = sceneWidget.width
                self.widgetHeight = sceneWidget.height
            }
            // Width change affects rendered content, so mark dirty
            needsRedraw = true
        }
    }

    // MARK: - Rendering

    private func usernameColor(for item: NostrChatDisplayItem) -> Color {
        switch settings.usernameStyle {
        case .coloredFromPubkey:
            return Color(
                hue: Double(abs(item.pubkeyColorSeed) % 360) / 360.0,
                saturation: 0.7,
                brightness: 0.9
            )
        case .singleColor:
            return settings.usernameColor.color()
        case .hidden:
            return .clear
        }
    }

    /// Maximum number of lines a single chat message can occupy.
    /// Prevents one huge message from consuming the entire widget height.
    private static let maxLinesPerMessage = 3

    private func triggerRender(size: CGSize, forMetalPetal: Bool) {
        let (msgs, settings, wWidth, wHeight) = nostrChatQueue.sync {
            self.needsRedraw = false
            return (self.messages, self.settings, self.widgetWidth, self.widgetHeight)
        }

        let count = msgs.count
        print("🎨 NostrChatEffect[\(settingName)]: triggerRender msgs=\(count) metalPetal=\(forMetalPetal)")

        let fontSize = CGFloat(settings.fontSize) * (size.maximum() / 1920)
        let renderWidth = toPixels(wWidth, size.width)
        let renderHeight = toPixels(wHeight, size.height)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let chatView: AnyView
            if msgs.isEmpty {
                chatView = AnyView(self.buildEmptyStateView(
                    settings: settings,
                    fontSize: fontSize,
                    renderWidth: renderWidth,
                    renderHeight: renderHeight
                ))
            } else {
                let orderedMessages = settings.scrollDirection == .bottomToTop
                    ? msgs : msgs.reversed()
                chatView = AnyView(self.buildChatView(
                    messages: orderedMessages,
                    settings: settings,
                    fontSize: fontSize,
                    renderWidth: renderWidth,
                    renderHeight: renderHeight
                ))
            }

            let renderer = ImageRenderer(content: chatView)
            let uiImage = renderer.uiImage

            nostrChatQueue.sync {
                if forMetalPetal {
                    self.imageMetalPetal = uiImage
                } else {
                    self.image = uiImage
                }
            }
        }
    }

    private func buildChatView(
        messages: [NostrChatDisplayItem],
        settings: SettingsWidgetNostrChat,
        fontSize: CGFloat,
        renderWidth: Double,
        renderHeight: Double
    ) -> some View {
        // For bottomToTop: newest message at bottom, content anchored to bottom.
        // For topToBottom: newest message at top, content anchored to top.
        VStack(alignment: .leading, spacing: CGFloat(settings.messageSpacing)) {
            ForEach(messages) { msg in
                HStack(alignment: .top, spacing: 4) {
                    if settings.showTimestamps {
                        Text(msg.timestamp, style: .time)
                            .foregroundColor(settings.timestampColor.color())
                            .font(.system(size: fontSize * 0.8))
                    }
                    if msg.isZap && settings.showZaps && settings.showZapAmount {
                        Text("⚡\(msg.zapAmount ?? 0)")
                            .foregroundColor(settings.zapColor.color())
                            .fontWeight(.bold)
                    }
                    if settings.usernameStyle != .hidden {
                        Text(msg.displayName + (settings.showColon ? ":" : ""))
                            .foregroundColor(self.usernameColor(for: msg))
                            .fontWeight(settings.usernameFontWeight.toSystem())
                            .lineLimit(1)
                    }
                    self.emojifiedText(msg.content, emojis: msg.customEmojis, fontSize: fontSize)
                        .foregroundColor(settings.messageColor.color())
                        .lineLimit(Self.maxLinesPerMessage)
                }
                .font(.system(size: fontSize, design: settings.fontDesign.toSystem()))
                .fontWeight(settings.fontWeight.toSystem())
                .shadow(
                    color: settings.textShadow
                        ? settings.textShadowColor.color() : .clear,
                    radius: CGFloat(settings.textShadowRadius)
                )
                .padding(
                    settings.perMessageBackground
                        ? CGFloat(settings.messagePadding) : 0
                )
                .background(
                    settings.perMessageBackground
                        ? settings.perMessageBackgroundColor.color() : .clear
                )
                .cornerRadius(
                    settings.perMessageBackground
                        ? CGFloat(settings.perMessageCornerRadius) : 0
                )
            }
        }
        .padding(CGFloat(settings.messagePadding))
        .frame(width: renderWidth, height: renderHeight,
               alignment: settings.scrollDirection == .bottomToTop ? .bottomLeading : .topLeading)
        .clipped()
        .background(settings.backgroundColor.color())
        .cornerRadius(CGFloat(settings.cornerRadius))
    }

    /// Renders a placeholder when no chat messages have arrived yet.
    private func buildEmptyStateView(
        settings: SettingsWidgetNostrChat,
        fontSize: CGFloat,
        renderWidth: Double,
        renderHeight: Double
    ) -> some View {
        VStack {
            Text("No chat messages yet")
                .foregroundColor(settings.messageColor.color().opacity(0.5))
                .font(.system(size: fontSize, design: settings.fontDesign.toSystem()))
                .fontWeight(settings.fontWeight.toSystem())
                .shadow(
                    color: settings.textShadow
                        ? settings.textShadowColor.color() : .clear,
                    radius: CGFloat(settings.textShadowRadius)
                )
        }
        .padding(CGFloat(settings.messagePadding))
        .frame(width: renderWidth, height: renderHeight, alignment: .center)
        .background(settings.backgroundColor.color())
        .cornerRadius(CGFloat(settings.cornerRadius))
    }

    // MARK: - Emote Image Cache (NIP-30)
    
    /// Prefetches emote images for all messages so they're available synchronously during render.
    private func prefetchEmoteImages(_ items: [NostrChatDisplayItem]) {
        let urls = items.flatMap { Array($0.customEmojis.values) }
        guard !urls.isEmpty else { return }
        EmoteImageCache.shared.prefetch(urls: urls)
    }
    
    /// Builds a SwiftUI Text/view with inline emote images from cache.
    /// Falls back to :shortcode: text if image isn't cached yet.
    @ViewBuilder
    private func emojifiedText(_ content: String, emojis: [String: URL], fontSize: CGFloat) -> some View {
        if emojis.isEmpty {
            Text(content)
        } else {
            // Rebuild: split on :shortcode: patterns, check if each is a known emoji
            let segments = Self.parseEmoteSegments(content, emojis: emojis)
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    switch seg {
                    case .text(let str):
                        Text(str)
                    case .emote(let url):
                        if let cached = EmoteImageCache.shared.image(for: url) {
                            Image(uiImage: cached)
                                .resizable()
                                .frame(width: fontSize * 1.2, height: fontSize * 1.2)
                        } else {
                            // Not cached yet — show shortcode as text
                            Text("⬜")
                        }
                    }
                }
            }
        }
    }
    
    private enum EmoteSegment {
        case text(String)
        case emote(URL)
    }
    
    /// Splits content on :shortcode: patterns matching known emoji URLs.
    private static func parseEmoteSegments(_ content: String, emojis: [String: URL]) -> [EmoteSegment] {
        guard let regex = try? NSRegularExpression(pattern: ":([_a-zA-Z0-9]+):") else {
            return [.text(content)]
        }
        
        var segments: [EmoteSegment] = []
        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: nsRange)
        
        if matches.isEmpty { return [.text(content)] }
        
        var lastIndex = content.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: content),
                  let shortcodeRange = Range(match.range(at: 1), in: content) else { continue }
            
            if lastIndex < fullRange.lowerBound {
                segments.append(.text(String(content[lastIndex..<fullRange.lowerBound])))
            }
            
            let shortcode = String(content[shortcodeRange])
            if let url = emojis[shortcode] {
                segments.append(.emote(url))
            } else {
                segments.append(.text(String(content[fullRange])))
            }
            lastIndex = fullRange.upperBound
        }
        
        if lastIndex < content.endIndex {
            segments.append(.text(String(content[lastIndex...])))
        }
        
        return segments
    }

    // MARK: - CIImage Execute

    /// Called every frame by the video pipeline. Follows the MapEffect pattern:
    /// position is computed fresh each frame from current x/y values,
    /// and content is only re-rendered when data actually changes.
    private func updateOverlay(size: CGSize) {
        let now = ContinuousClock.now

        // Pick up any new rendered image from the main thread
        var newImage: UIImage?
        nostrChatQueue.sync {
            if self.image != nil {
                newImage = self.image
                self.image = nil
            }
        }
        if let newImage {
            latestRenderedImage = newImage
        }

        // Kick off a new render if throttle allows and content is dirty
        let shouldRender = nostrChatQueue.sync { self.needsRedraw }
        if shouldRender, now >= nextUpdateTime {
            nextUpdateTime = now + Self.updateInterval
            triggerRender(size: size, forMetalPetal: false)
        }

        // Rebuild the positioned overlay from the latest rendered image every frame
        // (position is cheap to recompute — just a CIImage transform)
        guard let rendered = latestRenderedImage else {
            overlay = nil
            return
        }
        let (x, y) = nostrChatQueue.sync { (self.x, self.y) }
        let px = toPixels(x, size.width)
        let py = size.height - toPixels(y, size.height) - rendered.size.height
        overlay = CIImage(image: rendered)?
            .transformed(by: CGAffineTransform(translationX: px, y: py))
            .cropped(to: CGRect(
                x: px, y: py,
                width: rendered.size.width,
                height: rendered.size.height - 1
            ))
            .cropped(to: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }

    override func execute(_ image: CIImage, _: VideoEffectInfo) -> CIImage {
        updateOverlay(size: image.extent.size)
        filter.inputImage = overlay
        filter.backgroundImage = image
        return filter.outputImage ?? image
    }

    // MARK: - MetalPetal Execute

    private func updateOverlayMetalPetal(size: CGSize) -> (Double, Double) {
        let now = ContinuousClock.now

        // Pick up any new rendered image from the main thread
        var newImage: UIImage?
        nostrChatQueue.sync {
            if self.imageMetalPetal != nil {
                newImage = self.imageMetalPetal
                self.imageMetalPetal = nil
            }
        }
        if let newImage {
            if let cgImage = newImage.cgImage {
                overlayMetalPetal = MTIImage(cgImage: cgImage, isOpaque: false)
            }
        }

        // Kick off a new render if throttle allows and content is dirty
        let shouldRender = nostrChatQueue.sync { self.needsRedraw }
        if shouldRender, now >= nextUpdateTimeMetalPetal {
            nextUpdateTimeMetalPetal = now + Self.updateInterval
            triggerRender(size: size, forMetalPetal: true)
        }

        let (x, y) = nostrChatQueue.sync { (self.x, self.y) }
        return (x, y)
    }

    override func executeMetalPetal(_ image: MTIImage?, _: VideoEffectInfo) -> MTIImage? {
        guard let image else { return image }
        var (x, y) = updateOverlayMetalPetal(size: image.size)
        guard let overlayMetalPetal else { return image }
        x = toPixels(x, image.size.width) + overlayMetalPetal.size.width / 2
        y = toPixels(y, image.size.height) + overlayMetalPetal.size.height / 2
        let filter = MTIMultilayerCompositingFilter()
        filter.inputBackgroundImage = image
        filter.layers = [.init(content: overlayMetalPetal, position: .init(x: x, y: y))]
        return filter.outputImage ?? image
    }
}
