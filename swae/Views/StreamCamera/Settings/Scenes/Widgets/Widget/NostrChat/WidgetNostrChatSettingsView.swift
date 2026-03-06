import SwiftUI

struct WidgetNostrChatSettingsView: View {
    @EnvironmentObject var model: Model
    let widget: SettingsWidget
    @ObservedObject var nostrChat: SettingsWidgetNostrChat

    @State private var backgroundColor: Color
    @State private var messageColor: Color
    @State private var usernameColor: Color
    @State private var zapColor: Color
    @State private var perMessageBackgroundColor: Color
    @State private var timestampColor: Color
    @State private var textShadowColor: Color

    init(widget: SettingsWidget, nostrChat: SettingsWidgetNostrChat) {
        self.widget = widget
        self.nostrChat = nostrChat
        _backgroundColor = State(initialValue: nostrChat.backgroundColor.color())
        _messageColor = State(initialValue: nostrChat.messageColor.color())
        _usernameColor = State(initialValue: nostrChat.usernameColor.color())
        _zapColor = State(initialValue: nostrChat.zapColor.color())
        _perMessageBackgroundColor = State(
            initialValue: nostrChat.perMessageBackgroundColor.color())
        _timestampColor = State(initialValue: nostrChat.timestampColor.color())
        _textShadowColor = State(initialValue: nostrChat.textShadowColor.color())
    }

    private func updateEffect() {
        if let effect = model.getNostrChatEffect(id: widget.id) {
            effect.updateSettings(nostrChat)
        }
    }

    var body: some View {
        // Appearance
        Section {
            ColorPicker("Background", selection: $backgroundColor, supportsOpacity: true)
                .onChange(of: backgroundColor) { _ in
                    if let rgb = backgroundColor.toRgb() {
                        nostrChat.backgroundColor = rgb
                        updateEffect()
                    }
                }
            HStack {
                Text("Corner radius")
                Slider(
                    value: $nostrChat.cornerRadius,
                    in: 0...30,
                    step: 1
                )
                .onChange(of: nostrChat.cornerRadius) { _ in
                    updateEffect()
                }
                Text("\(Int(nostrChat.cornerRadius))")
                    .frame(width: 30)
            }
            Toggle("Text shadow", isOn: $nostrChat.textShadow)
                .onChange(of: nostrChat.textShadow) { _ in
                    updateEffect()
                }
            if nostrChat.textShadow {
                ColorPicker("Shadow color", selection: $textShadowColor, supportsOpacity: true)
                    .onChange(of: textShadowColor) { _ in
                        if let rgb = textShadowColor.toRgb() {
                            nostrChat.textShadowColor = rgb
                            updateEffect()
                        }
                    }
                HStack {
                    Text("Shadow radius")
                    Slider(
                        value: $nostrChat.textShadowRadius,
                        in: 0...10,
                        step: 0.5
                    )
                    .onChange(of: nostrChat.textShadowRadius) { _ in
                        updateEffect()
                    }
                    Text(String(format: "%.1f", nostrChat.textShadowRadius))
                        .frame(width: 35)
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Set background opacity to 0 for a fully transparent background.")
        }

        // Messages
        Section {
            ColorPicker("Text color", selection: $messageColor, supportsOpacity: false)
                .onChange(of: messageColor) { _ in
                    if let rgb = messageColor.toRgb() {
                        nostrChat.messageColor = rgb
                        updateEffect()
                    }
                }
            HStack {
                Text("Font size")
                Slider(
                    value: Binding(
                        get: { Float(nostrChat.fontSize) },
                        set: { nostrChat.fontSize = Int($0) }
                    ),
                    in: 10...60,
                    step: 1
                )
                .onChange(of: nostrChat.fontSize) { _ in
                    updateEffect()
                }
                Text("\(nostrChat.fontSize)")
                    .frame(width: 30)
            }
            Picker("Font design", selection: $nostrChat.fontDesign) {
                ForEach(SettingsFontDesign.allCases, id: \.self) {
                    Text($0.toString()).tag($0)
                }
            }
            .onChange(of: nostrChat.fontDesign) { _ in
                updateEffect()
            }
            Picker("Font weight", selection: $nostrChat.fontWeight) {
                ForEach(SettingsFontWeight.allCases, id: \.self) {
                    Text($0.toString()).tag($0)
                }
            }
            .onChange(of: nostrChat.fontWeight) { _ in
                updateEffect()
            }
            HStack {
                Text("Max messages")
                Slider(
                    value: Binding(
                        get: { Float(nostrChat.maxMessages) },
                        set: { nostrChat.maxMessages = Int($0) }
                    ),
                    in: 5...100,
                    step: 1
                )
                .onChange(of: nostrChat.maxMessages) { _ in
                    updateEffect()
                }
                Text("\(nostrChat.maxMessages)")
                    .frame(width: 35)
            }
            HStack {
                Text("Spacing")
                Slider(
                    value: $nostrChat.messageSpacing,
                    in: 0...20,
                    step: 1
                )
                .onChange(of: nostrChat.messageSpacing) { _ in
                    updateEffect()
                }
                Text("\(Int(nostrChat.messageSpacing))")
                    .frame(width: 30)
            }
            Picker("Scroll direction", selection: $nostrChat.scrollDirection) {
                ForEach(NostrChatScrollDirection.allCases, id: \.self) {
                    Text($0.toString()).tag($0)
                }
            }
            .onChange(of: nostrChat.scrollDirection) { _ in
                updateEffect()
            }
            Toggle("Show timestamps", isOn: $nostrChat.showTimestamps)
                .onChange(of: nostrChat.showTimestamps) { _ in
                    updateEffect()
                }
            if nostrChat.showTimestamps {
                ColorPicker("Timestamp color", selection: $timestampColor, supportsOpacity: false)
                    .onChange(of: timestampColor) { _ in
                        if let rgb = timestampColor.toRgb() {
                            nostrChat.timestampColor = rgb
                            updateEffect()
                        }
                    }
            }
        } header: {
            Text("Messages")
        }

        // Usernames
        Section {
            Picker("Style", selection: $nostrChat.usernameStyle) {
                ForEach(NostrChatUsernameStyle.allCases, id: \.self) {
                    Text($0.toString()).tag($0)
                }
            }
            .onChange(of: nostrChat.usernameStyle) { _ in
                updateEffect()
            }
            if nostrChat.usernameStyle == .singleColor {
                ColorPicker("Username color", selection: $usernameColor, supportsOpacity: false)
                    .onChange(of: usernameColor) { _ in
                        if let rgb = usernameColor.toRgb() {
                            nostrChat.usernameColor = rgb
                            updateEffect()
                        }
                    }
            }
            Picker("Username weight", selection: $nostrChat.usernameFontWeight) {
                ForEach(SettingsFontWeight.allCases, id: \.self) {
                    Text($0.toString()).tag($0)
                }
            }
            .onChange(of: nostrChat.usernameFontWeight) { _ in
                updateEffect()
            }
            Toggle("Show colon", isOn: $nostrChat.showColon)
                .onChange(of: nostrChat.showColon) { _ in
                    updateEffect()
                }
        } header: {
            Text("Usernames")
        }

        // Zaps
        Section {
            Toggle("Show zaps", isOn: $nostrChat.showZaps)
                .onChange(of: nostrChat.showZaps) { _ in
                    updateEffect()
                }
            if nostrChat.showZaps {
                ColorPicker("Zap color", selection: $zapColor, supportsOpacity: false)
                    .onChange(of: zapColor) { _ in
                        if let rgb = zapColor.toRgb() {
                            nostrChat.zapColor = rgb
                            updateEffect()
                        }
                    }
                Toggle("Show amount", isOn: $nostrChat.showZapAmount)
                    .onChange(of: nostrChat.showZapAmount) { _ in
                        updateEffect()
                    }
                Toggle("Show message", isOn: $nostrChat.showZapMessage)
                    .onChange(of: nostrChat.showZapMessage) { _ in
                        updateEffect()
                    }
            }
        } header: {
            Text("Zaps")
        }

        // Per-message bubbles
        Section {
            Toggle("Message bubbles", isOn: $nostrChat.perMessageBackground)
                .onChange(of: nostrChat.perMessageBackground) { _ in
                    updateEffect()
                }
            if nostrChat.perMessageBackground {
                ColorPicker("Bubble color", selection: $perMessageBackgroundColor, supportsOpacity: true)
                    .onChange(of: perMessageBackgroundColor) { _ in
                        if let rgb = perMessageBackgroundColor.toRgb() {
                            nostrChat.perMessageBackgroundColor = rgb
                            updateEffect()
                        }
                    }
                HStack {
                    Text("Padding")
                    Slider(
                        value: $nostrChat.messagePadding,
                        in: 0...20,
                        step: 1
                    )
                    .onChange(of: nostrChat.messagePadding) { _ in
                        updateEffect()
                    }
                    Text("\(Int(nostrChat.messagePadding))")
                        .frame(width: 30)
                }
                HStack {
                    Text("Corner radius")
                    Slider(
                        value: $nostrChat.perMessageCornerRadius,
                        in: 0...20,
                        step: 1
                    )
                    .onChange(of: nostrChat.perMessageCornerRadius) { _ in
                        updateEffect()
                    }
                    Text("\(Int(nostrChat.perMessageCornerRadius))")
                        .frame(width: 30)
                }
            }
        } header: {
            Text("Message Bubbles")
        }

        WidgetEffectsView(widget: widget)
    }
}
