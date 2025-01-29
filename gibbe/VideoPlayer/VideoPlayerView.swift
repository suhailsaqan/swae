//
//  VideoPlayerView.swift
//  gibbe
//
//  Created by Suhail Saqan on 1/25/25.
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    var size: CGSize
    var safeArea: EdgeInsets
    let url: URL
    @State private var player: AVPlayer?

    init(size: CGSize, safeArea: EdgeInsets, url: URL) {
        self.size = size
        self.safeArea = safeArea
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }
    
    @State private var showPlayerControls: Bool = false
    @State private var isPlaying: Bool = false
    @State private var timeoutTask: DispatchWorkItem?
    @State private var isFinishedPlaying: Bool = false
    /// Video Seeker Properties
    @GestureState private var isDragging: Bool = false
    @State private var isSeeking: Bool = false
    @State private var progress: CGFloat = 0
    @State private var lastDraggedProgress: CGFloat = 0
    @State private var isObserverAdded: Bool = false
    @State private var thumbnailFrames: [UIImage] = []
    @State private var draggingImage: UIImage?
    @State private var playerStatusObserver: NSKeyValueObservation?
    /// Rotation Properties
    @State private var isRotated: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
//            let videoPlayerSize: CGSize = .init(width: isRotated ? size.height: size.width, height: isRotated ? size.width : (size.height / 3.5))
            let videoPlayerSize: CGSize = .init(width: isRotated ? size.height: size.width, height: isRotated ? size.width : (size.height))
            
            ZStack {
                if let player {
                    CustomVideoPlayer(player: player)
                        .overlay {
                            Rectangle()
                                .fill(.black.opacity(0.4))
                                .opacity(showPlayerControls || isDragging ? 1 : 0)
                                .animation(.easeInOut(duration: 0.35), value: isDragging)
                                .overlay {
                                    PlayBackControls()
                                }
                        }
                        .overlay {
                            HStack(spacing: 60) {
                                DoubleTapSeek {
                                    let seconds = player.currentTime().seconds - 15
                                    player.seek(to: .init(seconds: seconds, preferredTimescale: 600))
                                }
                                
                                DoubleTapSeek(isForward: true) {
                                    let seconds = player.currentTime().seconds + 15
                                    player.seek(to: .init(seconds: seconds, preferredTimescale: 600))
                                }
                            }
                            
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.20)) {
                                showPlayerControls.toggle()
                            }
                            
                            if isPlaying {
                                timeoutControls()
                            }
                        }
                        .overlay(alignment: .bottomLeading) {
                            SeekerThumbnailView(videoPlayerSize)
                                .offset(y: isRotated ? -85: -60)
                        }
                        .overlay(alignment: .bottom) {
                            VideoSeekerView(videoPlayerSize)
                                .offset(y: isRotated ? -15: 0)
                        }
                }
            }
            .background {
                Rectangle()
                    .fill(.black)
                    .padding(.trailing, isRotated ? -safeArea.bottom : 0)
            }
            .gesture(
                DragGesture()
                    .onEnded({ value in
                        if -value.translation.height > 100 {
                            /// Rotate Player
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRotated = true
                            }
                        } else {
                            /// Go to Normal
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRotated = false
                            }
                        }
                    })
            )
            .frame(width: videoPlayerSize.width, height: videoPlayerSize.height)
//            .frame(width: size.width, height: size.height / 3.5, alignment: .bottomLeading) replacement ^
            .frame(width: size.width, height: size.height, alignment: .bottomLeading)
            .offset(y: isRotated ? -((size.width / 2) + safeArea.bottom) : 0)
            .rotationEffect(.init(degrees: isRotated ? 90 : 0), anchor: .topLeading)
            .zIndex(10000)
        }
        .padding(.top, safeArea.top)
        .onAppear {
            guard !isObserverAdded else { return }
                    
            player?.addPeriodicTimeObserver(forInterval: .init(seconds: 1, preferredTimescale: 600), queue: .main, using: { time in
                
                if let currentPlayerItem = player?.currentItem {
                    let totalDuration = currentPlayerItem.duration.seconds
                    guard let currentDuration = player?.currentTime().seconds else { return }
                    
                    let calculatedProgress = currentDuration / totalDuration
                    
                    if !isSeeking {
                        progress = calculatedProgress
                        lastDraggedProgress = progress
                    }
                    
                    if calculatedProgress == 1 {
                        isFinishedPlaying = true
                        isPlaying = false
                    }
                }
            })
            
            isObserverAdded = true
            
            playerStatusObserver = player?.observe(\.status, options: .new, changeHandler: {
                player, _ in
                if player.status == .readyToPlay {
                    generateThumbnailFrames()
                }
            })
            
            player?.play()
            togglePlayWithAnimation($isPlaying)
            if let timeoutTask {
                timeoutTask.cancel()
            }
        }
        .onDisappear {
            playerStatusObserver?.invalidate()
            
            player?.pause()
            togglePlayWithAnimation($isPlaying)
            timeoutControls()
        }
    }
    
    @ViewBuilder
    func SeekerThumbnailView(_ videoSize: CGSize) -> some View {
        let thumbSize: CGSize = .init(width: 175, height: 100)
        ZStack {
            if let draggingImage {
                Image(uiImage: draggingImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(alignment: .bottom) {
                        if let currentItem = player?.currentItem {
                            Text(CMTime(seconds: progress * currentItem.duration.seconds, preferredTimescale: 600).toTimeString())
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .offset(y: 25)
                        }
                        
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white, lineWidth: 2)
                    }
            } else {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.black)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white, lineWidth: 2)
                    }
            }
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .opacity(isDragging ? 1 : 0)
        .offset(x: progress * (videoSize.width - thumbSize.width - 20))
        .offset(x: 10)
    }
    
    /// Video Seeker View
    @ViewBuilder
    func VideoSeekerView(_ videoSize: CGSize) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.gray)
            
            Rectangle()
                .fill(.red)
                .frame(width: max(videoSize.width * (progress.isFinite ? progress : 0), 0))
        }
        .frame(height: 3)
        .overlay(alignment: .leading) {
            Circle()
                .fill(.red)
                .frame(width: 15, height: 15)
                /// Showing Drag Knob Only When Dragging
                .scaleEffect(showPlayerControls || isDragging ? 1 : 0.001, anchor: progress * videoSize.width > 15 ? .trailing : .leading)
                /// For more Dragging Space
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
                /// Moving Along Side With Gesture Progress
                .offset(x: videoSize.width * progress)
                .gesture(DragGesture()
                    .updating($isDragging, body: { _, out, _ in
                        out = true
                    })
                        .onChanged({value in
                            if let timeoutTask {
                                timeoutTask.cancel()
                            }
                            
                            let translationX: CGFloat = value.translation.width
                            let calculatedProgress = (translationX / videoSize.width) + lastDraggedProgress
                            
                            progress = max(min(calculatedProgress, 1), 0)
                            isSeeking = true
                            
                            let dragIndex = Int(progress / 0.01)
                            if thumbnailFrames.indices.contains(dragIndex) {
                                draggingImage = thumbnailFrames[dragIndex]
                            }
                        })
                        .onEnded({value in
                            /// Storing Last Known Progress
                            lastDraggedProgress = progress
                            /// Seeking Video To Dragged Time
                            if let currentPlayerItem = player?.currentItem {
                                let totalDuration = currentPlayerItem.duration.seconds
                                
                                player?.seek(to: .init(seconds: totalDuration * progress, preferredTimescale: 600))
                                
                                if isPlaying {
                                    timeoutControls()
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    isSeeking = false
                                }
                            }
                        })
                )
                .offset(x: progress * videoSize.width > 15 ? -15 : 0)
                .frame(width: 15, height: 15)
        }
    }
    
    /// Playback Controls View
    @ViewBuilder
    func PlayBackControls() -> some View {
        HStack(spacing: 25) {
            Button {
                
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .fontWeight(.ultraLight)
                    .foregroundColor(.white)
                    .padding(15)
                    .background {
                        Circle()
                            .fill(.black.opacity(0.35))
                    }
            }
            .disabled(true)
            .opacity(0.6)
            

            
            Button {
                if isFinishedPlaying {
                    isFinishedPlaying = false
                    player?.seek(to: .zero)
                    progress = .zero
                    lastDraggedProgress = .zero
                }
                if isPlaying {
                    player?.pause()
                    if let timeoutTask {
                        timeoutTask.cancel()
                    }
                } else {
                    player?.play()
                    timeoutControls()
                }
                
                togglePlayWithAnimation($isPlaying)
            } label: {
                Image(systemName: isFinishedPlaying ? "arrow.clockwise" : (isPlaying ? "pause.fill" : "play.fill"))
                    .font(.title)
//                    .fontWeight(.ultraLight)
                    .foregroundColor(.white)
                    .padding(15)
                    .background {
                        Circle()
                            .fill(.black.opacity(0.35))
                    }
            }
            .scaleEffect(1.1)
            
            Button {
                
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .fontWeight(.ultraLight)
                    .foregroundColor(.white)
                    .padding(15)
                    .background {
                        Circle()
                            .fill(.black.opacity(0.35))
                    }
            }
            .disabled(true)
            .opacity(0.6)
            
        }
        .opacity(showPlayerControls && !isDragging ? 1 : 0)
        .animation(.easeIn(duration: 0.125), value: showPlayerControls && !isDragging)
    }
    
    func togglePlayWithAnimation(_ isPlaying: Binding<Bool>, duration: Double = 0.15) {
        withAnimation(.easeInOut(duration: duration)) {
            isPlaying.wrappedValue.toggle()
        }
    }
    
    func timeoutControls() {
        if let timeoutTask {
            timeoutTask.cancel()
        }
        
        timeoutTask = .init(block: {
            withAnimation(.easeInOut(duration: 0.35)) {
                showPlayerControls = false
            }
        })
        
        if let timeoutTask {
            DispatchQueue.main.asyncAfter(deadline:  .now() + 3, execute: timeoutTask)
        }
    }
    
    func generateThumbnailFrames() {
        Task {
            guard let asset = player?.currentItem?.asset else { return }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = .init(width: 250, height: 250)

            do {
                let totalDuration = try await asset.load(.duration).seconds
                var frameTimes: [CMTime] = []

                for progress in stride(from: 0, to: 1, by: 0.01) {
                    let time = CMTime(seconds: progress * totalDuration, preferredTimescale: 600)
                    frameTimes.append(time)
                }

                for try await result in generator.images(for: frameTimes) {
                    let cgImage = try result.image
                    await MainActor.run {
                        thumbnailFrames.append(UIImage(cgImage: cgImage))
                    }
                }
            } catch {
                print("Error generating thumbnail frames: \(error.localizedDescription)")
            }
        }
    }
}
