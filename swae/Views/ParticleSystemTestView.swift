//
//  ParticleSystemTestView.swift
//  swae
//
//  Comprehensive test view for the new particle system
//

import SwiftUI

struct ParticleSystemTestView: View {
    @State private var selectedTest = 0
    
    let tests = [
        "Basic Demo",
        "Pattern Gallery",
        "Voice Activity",
        "Zap Effect",
        "Onboarding"
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Section("Select Test") {
                    Picker("Test", selection: $selectedTest) {
                        ForEach(Array(tests.enumerated()), id: \.offset) { index, test in
                            Text(test).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Current Test") {
                    NavigationLink {
                        currentTestView
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.blue)
                            Text("Run \(tests[selectedTest])")
                        }
                    }
                }
                
                Section("Quick Tests") {
                    NavigationLink("Basic Demo") {
                        PhysicsParticleDemo()
                    }
                    
                    NavigationLink("Pattern Gallery") {
                        ParticlePatternGallery()
                    }
                    
                    NavigationLink("Voice Activity") {
                        VoiceActivityParticleViewComplete()
                    }
                    
                    NavigationLink("Zap Effect") {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            
                            VStack(spacing: 40) {
                                Text("Zap Particle Effects")
                                    .font(.title)
                                    .foregroundColor(.white)
                                
                                SimpleZapParticleView(size: 150, intensity: 1.0)
                                
                                ZapParticleEffectView(
                                    size: 200,
                                    autoPlay: true,
                                    intensity: 1.2
                                )
                            }
                        }
                    }
                }
                
                Section("Documentation") {
                    Link("Quick Start Guide", destination: URL(string: "file://Metal/QUICKSTART.md")!)
                    Link("Integration Guide", destination: URL(string: "file://Metal/INTEGRATION.md")!)
                    Link("Migration Guide", destination: URL(string: "file://Metal/MIGRATION.md")!)
                }
                
                Section("System Info") {
                    HStack {
                        Text("Metal Support")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Text("Particle Count")
                        Spacer()
                        Text("2000")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Target FPS")
                        Spacer()
                        Text("60")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Particle System Tests")
        }
    }
    
    @ViewBuilder
    var currentTestView: some View {
        switch selectedTest {
        case 0:
            PhysicsParticleDemo()
        case 1:
            ParticlePatternGallery()
        case 2:
            VoiceActivityParticleViewComplete()
        case 3:
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 40) {
                    SimpleZapParticleView(size: 150, intensity: 1.0)
                    ZapParticleEffectView(size: 200, autoPlay: true, intensity: 1.2)
                }
            }
        case 4:
            Text("Onboarding test - use OnboardingViewWithParticles in your app")
                .padding()
        default:
            Text("Unknown test")
        }
    }
}

#Preview {
    ParticleSystemTestView()
}
