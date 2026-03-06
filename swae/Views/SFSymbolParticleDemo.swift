//
//  SFSymbolParticleDemo.swift
//  swae
//
//  Demo view showing SF Symbol particle patterns
//

import SwiftUI

struct SFSymbolParticleDemo: View {
    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var metalView: ParticleMetalView?
    @State private var currentSymbol = "bolt.fill"
    
    let symbols = [
        "bolt.fill",
        "heart.fill",
        "star.fill",
        "flame.fill",
        "sparkles",
        "waveform",
        "music.note",
        "play.fill",
        "pause.fill",
        "hand.thumbsup.fill",
        "face.smiling",
        "moon.stars.fill",
        "sun.max.fill",
        "cloud.bolt.fill",
        "tornado",
        "snowflake"
    ]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Particle system
            MetalParticleViewWithCoordinator(
                touchLocation: $touchLocation,
                isTouching: $isTouching,
                metalView: $metalView
            )
            .ignoresSafeArea()
            .onChange(of: metalView) { newView in
                if let renderer = newView?.renderer {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        renderer.transitionToSFSymbol(currentSymbol, size: 250)
                    }
                }
            }
            .onChange(of: currentSymbol) { newSymbol in
                metalView?.renderer?.transitionToSFSymbol(newSymbol, size: 250)
            }
            
            VStack {
                Text("SF Symbol Particles")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                
                Text(currentSymbol)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                // Symbol picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button(action: {
                                currentSymbol = symbol
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: symbol)
                                        .font(.title2)
                                        .foregroundColor(currentSymbol == symbol ? .cyan : .white)
                                        .frame(width: 50, height: 50)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.white.opacity(currentSymbol == symbol ? 0.2 : 0.1))
                                        )
                                    
                                    Text(symbol.split(separator: ".").first.map(String.init) ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    touchLocation = value.location
                    isTouching = true
                }
                .onEnded { _ in
                    isTouching = false
                }
        )
    }
}

#Preview {
    SFSymbolParticleDemo()
}
