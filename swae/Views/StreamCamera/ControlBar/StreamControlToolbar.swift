//
//  StreamControlToolbar.swift
//  swae
//
//  New bottom toolbar for camera view with liquid glass controls
//  Layout: Settings | Mic | Flip | GO LIVE | Torch | More
//

import MetalKit
import SwiftUI
import UIKit

// MARK: - StreamControlToolbar

struct StreamControlToolbar: View {
    @EnvironmentObject var model: Model
    @State private var isMoreExpanded: Bool = false
    
    // Control sizes
    private let smallOrbSize: CGFloat = 44
    private let goLiveSize: CGFloat = 100
    private let settingsButtonSize: CGSize = CGSize(width: 44, height: 44)
    private let moreButtonSize: CGSize = CGSize(width: 56, height: 56)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Dimming overlay when More is expanded
            if isMoreExpanded {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isMoreExpanded = false
                        }
                    }
            }
            
            // Main toolbar
            HStack(alignment: .center, spacing: 12) {
                // Settings button (far left)
                SettingsOrbButton {
                    model.toggleShowingPanel(type: nil, panel: .settings)
                }
                .frame(width: smallOrbSize, height: smallOrbSize)
                
                // Mic toggle
                ToolbarMiniOrb(
                    type: .mic,
                    isOn: !model.isMuteOn
                ) {
                    model.toggleMute()
                }
                .frame(width: smallOrbSize, height: smallOrbSize)
                
                // Flip camera
                ToolbarMiniOrb(
                    type: .flip,
                    isOn: false
                ) {
                    model.toggleCamera()
                }
                .frame(width: smallOrbSize, height: smallOrbSize)
                
                Spacer()
                
                // Go Live (center hero)
                GoLiveOrb()
                    .frame(width: goLiveSize, height: goLiveSize)
                
                Spacer()
                
                // Torch toggle
                ToolbarMiniOrb(
                    type: .torch,
                    isOn: model.streamOverlay.isTorchOn
                ) {
                    model.toggleTorch()
                }
                .frame(width: smallOrbSize, height: smallOrbSize)
                
                // More button placeholder - use MorphingGoLiveToolbar instead
                Color.clear
                    .frame(width: moreButtonSize.width, height: moreButtonSize.height)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .safeAreaPadding(.bottom)
        }
    }
}

// MARK: - Settings Orb Button

private struct SettingsOrbButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                MiniOrbSwiftUIView(config: .off)
                
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(OrbPressStyle())
    }
}

// MARK: - Toolbar Mini Orb

private struct ToolbarMiniOrb: View {
    let type: ToggleOrbType
    let isOn: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
            action()
        }) {
            ZStack {
                MiniOrbSwiftUIView(config: type.config(isOn: isOn))
                
                Image(systemName: type.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(isOn ? 1.0 : 0.7))
            }
        }
        .buttonStyle(OrbPressStyle())
        .accessibilityLabel(type.title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint("Double tap to toggle")
    }
}

// MARK: - Orb Press Style

private struct OrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Morphing More Button Wrapper
// NOTE: This wrapper is disabled because MorphingMoreButton was never implemented.
// Use MorphingGoLiveToolbar instead which implements the morphing Go Live orb.

/*
private struct MorphingMoreButtonWrapper: UIViewRepresentable {
    @Binding var isExpanded: Bool
    let model: Model
    
    func makeUIView(context: Context) -> MorphingMoreButton {
        let view = MorphingMoreButton()
        
        // Configure control items
        let items = createControlItems(model: model)
        view.configure(items: items)
        
        // Set expanded size and offset
        view.setExpandedSize(
            CGSize(width: 200, height: 180),
            offset: CGPoint(x: -72, y: -120)  // Offset left and up from button position
        )
        
        // Handle expansion state changes
        view.onExpandedChanged = { expanded in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded = expanded
                }
            }
        }
        
        // Handle control toggles
        view.onControlToggled = { type in
            handleControlToggle(type: type, model: model)
        }
        
        // Trigger birth animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            view.triggerBirthAnimation()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: MorphingMoreButton, context: Context) {
        // Update control items with current state
        let items = createControlItems(model: model)
        uiView.configure(items: items)
        uiView.updateControlStates()
        
        // Sync expansion state from SwiftUI
        if isExpanded && !uiView.isExpanded {
            uiView.expand()
        } else if !isExpanded && uiView.isExpanded {
            uiView.collapse()
        }
    }
    
    private func createControlItems(model: Model) -> [MoreControlItem] {
        return [
            MoreControlItem(
                type: .widget,
                action: { model.toggleShowingPanel(type: nil, panel: .widgets) },
                isOn: { model.showingPanel == .widgets }
            ),
            MoreControlItem(
                type: .lut,
                action: { model.toggleShowingPanel(type: nil, panel: .luts) },
                isOn: { model.database.color.lutEnabled }
            ),
            MoreControlItem(
                type: .mute,
                action: { model.toggleMute() },
                isOn: { model.isMuteOn }
            ),
            MoreControlItem(
                type: .scene,
                action: { model.toggleShowingPanel(type: nil, panel: .sceneSettings) },
                isOn: { model.showingPanel == .sceneSettings }
            ),
            MoreControlItem(
                type: .obs,
                action: { model.toggleShowingPanel(type: nil, panel: .obs) },
                isOn: { model.isObsConnected() }
            ),
            MoreControlItem(
                type: .streams,
                action: { model.toggleShowingPanel(type: nil, panel: .streamSwitcher) },
                isOn: { model.showingPanel == .streamSwitcher }
            )
        ]
    }
    
    private func handleControlToggle(type: ToggleOrbType, model: Model) {
        switch type {
        case .widget:
            model.toggleShowingPanel(type: nil, panel: .widgets)
        case .lut:
            model.toggleShowingPanel(type: nil, panel: .luts)
        case .mute:
            model.toggleMute()
        case .scene:
            model.toggleShowingPanel(type: nil, panel: .sceneSettings)
        case .obs:
            model.toggleShowingPanel(type: nil, panel: .obs)
        case .streams:
            model.toggleShowingPanel(type: nil, panel: .streamSwitcher)
        default:
            break
        }
    }
}
*/

// MARK: - Preview

#if DEBUG
struct StreamControlToolbar_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                Spacer()
                StreamControlToolbar()
                    .environmentObject(Model())
            }
        }
    }
}
#endif
