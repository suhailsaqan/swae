//
//  DoubleTapSeek.swift
//  gibbe
//
//  Created by Suhail Saqan on 1/25/25.
//

import SwiftUI

struct DoubleTapSeek: View {
    var isForward: Bool = false
    var onTap: () -> ()
   
    @State private var isTapped: Bool = false
    @State private var showArrows: [Bool] = [false, false, false]
    var body: some View {
            Rectangle()
            .foregroundColor(.clear)
            .overlay {
                Circle()
                    .fill(.black.opacity(0.4))
                    .scaleEffect(2, anchor: isForward ? .leading : .trailing)
            }
            .clipped()
            .opacity(isTapped ? 1 : 0)
            .overlay {
                VStack(spacing: 10) {
                    HStack(spacing: 0) {
                        ForEach((0...2).reversed(), id: \.self) { index in
                            Image(systemName: "arrowtriangle.backward.fill")
                                .opacity(showArrows[index] ? 1 : 0.2)
                        }
                    }
                    .font(.title)
                    .rotationEffect(.init(degrees: isForward ? 180 : 0))
                    
                    Text("15 Seconds")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .opacity(isTapped ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isTapped = true
                    showArrows[0] = true
                }
                
                withAnimation(.easeInOut(duration: 0.2).delay(0.2)) {
                    showArrows[0] = false
                    showArrows[1] = true
                }
                
                withAnimation(.easeInOut(duration: 0.2).delay(0.35)) {
                    showArrows[1] = false
                    showArrows[2] = true
                }
                
                withAnimation(.easeInOut(duration: 0.2).delay(0.5)) {
                    showArrows[2] = false
                    isTapped = false
                }
                
                onTap()
            }
    }
}
