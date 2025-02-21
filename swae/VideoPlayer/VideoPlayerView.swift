//
//  VideoPlayerView.swift
//  swae
//
//  Created by Suhail Saqan on 1/25/25.
//

import AVKit
import SwiftUI

struct VideoPlayerView: View {
//    var size: CGSize
//    var safeArea: EdgeInsets
    let url: URL
//    let onDragDown: (() -> Void)?
    let onDragUp: (() -> Void)?
    
    @State private var videoSize: CGSize = CGSize(width: 393, height: 250)

    @GestureState private var isDragging: Bool = false

    @StateObject private var viewModel: VideoPlayerModel
    
    @EnvironmentObject var orientationMonitor: OrientationMonitor

    init(/*size: CGSize,safeArea: EdgeInsets,*/ url: URL, /*onDragDown: (() -> Void)? = nil,*/ onDragUp: (() -> Void)? = nil) {
//        self.size = size
//        self.safeArea = safeArea
        self.url = url
//        self.onDragDown = onDragDown
        self.onDragUp = onDragUp
        _viewModel = StateObject(wrappedValue: VideoPlayerModel(url: url))
    }
    
    var computedSize: CGSize {
        let screenWidth = UIScreen.main.bounds.width
        if orientationMonitor.isLandscape {
            // Full screen mode: extend to the bottom of the screen.
            return UIScreen.main.bounds.size
        } else {
            // Use the intrinsic video aspect ratio, defaulting to 16:9 if not available.
            let aspectRatio = videoSize.width > 0 ? videoSize.height / videoSize.width : (9.0 / 16.0)
            let calculatedHeight = screenWidth * aspectRatio
            return CGSize(width: screenWidth, height: min(calculatedHeight, 250))
        }
    }

    var body: some View {
//        var scaledSize: CGSize {
//            guard videoSize.width > 0 && videoSize.height > 0 else {
//                return CGSize(width: 0, height: 250)
//            }
//            // Calculate a scale factor that limits the height to 250.
//            let scaleFactor = min(250 / videoSize.height, 1.0)
//            return CGSize(width: videoSize.width * scaleFactor, height: videoSize.height * scaleFactor)
//        }
        
        VStack {
            if !viewModel.playerError {
                CustomVideoPlayer(player: viewModel.player, videoSize: $videoSize)
                    .background(
                        // Use a GeometryReader to report the final size up via a preference.
                        GeometryReader { proxy in
                            Color.clear.preference(key: VideoPlayerViewSizeKey.self, value: proxy.size)
                        }
                    )
                    .background(Color.black)
                    .overlay {
                        Rectangle()
                            .fill(.black.opacity(0.3))
                            .opacity(viewModel.showPlayerControls || isDragging ? 1 : 0)
                            .overlay {
                                PlayBackControls()
                            }
                    }
                    .overlay {
                        HStack(spacing: 60) {
                            DoubleTapSeek {
                                let seconds = viewModel.player.currentTime().seconds - 15
                                viewModel.player.seek(
                                    to: .init(seconds: seconds, preferredTimescale: 600))
                            }
                            
                            DoubleTapSeek(isForward: true) {
                                let seconds = viewModel.player.currentTime().seconds + 15
                                viewModel.player.seek(
                                    to: .init(seconds: seconds, preferredTimescale: 600))
                            }
                        }
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.showPlayerControls.toggle()
                        }
                        
                        if viewModel.isPlaying {
                            viewModel.timeoutControls()
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        SeekerThumbnailView(videoSize)
                            .offset(y: orientationMonitor.isLandscape ? -85 : -60)
                    }
                    .overlay(alignment: .bottom) {
                        VideoSeekerView(videoSize)
                            .offset(y: orientationMonitor.isLandscape ? -15 : 0)
                            .opacity(viewModel.showPlayerControls ? 1 : 0)
                    }
            } else {
                VStack {
                    Text("STREAM NOT LIVE")
                        .font(.headline)
                        .foregroundColor(.purple)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
        .frame(width: computedSize.width, height: computedSize.height)
            //        .frame(width: size.width, height: size.height)
        //            .background {
        //                Rectangle()
        //                    .fill(.black)
        //                    .padding(.trailing, orientationMonitor.isLandscape ? -safeArea.bottom : 0) // remove for now
        //            }
        //            .gesture(
        //                DragGesture()
        //                    .onChanged { value in
        //                        if value.translation.height > 1 && !orientationMonitor.isLandscape {  // Trigger immediately when dragging down
        ////                            onDragDown?()
        //                        }
        //                    }
        //                    .onEnded { value in
        //                        if value.translation.height < -50 {  // Drag Up
        //                            /// Rotate Player
        //                            withAnimation(.easeInOut(duration: 0.15)) {
        //                                orientationMonitor.setOrientation(to: .landscape)
        //                                onDragUp?()
        //                            }
        //                        } else {
        //                            /// Go to Normal
        //                            withAnimation(.easeInOut(duration: 0.15)) {
        //                                orientationMonitor.setOrientation(to: .portrait)
        //                                onDragUp?()
        //                            }
        //                        }
        //                    }
        //            )
        //            .frame(width: size.width, height: orientationMonitor.isLandscape ? size.height : 250)
        .zIndex(10000)
        .onAppear {
            guard !viewModel.isObserverAdded else { return }
            
            viewModel.player.addPeriodicTimeObserver(
                forInterval: .init(seconds: 1, preferredTimescale: 600), queue: .main,
                using: { time in
                    if let currentPlayerItem = viewModel.player.currentItem {
                        let totalDuration = currentPlayerItem.duration.seconds
                        let currentDuration = viewModel.player.currentTime().seconds
                        
                        let calculatedProgress = currentDuration / totalDuration
                        
                        if !viewModel.isSeeking {
                            viewModel.progress = calculatedProgress
                            viewModel.lastDraggedProgress = viewModel.progress
                        }
                    }
                })
            
            viewModel.isObserverAdded = true
            
            viewModel.playerStatusObserver = viewModel.player.observe(
                \.status, options: .new,
                 changeHandler: { player, _ in
                     if player.status == .readyToPlay {
                         viewModel.generateThumbnailFrames()
                     }
                 })
            
            NotificationCenter.default.addObserver(
                viewModel,
                selector: #selector(viewModel.videoDidFinishPlaying),
                name: .AVPlayerItemDidPlayToEndTime,
                object: viewModel.player.currentItem
            )
            
            viewModel.player.play()
            togglePlayWithAnimation($viewModel.isPlaying)
            if let timeoutTask = viewModel.timeoutTask {
                timeoutTask.cancel()
            }
        }
        .onDisappear {
            viewModel.playerStatusObserver?.invalidate()
            viewModel.player.pause()
            togglePlayWithAnimation($viewModel.isPlaying)
            viewModel.timeoutControls()
        }
    }

    @ViewBuilder
    func SeekerThumbnailView(_ videoSize: CGSize) -> some View {
        let thumbSize: CGSize = .init(width: 175, height: 100)
        ZStack {
            if let draggingImage = viewModel.draggingImage {
                Image(uiImage: draggingImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(alignment: .bottom) {
                        if let currentItem = viewModel.player.currentItem {
                            Text(
                                CMTime(
                                    seconds: viewModel.progress * currentItem.duration.seconds,
                                    preferredTimescale: 600
                                ).toTimeString()
                            )
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
        .offset(x: viewModel.progress * (videoSize.width - thumbSize.width - 20))
        .offset(x: 10)
    }

    /// Video Seeker View
    @ViewBuilder
    func VideoSeekerView(_ videoSize: CGSize) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.gray)

            Rectangle()
                .fill(.purple)
                .frame(
                    width: max(
                        videoSize.width * (viewModel.progress.isFinite ? viewModel.progress : 0), 0)
                )
        }
        .frame(height: 3)
        .overlay(alignment: .leading) {
            Circle()
                .fill(.purple)
                .frame(width: 15, height: 15)
                /// Showing Drag Knob Only When Dragging
                .scaleEffect(
                    viewModel.showPlayerControls || isDragging ? 1 : 0.001,
                    anchor: viewModel.progress * videoSize.width > 15 ? .trailing : .leading
                )
                /// For more Dragging Space
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
                /// Moving Along Side With Gesture Progress
                .offset(x: videoSize.width * viewModel.progress)
                .gesture(
                    DragGesture()
                        .updating(
                            $isDragging,
                            body: { _, out, _ in
                                out = true
                            }
                        )
                        .onChanged({ value in
                            if let timeoutTask = viewModel.timeoutTask {
                                timeoutTask.cancel()
                            }

                            let translationX: CGFloat = value.translation.width
                            let calculatedProgress =
                                (translationX / videoSize.width) + viewModel.lastDraggedProgress

                            viewModel.progress = max(min(calculatedProgress, 1), 0)
                            viewModel.isSeeking = true

                            let dragIndex = Int(viewModel.progress / 0.01)
                            if viewModel.thumbnailFrames.indices.contains(dragIndex) {
                                viewModel.draggingImage = viewModel.thumbnailFrames[dragIndex]
                            }
                        })
                        .onEnded({ value in
                            /// Storing Last Known Progress
                            viewModel.lastDraggedProgress = viewModel.progress
                            /// Seeking Video To Dragged Time
                            if let currentPlayerItem = viewModel.player.currentItem {
                                let totalDuration = currentPlayerItem.duration.seconds

                                viewModel.player.seek(
                                    to: .init(
                                        seconds: totalDuration * viewModel.progress,
                                        preferredTimescale: 600))

                                if viewModel.isPlaying {
                                    viewModel.timeoutControls()
                                }

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    viewModel.isSeeking = false
                                    viewModel.isFinishedPlaying = false
                                }
                            }
                        })
                )
                .offset(x: viewModel.progress * videoSize.width > 15 ? -15 : 0)
                .frame(width: 15, height: 15)
        }
    }

    /// Playback Controls View
    @ViewBuilder
    func PlayBackControls() -> some View {
        HStack(spacing: 25) {
//            Button {
//
//            } label: {
//                Image(systemName: "backward.end.fill")
//                    .frame(width: 25, height: 25)
//                    .fontWeight(.ultraLight)
//                    .foregroundColor(.white)
//                    .padding(10)
//                    .background {
//                        Circle()
//                            .fill(.black.opacity(0.35))
//                    }
//            }
//            .disabled(true)
//            .opacity(0.6)

            Button {
                if !viewModel.isLoading {
                    if viewModel.isFinishedPlaying {
                        viewModel.isFinishedPlaying = false
                        viewModel.player.seek(to: .zero)
                        viewModel.progress = .zero
                        viewModel.lastDraggedProgress = .zero
                    }
                    if viewModel.isPlaying {
                        viewModel.player.pause()
                        if viewModel.timeoutTask != nil {
                            viewModel.timeoutTask?.cancel()
                        }
                    } else {
                        viewModel.player.play()
                        viewModel.timeoutControls()
                    }
                    
                    togglePlayWithAnimation($viewModel.isPlaying)
                }
            } label: {
                ZStack {
                    if viewModel.isLoading {
                        LoadingCircleView(strokeColor: .white)
                            .transition(.opacity)
                    } else {
                        Image(
                            systemName: viewModel.isFinishedPlaying
                            ? "arrow.clockwise"
                            : (viewModel.isPlaying ? "pause.fill" : "play.fill")
                        )
                        .frame(width: 25, height: 25)
                        .foregroundColor(.white)
                        .padding(10)
                        .background {
                            Circle()
                                .fill(.black.opacity(0.35))
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
            }
            .scaleEffect(1.1)

//            Button {
//
//            } label: {
//                Image(systemName: "forward.end.fill")
//                    .frame(width: 25, height: 25)
//                    .fontWeight(.ultraLight)
//                    .foregroundColor(.white)
//                    .padding(10)
//                    .background {
//                        Circle()
//                            .fill(.black.opacity(0.35))
//                    }
//            }
//            .disabled(true)
//            .opacity(0.6)

        }
        .opacity(viewModel.showPlayerControls && !isDragging ? 1 : 0)
    }

    func togglePlayWithAnimation(_ isPlaying: Binding<Bool>, duration: Double = 0.15) {
        withAnimation(.easeInOut(duration: duration)) {
            isPlaying.wrappedValue.toggle()
        }
    }
}

struct VideoPlayerViewSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
