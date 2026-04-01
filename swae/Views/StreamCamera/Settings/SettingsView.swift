import SwiftUI

let settingsHalfWidth = 350.0

// MARK: - Settings Row with Status
/// A settings navigation row that shows current status on the right
struct SettingsRowWithStatus: View {
    let title: String
    let icon: String
    var status: String? = nil
    var statusColor: Color = .secondary
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if let status = status {
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
            }
        }
    }
}

// MARK: - Settings Dismiss Environment Key
/// Environment key to pass the dismiss action to all child settings views
private struct SettingsDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var settingsDismiss: (() -> Void)? {
        get { self[SettingsDismissKey.self] }
        set { self[SettingsDismissKey.self] = newValue }
    }
}

// MARK: - Pop to Streams List Environment Key
/// Environment key to allow child views to pop back to streams list after stream creation
struct PopToStreamsListKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var popToStreamsList: (() -> Void)? {
        get { self[PopToStreamsListKey.self] }
        set { self[PopToStreamsListKey.self] = newValue }
    }
}

// MARK: - Settings Close Button Toolbar Modifier
/// Adds a persistent X close button to the toolbar that dismisses settings
struct SettingsCloseToolbar: ViewModifier {
    @Environment(\.settingsDismiss) private var settingsDismiss
    
    func body(content: Content) -> some View {
        content
            .toolbar {
                if let dismiss = settingsDismiss {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
    }
}

extension View {
    func settingsCloseButton() -> some View {
        modifier(SettingsCloseToolbar())
    }
}

// MARK: - Settings Root View (with NavigationStack)
/// Use this when presenting settings modally or embedding in a container.
/// It wraps SettingsView in a NavigationStack for proper iOS 26 Liquid Glass support.
/// Includes a persistent close button that stays visible at all navigation depths.
struct SettingsRootView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var appState: AppState
    var onDismiss: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            SettingsView(database: model.database)
        }
        .environment(\.settingsDismiss, onDismiss)
        .environmentObject(model)
        .environmentObject(appState)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var appState: AppState
    @ObservedObject var database: Database

    // MARK: - Stream Icon Helpers

    private var streamIcon: String {
        if !model.isStreamConfigured() { return "bolt.fill" }
        if model.stream.zapStreamCoreEnabled { return "bolt.fill" }
        switch model.stream.getProtocol() {
        case .rtmp: return "play.rectangle.fill"
        case .srt: return "bolt.horizontal.fill"
        case .rist: return "arrow.triangle.branch"
        }
    }

    private var streamIconColor: Color {
        if !model.isStreamConfigured() { return .orange }
        if model.stream.zapStreamCoreEnabled { return .yellow }
        switch model.stream.getProtocol() {
        case .rtmp: return .red
        case .srt: return .purple
        case .rist: return .orange
        }
    }

    // MARK: - Stream Status Row

    @ViewBuilder
    private var streamStatusRow: some View {
        if model.isStreamConfigured() {
            if model.isLive {
                HStack(spacing: 8) {
                    Image(systemName: streamIcon)
                        .foregroundColor(streamIconColor)
                    Text(model.stream.name)
                        .lineLimit(1)
                    Spacer()
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)
                    Text(model.streamUptime.uptime)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            } else {
                NavigationLink {
                    StreamSettingsView(database: model.database, stream: model.stream)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: streamIcon)
                            .foregroundColor(streamIconColor)
                        Text(model.stream.name)
                            .lineLimit(1)
                        Spacer()
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
        } else {
            NavigationLink {
                StreamSetupView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                    Text("Set Up Stream")
                        .foregroundColor(.orange)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Form {
            if model.isLive {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Settings that would stop the stream are disabled when live.")
                    }
                }
            }

            Section {
                StreamStatusHeroCard()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                NavigationLink {
                    StreamsSettingsView(
                        createStreamWizard: model.createStreamWizard, database: database)
                } label: {
                    SettingsRowWithStatus(
                        title: "Streams",
                        icon: "dot.radiowaves.left.and.right",
                        status: "\(database.streams.count) stream\(database.streams.count == 1 ? "" : "s")"
                    )
                }
                NavigationLink {
                    ScenesSettingsView()
                } label: {
                    SettingsRowWithStatus(
                        title: "Scenes",
                        icon: "photo.on.rectangle",
                        status: "\(model.enabledScenes.count) scene\(model.enabledScenes.count == 1 ? "" : "s")"
                    )
                }
                NavigationLink {
                    CameraSettingsView(database: database, color: database.color)
                } label: {
                    SettingsRowWithStatus(
                        title: "Camera",
                        icon: "camera"
                    )
                }
                NavigationLink {
                    DisplaySettingsView(database: database)
                } label: {
                    SettingsRowWithStatus(
                        title: "Display",
                        icon: "rectangle.on.rectangle"
                    )
                }
                NavigationLink {
                    AudioSettingsView(database: database, mic: model.mic)
                } label: {
                    SettingsRowWithStatus(
                        title: "Audio",
                        icon: "waveform"
                    )
                }
                NavigationLink {
                    LocationSettingsView(
                        database: model.database, location: database.location, stream: $model.stream
                    )
                } label: {
                    SettingsRowWithStatus(
                        title: "Location",
                        icon: "location",
                        status: database.location.enabled ? "On" : "Off"
                    )
                }
            } header: {
                Text("Stream")
            }
            Section {
                NavigationLink {
                    DjiDevicesSettingsView(djiDevices: database.djiDevices)
                } label: {
                    Label("DJI devices", systemImage: "appletvremote.gen1")
                }
                NavigationLink {
                    GoProSettingsView()
                } label: {
                    Label("GoPro", systemImage: "appletvremote.gen1")
                }
                NavigationLink {
                    MetaGlassesSettingsView()
                } label: {
                    Label("Meta Glasses", systemImage: "eyeglasses")
                }
                NavigationLink {
                    IngestsSettingsView(database: database)
                } label: {
                    Label("Ingests", systemImage: "server.rack")
                }
            } header: {
                Text("Devices")
            }
            Section {
                NavigationLink {
                    RecordingsSettingsView(model: model)
                } label: {
                    Label("Recordings", systemImage: "photo.on.rectangle.angled")
                }
                if database.showAllSettings {
                    NavigationLink {
                        StreamingHistorySettingsView(model: model)
                    } label: {
                        Label("Streaming history", systemImage: "text.book.closed")
                    }
                }
            } header: {
                Text("Library")
            }
            if database.showAllSettings {
                Section {
                    NavigationLink {
                        SelfieStickSettingsView(
                            database: database, selfieStick: database.selfieStick)
                    } label: {
                        Label("Selfie stick", systemImage: "line.diagonal")
                    }
                    NavigationLink {
                        GameControllersSettingsView(database: database)
                    } label: {
                        Label("Game controllers", systemImage: "gamecontroller")
                    }
                    if #available(iOS 17.0, *) {
                        NavigationLink {
                            KeyboardSettingsView(keyboard: database.keyboard)
                        } label: {
                            Label("Keyboard", systemImage: "keyboard")
                        }
                    }
                    NavigationLink {
                        RemoteControlSettingsView(
                            database: database,
                            status: model.statusOther,
                            assistant: database.remoteControl.assistant,
                            stream: $model.stream)
                    } label: {
                        Label("Remote control", systemImage: "appletvremote.gen1")
                    }
                }
                Section {
                    NavigationLink {
                        CatPrintersSettingsView(catPrinters: model.database.catPrinters)
                    } label: {
                        Label("Cat printers", systemImage: "pawprint")
                    }
                    NavigationLink {
                        TeslaSettingsView(tesla: model.tesla)
                    } label: {
                        Label("Tesla", systemImage: "car.side")
                    }
                    NavigationLink {
                        CyclingPowerDevicesSettingsView(
                            cyclingPowerDevices: model.database.cyclingPowerDevices)
                    } label: {
                        Label("Cycling power devices", systemImage: "bicycle")
                    }
                    NavigationLink {
                        HeartRateDevicesSettingsView(
                            heartRateDevices: model.database.heartRateDevices)
                    } label: {
                        Label("Heart rate devices", systemImage: "heart")
                    }
                    NavigationLink {
                        PhoneCoolerDevicesSettingsView(
                            phoneCoolerDevices: database.phoneCoolerDevices)
                    } label: {
                        Label("Black Shark coolers", systemImage: "fan")
                    }
                }
            }
            if database.showAllSettings, isPhone() {
                Section {
                    NavigationLink {
                        WatchSettingsView(watch: database.watch)
                    } label: {
                        Label("Apple Watch", systemImage: "applewatch")
                    }
                }
            }
            Section {
                if database.showAllSettings {
                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    NavigationLink {
                        DebugSettingsView(debug: database.debug)
                    } label: {
                        Label("Debug", systemImage: "ladybug")
                    }
                }
            }
            if database.showAllSettings {
                Section {
                    NavigationLink {
                        ImportExportSettingsView()
                    } label: {
                        Label("Import and export settings", systemImage: "gearshape")
                    }
                    NavigationLink {
                        DeepLinkCreatorSettingsView(deepLinkCreator: model.database.deepLinkCreator)
                    } label: {
                        Label("Deep link creator", systemImage: "link.badge.plus")
                    }
                }
            }
            Section {
                ResetSettingsView()
            }
        }
        .navigationTitle("Settings")
        .settingsCloseButton()
    }
}
