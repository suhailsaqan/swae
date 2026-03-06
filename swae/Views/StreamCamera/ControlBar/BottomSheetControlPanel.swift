import Foundation
import SwiftUI

// MARK: - Bottom Sheet Control Panel (Minimal Fixed Bar)
struct BottomSheetControlPanel: View {
    @EnvironmentObject var model: Model

    var body: some View {
        HStack(spacing: 0) {
            // Go Live/End Stream Button (prominent)
            StreamButton()
                .padding(.horizontal, 8)
            
            // Record Button
            ControlBarButton(
                icon: model.isRecording ? "stop.circle.fill" : "record.circle",
                label: model.isRecording ? "Stop" : "Record",
                color: model.isRecording ? .red : .white
            ) {
                if model.isRecording {
                    model.stopRecording()
                } else {
                    model.startRecording()
                }
            }
            
            // Mute Button
            ControlBarButton(
                icon: model.isMuteOn ? "mic.slash.fill" : "mic.fill",
                label: model.isMuteOn ? "Muted" : "Mic",
                color: model.isMuteOn ? .red : .white
            ) {
                model.toggleMute()
            }
            
            // Flip Camera Button
            ControlBarButton(
                icon: "camera.rotate.fill",
                label: "Flip",
                color: .white
            ) {
                model.toggleCamera()
            }
            
            // Settings Button (with upward hint)
            SettingsBarButton()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom)  // Add safe area padding to content
        .background(
            Color.black.opacity(0.7)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(.all, edges: .bottom)  // Background extends into safe area
        )
    }
}

// MARK: - Control Bar Button
struct ControlBarButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                    .frame(height: 28)
                
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Settings Bar Button (with upward hint)
struct SettingsBarButton: View {
    @EnvironmentObject var model: Model
    
    var body: some View {
        Button {
            // Trigger settings to open via notification
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenCameraSettings"),
                object: nil
            )
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(height: 24)
                
                Text("Settings")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}



// MARK: - Model Extension for Bottom Sheet
extension Model {
    func handleQuickButtonAction(state: ButtonState) {
        // Handle quick button actions based on button type
        switch state.button.type {
        case .torch:
            toggleTorch()
            updateQuickButtonStates()
        case .mute:
            toggleMute()
            updateQuickButtonStates()
        case .record:
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        case .widgets:
            toggleShowingPanel(type: .widgets, panel: .widgets)
        case .luts:
            toggleShowingPanel(type: .luts, panel: .luts)
            updateLutsButtonState()
        case .chat:
            toggleShowingPanel(type: .chat, panel: .chat)
        case .mic:
            toggleShowingPanel(type: .mic, panel: .mic)
        case .bitrate:
            toggleShowingPanel(type: .bitrate, panel: .bitrate)
        case .recordings:
            toggleShowingPanel(type: .recordings, panel: .recordings)
        case .djiDevices:
            toggleShowingPanel(type: .djiDevices, panel: .djiDevices)
        case .goPro:
            toggleShowingPanel(type: .goPro, panel: .goPro)
        case .connectionPriorities:
            toggleShowingPanel(type: .connectionPriorities, panel: .connectionPriorities)
        case .autoSceneSwitcher:
            toggleShowingPanel(type: .autoSceneSwitcher, panel: .autoSceneSwitcher)
        case .obs:
            toggleShowingPanel(type: .obs, panel: .obs)
        case .blackScreen:
            toggleStealthMode()
            updateQuickButtonStates()
        case .lockScreen:
            toggleLockScreen()
        case .image:
            streamOverlay.showingCamera.toggle()
            updateImageButtonState()
        case .movie:
            // Handle movie action
            break
        case .fourThree:
            // Handle aspect ratio
            break
        case .localOverlays:
            setGlobalButtonState(type: .localOverlays, isOn: state.button.isOn)
            updateQuickButtonStates()
            toggleLocalOverlays()
        case .browser:
            setGlobalButtonState(type: .browser, isOn: state.button.isOn)
            updateQuickButtonStates()
            toggleBrowser()
        case .cameraPreview:
            updateQuickButtonStates()
            reattachCamera()
        case .face:
            showFace.toggle()
            updateFaceFilterButtonState()
        case .poll:
            togglePoll()
        case .snapshot:
            takeSnapshot()
        case .interactiveChat:
            setGlobalButtonState(type: .interactiveChat, isOn: state.button.isOn)
            updateQuickButtonStates()
            chat.interactiveChat = state.button.isOn
            if !state.button.isOn {
                disableInteractiveChat()
            }
        case .portrait:
            setDisplayPortrait(portrait: !database.portrait)
            reattachCamera()
            sceneSettingsPanelSceneId += 1
        case .replay:
            streamOverlay.showingReplay.toggle()
            setGlobalButtonState(type: .replay, isOn: state.button.isOn)
            updateQuickButtonStates()
        case .remote:
            showingRemoteControl.toggle()
            setGlobalButtonState(type: .remote, isOn: showingRemoteControl)
            updateQuickButtonStates()
        case .draw:
            toggleDrawOnStream()
        case .zapPlasma:
            stream.zapPlasmaEffectEnabled.toggle()
            setGlobalButtonState(type: .zapPlasma, isOn: stream.zapPlasmaEffectEnabled)
            updateZapPlasmaEffectSettings()
            updateQuickButtonStates()
        default:
            break
        }
    }

    func toggleCamera() {
        // Toggle between front and back camera
        if cameraPosition == .front {
            cameraPosition = .back
        } else {
            cameraPosition = .front
        }
        // Trigger camera reattachment
        reattachCamera()
    }
}



#Preview {
    BottomSheetControlPanel()
        .environmentObject(Model())
}
