//
//  GenericPlayerView.swift
//  swae
//
//  Generic live player view with controls
//

import AVKit
import Combine
import UIKit

enum GenericPlayerViewAction {
    case dismiss
    case fullscreen
    case share
    case mute
}

protocol GenericPlayerViewDelegate: AnyObject {
    func playerViewPerformAction(_ action: GenericPlayerViewAction)
}

class GenericLargePlayerView: GenericPlayerView {
    override var horizontalMargin: CGFloat { 50 }
    override var verticalMargin: CGFloat { 20 }
    override var labelFontSize: CGFloat { 24 }
    override var progressBarBottomOffset: CGFloat { 10 }
    override var progressBarHorizontalMargin: CGFloat { 50 }

    override init() {
        super.init()

        fullscreenButton.setImage(
            UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .normal)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

class GenericPlayerView: UIView {
    let playerView = PlayerView()

    var playerLayer: AVPlayerLayer { playerView.playerLayer }

    var player: VideoPlayer? {
        didSet {
            // Clean up old time observer
            if let observer = timeObserver, let oldPlayer = oldValue?.avPlayer {
                oldPlayer.removeTimeObserver(observer)
                timeObserver = nil
            }
            streamEndedView.isHidden = player != nil
            playerLayer.player = player?.avPlayer
            setCancellables()
        }
    }

    let controlsView = UIView()
    let streamEndedView = UIView()
    lazy var streamEndedLabel: UILabel = {
        let label = UILabel()
        label.text = "STREAM ENDED"
        label.textColor = .systemGray
        label.font = .systemFont(ofSize: labelFontSize, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let threeDotsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "play.fill"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    /// Loading indicator inside controls (for when controls are visible)
    let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    /// Always-visible loading indicator (outside controlsView) - YouTube style
    let alwaysVisibleLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Auto-Hide Timer Properties
    private var controlsAutoHideTimer: Timer?
    private let controlsAutoHideDelay: TimeInterval = 3.0
    private var userManuallyHidControls = false

    let seekPastButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "gobackward.15"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let seekFutureButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "goforward.30"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let muteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "speaker.slash.fill"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let fullscreenButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let liveDot: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let liveLabel: UILabel = {
        let label = UILabel()
        label.text = "LIVE"
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Recording Scrub Bar Components

    // MARK: - YouTube-Style Progress Bar

    /// Background track (full width, semi-transparent) — always visible for recordings
    let progressBarTrack: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.layer.cornerRadius = 2.5
        view.clipsToBounds = true
        return view
    }()

    /// Fill bar (played portion)
    let progressBarFill: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 2.5
        view.clipsToBounds = true
        return view
    }()

    /// Draggable thumb dot — only visible when controls are shown
    let progressThumb: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 7
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        // Shadow for depth
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 2
        view.layer.shadowOpacity = 0.3
        return view
    }()

    /// Combined time label "0:25 / 0:35" shown at bottom-left when controls are visible (recording mode)
    let currentTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "0:00 / 0:00"
        label.textColor = .white
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    /// Duration label — kept for internal tracking but not displayed separately
    let durationLabel: UILabel = {
        let label = UILabel()
        label.text = "0:00"
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    /// Width constraint for the fill — updated by time observer
    private var progressFillWidthConstraint: NSLayoutConstraint?

    /// Height constraint for the track — animates between 3px (thin) and 5px (expanded)
    private var progressBarHeightConstraint: NSLayoutConstraint?

    /// Center X constraint for the thumb — tracks the fill bar's trailing edge
    private var progressThumbCenterXConstraint: NSLayoutConstraint?

    /// Current progress value (0...1) — used for scrubbing
    private var currentProgress: CGFloat = 0

    /// Transparent hit area for scrubbing — always on top for the thin bar
    private let progressHitArea: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Whether the user is currently dragging the scrub slider
    private var isScrubbing = false

    weak var delegate: GenericPlayerViewDelegate?

    var cancellables: Set<AnyCancellable> = []
    var timeObserver: Any?

    /// Whether this player is in recording/replay mode (not a live stream)
    var isRecordingMode: Bool {
        guard let ls = player?.liveStream else { return false }
        return ls.hasRecording && !ls.isLive
    }

    // TO BE OVERRIDDEN BY THE CHILD
    var horizontalMargin: CGFloat { 8 }
    var verticalMargin: CGFloat { 4 }
    var buttonSize: CGFloat { 36 }
    var labelFontSize: CGFloat { 16 }
    var progressBarBottomOffset: CGFloat { 0 }
    var progressBarHorizontalMargin: CGFloat { 0 }

    // Stored constraints for dynamic margin updates (portrait fullscreen)
    private var progressBarLeadingConstraint: NSLayoutConstraint?
    private var progressBarTrailingConstraint: NSLayoutConstraint?
    private var progressHitAreaLeadingConstraint: NSLayoutConstraint?
    private var progressHitAreaTrailingConstraint: NSLayoutConstraint?
    private var liveStackLeadingConstraint: NSLayoutConstraint?
    private var fullscreenButtonTrailingConstraint: NSLayoutConstraint?
    private var currentTimeLabelLeadingConstraint: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        setupViews()
        setupActions()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        playerLayer.videoGravity = .resizeAspectFill

        addSubview(playerView)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        addSubview(controlsView)
        controlsView.isHidden = true
        controlsView.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controlsView.topAnchor.constraint(equalTo: topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        addSubview(streamEndedView)
        streamEndedView.isHidden = true
        streamEndedView.backgroundColor = .darkGray
        streamEndedView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            streamEndedView.topAnchor.constraint(equalTo: topAnchor),
            streamEndedView.bottomAnchor.constraint(equalTo: bottomAnchor),
            streamEndedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            streamEndedView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        streamEndedView.addSubview(streamEndedLabel)
        NSLayoutConstraint.activate([
            streamEndedLabel.centerXAnchor.constraint(equalTo: streamEndedView.centerXAnchor),
            streamEndedLabel.centerYAnchor.constraint(equalTo: streamEndedView.centerYAnchor),
        ])
        
        // Always-visible loading indicator (outside controlsView) - YouTube style
        addSubview(alwaysVisibleLoadingIndicator)
        NSLayoutConstraint.activate([
            alwaysVisibleLoadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            alwaysVisibleLoadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Top controls
        controlsView.addSubview(dismissButton)
        controlsView.addSubview(muteButton)
        controlsView.addSubview(threeDotsButton)
        NSLayoutConstraint.activate([
            dismissButton.leadingAnchor.constraint(
                equalTo: controlsView.leadingAnchor, constant: horizontalMargin),
            dismissButton.topAnchor.constraint(
                equalTo: controlsView.safeAreaLayoutGuide.topAnchor, constant: verticalMargin),
            dismissButton.widthAnchor.constraint(equalToConstant: buttonSize),
            dismissButton.heightAnchor.constraint(equalToConstant: buttonSize),

            threeDotsButton.trailingAnchor.constraint(
                equalTo: controlsView.trailingAnchor, constant: -horizontalMargin),
            threeDotsButton.centerYAnchor.constraint(equalTo: dismissButton.centerYAnchor),
            threeDotsButton.widthAnchor.constraint(equalToConstant: buttonSize),
            threeDotsButton.heightAnchor.constraint(equalToConstant: buttonSize),

            muteButton.trailingAnchor.constraint(
                equalTo: threeDotsButton.leadingAnchor, constant: -4),
            muteButton.centerYAnchor.constraint(equalTo: dismissButton.centerYAnchor),
            muteButton.widthAnchor.constraint(equalToConstant: buttonSize),
            muteButton.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        // Center controls
        controlsView.addSubview(playPauseButton)
        controlsView.addSubview(loadingIndicator)
        controlsView.addSubview(seekPastButton)
        controlsView.addSubview(seekFutureButton)
        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: controlsView.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 60),
            playPauseButton.heightAnchor.constraint(equalToConstant: 60),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: controlsView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),

            seekPastButton.trailingAnchor.constraint(
                equalTo: playPauseButton.leadingAnchor, constant: -30),
            seekPastButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            seekPastButton.widthAnchor.constraint(equalToConstant: 44),
            seekPastButton.heightAnchor.constraint(equalToConstant: 44),

            seekFutureButton.leadingAnchor.constraint(
                equalTo: playPauseButton.trailingAnchor, constant: 30),
            seekFutureButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            seekFutureButton.widthAnchor.constraint(equalToConstant: 44),
            seekFutureButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        // Bottom controls
        let liveStack = UIStackView(arrangedSubviews: [liveDot, liveLabel])
        liveStack.axis = .horizontal
        liveStack.alignment = .center
        liveStack.spacing = 6
        liveStack.translatesAutoresizingMaskIntoConstraints = false

        controlsView.addSubview(liveStack)
        controlsView.addSubview(fullscreenButton)

        // Combined time label for recording mode (inside controlsView, bottom-left)
        controlsView.addSubview(currentTimeLabel)

        let liveStackLeading = liveStack.leadingAnchor.constraint(
                equalTo: controlsView.leadingAnchor, constant: progressBarHorizontalMargin)
        liveStackLeadingConstraint = liveStackLeading

        let fullscreenTrailing = fullscreenButton.trailingAnchor.constraint(
                equalTo: controlsView.trailingAnchor, constant: -progressBarHorizontalMargin)
        fullscreenButtonTrailingConstraint = fullscreenTrailing

        let timeLeading = currentTimeLabel.leadingAnchor.constraint(
                equalTo: controlsView.leadingAnchor, constant: progressBarHorizontalMargin)
        currentTimeLabelLeadingConstraint = timeLeading

        NSLayoutConstraint.activate([
            liveDot.widthAnchor.constraint(equalToConstant: 8),
            liveDot.heightAnchor.constraint(equalToConstant: 8),

            liveStackLeading,
            liveStack.bottomAnchor.constraint(
                equalTo: controlsView.safeAreaLayoutGuide.bottomAnchor, constant: -verticalMargin),

            fullscreenTrailing,
            fullscreenButton.bottomAnchor.constraint(
                equalTo: controlsView.safeAreaLayoutGuide.bottomAnchor, constant: -(progressBarBottomOffset + 15)),
            fullscreenButton.widthAnchor.constraint(equalToConstant: buttonSize),
            fullscreenButton.heightAnchor.constraint(equalToConstant: buttonSize),

            // Combined time label — vertically centered with fullscreen button
            timeLeading,
            currentTimeLabel.centerYAnchor.constraint(
                equalTo: fullscreenButton.centerYAnchor),

        ])

        // Tap gesture to toggle controls
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        // YouTube-style progress bar — added LAST so it sits on top of controlsView
        addSubview(progressBarTrack)
        progressBarTrack.addSubview(progressBarFill)
        progressFillWidthConstraint = progressBarFill.widthAnchor.constraint(equalToConstant: 0)
        progressFillWidthConstraint?.isActive = true
        progressBarHeightConstraint = progressBarTrack.heightAnchor.constraint(equalToConstant: 3)
        progressBarHeightConstraint?.isActive = true
        let pbLeading = progressBarTrack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: progressBarHorizontalMargin)
        let pbTrailing = progressBarTrack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -progressBarHorizontalMargin)
        progressBarLeadingConstraint = pbLeading
        progressBarTrailingConstraint = pbTrailing
        NSLayoutConstraint.activate([
            pbLeading,
            pbTrailing,
            progressBarTrack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -progressBarBottomOffset),

            progressBarFill.leadingAnchor.constraint(equalTo: progressBarTrack.leadingAnchor),
            progressBarFill.topAnchor.constraint(equalTo: progressBarTrack.topAnchor),
            progressBarFill.bottomAnchor.constraint(equalTo: progressBarTrack.bottomAnchor),
        ])

        // Thumb dot — on top of progress bar
        addSubview(progressThumb)
        progressThumbCenterXConstraint = progressThumb.centerXAnchor.constraint(equalTo: progressBarTrack.leadingAnchor)
        progressThumbCenterXConstraint?.isActive = true
        NSLayoutConstraint.activate([
            progressThumb.centerYAnchor.constraint(equalTo: progressBarTrack.centerYAnchor),
            progressThumb.widthAnchor.constraint(equalToConstant: 14),
            progressThumb.heightAnchor.constraint(equalToConstant: 14),
        ])

        // Transparent hit area for scrubbing (30pt tall touch target over the thin bar)
        let hitLeading = progressHitArea.leadingAnchor.constraint(equalTo: leadingAnchor, constant: progressBarHorizontalMargin)
        let hitTrailing = progressHitArea.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -progressBarHorizontalMargin)
        progressHitAreaLeadingConstraint = hitLeading
        progressHitAreaTrailingConstraint = hitTrailing
        addSubview(progressHitArea)
        NSLayoutConstraint.activate([
            hitLeading,
            hitTrailing,
            progressHitArea.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -progressBarBottomOffset),
            progressHitArea.heightAnchor.constraint(equalToConstant: 22),
        ])
        let scrubPan = UIPanGestureRecognizer(target: self, action: #selector(handleProgressPan(_:)))
        progressHitArea.addGestureRecognizer(scrubPan)
        progressHitArea.isUserInteractionEnabled = true
        let scrubTap = UITapGestureRecognizer(target: self, action: #selector(handleProgressTap(_:)))
        progressHitArea.addGestureRecognizer(scrubTap)
    }

    private func setupActions() {
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        seekPastButton.addTarget(self, action: #selector(seekPastTapped), for: .touchUpInside)
        seekFutureButton.addTarget(self, action: #selector(seekFutureTapped), for: .touchUpInside)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        fullscreenButton.addTarget(self, action: #selector(fullscreenTapped), for: .touchUpInside)

        let menu = UIMenu(children: [
            UIAction(title: "Share Stream", image: UIImage(systemName: "square.and.arrow.up")) {
                [weak self] _ in
                self?.delegate?.playerViewPerformAction(.share)
            }
        ])
        threeDotsButton.menu = menu
        threeDotsButton.showsMenuAsPrimaryAction = true
    }

    /// Updates the horizontal margin for the progress bar, hit area, and bottom controls.
    /// Used by the controller to add padding in portrait fullscreen mode.
    func updateProgressBarMargin(_ margin: CGFloat) {
        progressBarLeadingConstraint?.constant = margin
        progressBarTrailingConstraint?.constant = -margin
        progressHitAreaLeadingConstraint?.constant = margin
        progressHitAreaTrailingConstraint?.constant = -margin
        liveStackLeadingConstraint?.constant = margin
        fullscreenButtonTrailingConstraint?.constant = -margin
        currentTimeLabelLeadingConstraint?.constant = margin
    }

    @objc private func handleTap() {
        if controlsView.isHidden {
            showControls()
        } else {
            hideControls()
        }
    }

    @objc private func playPauseTapped() {
        guard let player = player else { return }
        
        // If recording finished, replay from start
        if player.didFinishPlaying {
            player.replay()
            // Immediately show pause icon (optimistic)
            playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            resetControlsAutoHideTimer()
            return
        }
        
        // Toggle play/pause based on current state
        if player.playbackState == .playing {
            player.pause()
            // Immediately show play icon (optimistic — no waiting for state subscriber)
            playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            if !isRecordingMode {
                liveDot.backgroundColor = .systemGray
            }
        } else {
            player.play()
            // Immediately show pause icon (optimistic)
            playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
        
        // Reset auto-hide timer on interaction
        resetControlsAutoHideTimer()
    }

    @objc private func muteTapped() {
        player?.avPlayer.isMuted.toggle()
        resetControlsAutoHideTimer()
    }

    @objc private func seekPastTapped() {
        guard let playerItem = player?.avPlayer.currentItem else { return }
        let currentTime = playerItem.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTime(seconds: 15, preferredTimescale: 1))
        playerItem.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
        if player?.didFinishPlaying == true {
            player?.clearFinishedFlag()
            UIView.transition(with: playPauseButton, duration: 0.15, options: .transitionCrossDissolve) {
                self.playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            }
        }
        resetControlsAutoHideTimer()
    }

    @objc private func seekFutureTapped() {
        guard let playerItem = player?.avPlayer.currentItem else { return }
        let currentTime = playerItem.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: 30, preferredTimescale: 1))
        playerItem.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
        if player?.didFinishPlaying == true {
            player?.clearFinishedFlag()
            UIView.transition(with: playPauseButton, duration: 0.15, options: .transitionCrossDissolve) {
                self.playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            }
        }
        resetControlsAutoHideTimer()
    }

    @objc private func dismissTapped() {
        delegate?.playerViewPerformAction(.dismiss)
    }

    @objc private func fullscreenTapped() {
        delegate?.playerViewPerformAction(.fullscreen)
        resetControlsAutoHideTimer()
    }

    // MARK: - Scrub Bar Actions

    @objc private func scrubBegan() {
        isScrubbing = true
        cancelControlsAutoHideTimer()
    }

    @objc private func scrubChanged(_ progress: CGFloat) {
        guard let duration = player?.avPlayer.currentItem?.duration,
              duration.isNumeric, !duration.isIndefinite else { return }
        let totalSeconds = CMTimeGetSeconds(duration)
        let targetSeconds = Double(progress) * totalSeconds
        currentTimeLabel.text = "\(formatTime(targetSeconds)) / \(formatTime(totalSeconds))"
        currentProgress = progress
        let trackWidth = progressBarTrack.bounds.width
        if trackWidth > 0 {
            progressFillWidthConstraint?.constant = trackWidth * progress
            progressThumbCenterXConstraint?.constant = trackWidth * progress
        }
    }

    @objc private func scrubEnded(_ progress: CGFloat) {
        guard let duration = player?.avPlayer.currentItem?.duration,
              duration.isNumeric, !duration.isIndefinite else {
            isScrubbing = false
            return
        }
        let totalSeconds = CMTimeGetSeconds(duration)
        let targetTime = CMTime(seconds: Double(progress) * totalSeconds, preferredTimescale: 600)
        player?.avPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.isScrubbing = false
            self?.resetControlsAutoHideTimer()
        }
        // If recording had finished, clear the flag since user seeked to a new position
        if player?.didFinishPlaying == true {
            player?.clearFinishedFlag()
            UIView.transition(with: playPauseButton, duration: 0.15, options: .transitionCrossDissolve) {
                self.playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            }
        }
    }

    // MARK: - Progress Bar Gesture Handlers

    @objc private func handleProgressPan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: progressBarTrack)
        let trackWidth = progressBarTrack.bounds.width
        guard trackWidth > 0 else { return }
        let progress = max(0, min(1, location.x / trackWidth))

        switch gesture.state {
        case .began:
            scrubBegan()
            scrubChanged(progress)
        case .changed:
            scrubChanged(progress)
        case .ended, .cancelled:
            scrubEnded(progress)
        default:
            break
        }
    }

    @objc private func handleProgressTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: progressBarTrack)
        let trackWidth = progressBarTrack.bounds.width
        guard trackWidth > 0 else { return }
        let progress = max(0, min(1, location.x / trackWidth))
        scrubBegan()
        scrubChanged(progress)
        scrubEnded(progress)
    }

    // MARK: - Recording Mode Helpers

    /// Configures the UI for recording vs live mode based on the current player's liveStream
    func updateRecordingModeUI() {
        let recording = isRecordingMode
        // Progress bar is always visible in recording mode
        progressBarTrack.isHidden = !recording
        // Time label and thumb only visible when controls are showing
        currentTimeLabel.isHidden = !recording || controlsView.isHidden
        progressThumb.isHidden = !recording || controlsView.isHidden
        // Hide LIVE/REPLAY label in recording mode — it's already in the header below
        liveDot.isHidden = recording
        liveLabel.isHidden = recording
        if recording {
            liveDot.backgroundColor = .systemBlue
        } else {
            liveLabel.text = "LIVE"
        }
    }

    /// Formats seconds into M:SS or H:MM:SS
    func formatTime(_ totalSeconds: Double) -> String {
        guard totalSeconds.isFinite && !totalSeconds.isNaN else { return "0:00" }
        let seconds = Int(max(0, totalSeconds))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
    
    // MARK: - Auto-Hide Timer Methods
    
    private func startControlsAutoHideTimer() {
        cancelControlsAutoHideTimer()
        
        // Only start timer if playing (not paused or loading)
        guard player?.playbackState == .playing else { return }
        
        controlsAutoHideTimer = Timer.scheduledTimer(
            withTimeInterval: controlsAutoHideDelay,
            repeats: false
        ) { [weak self] _ in
            self?.autoHideControls()
        }
    }
    
    private func cancelControlsAutoHideTimer() {
        controlsAutoHideTimer?.invalidate()
        controlsAutoHideTimer = nil
    }
    
    private func resetControlsAutoHideTimer() {
        if !controlsView.isHidden && player?.playbackState == .playing {
            startControlsAutoHideTimer()
        }
    }
    
    /// Auto-hide (doesn't set userManuallyHidControls)
    private func autoHideControls() {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.controlsView.alpha = 0
            self.progressBarTrack.alpha = 0
            self.progressThumb.alpha = 0
        } completion: { _ in
            self.controlsView.isHidden = true
            if self.isRecordingMode {
                self.progressBarTrack.isHidden = true
                self.progressThumb.isHidden = true
                self.currentTimeLabel.isHidden = true
            }
        }
    }

    func hideControls() {
        userManuallyHidControls = true
        cancelControlsAutoHideTimer()
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.controlsView.alpha = 0
            self.progressBarTrack.alpha = 0
            self.progressThumb.alpha = 0
        } completion: { _ in
            self.controlsView.isHidden = true
            if self.isRecordingMode {
                self.progressBarTrack.isHidden = true
                self.progressThumb.isHidden = true
                self.currentTimeLabel.isHidden = true
            }
        }
    }

    func showControls() {
        userManuallyHidControls = false
        controlsView.isHidden = false
        controlsView.alpha = 0
        if isRecordingMode {
            // Show progress bar, thumb and time label
            progressBarTrack.isHidden = false
            progressBarTrack.alpha = 0
            progressThumb.isHidden = false
            progressThumb.alpha = 0
            currentTimeLabel.isHidden = false
            progressBarHeightConstraint?.constant = 5
            progressBarTrack.layer.cornerRadius = 2.5
            progressBarFill.layer.cornerRadius = 2.5
            layoutIfNeeded()
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
            self.controlsView.alpha = 1
            if self.isRecordingMode {
                self.progressBarTrack.alpha = 1
                self.progressThumb.alpha = 1
            }
        }
        
        // Start auto-hide timer only if playing
        if player?.playbackState == .playing {
            startControlsAutoHideTimer()
        }
    }

    func setCancellables() {
        cancellables = []
        if let observer = timeObserver, let avPlayer = player?.avPlayer {
            avPlayer.removeTimeObserver(observer)
        }
        timeObserver = nil

        guard let player else { return }

        // Configure recording mode UI
        updateRecordingModeUI()

        // Observe playback state for play/pause button and loading indicator
        // Debounce only the loading state to prevent brief flash during play/pause transitions.
        // Play/pause icon is updated optimistically in playPauseTapped for instant response.
        player.$playbackState
            .removeDuplicates()
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                
                switch state {
                case .playing:
                    // Hide loading indicators
                    self.alwaysVisibleLoadingIndicator.stopAnimating()
                    self.loadingIndicator.stopAnimating()
                    self.playPauseButton.isHidden = false
                    UIView.transition(with: self.playPauseButton, duration: 0.15, options: .transitionCrossDissolve) {
                        self.playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
                    }
                    
                    // Start auto-hide timer if controls are visible
                    if !self.controlsView.isHidden {
                        self.startControlsAutoHideTimer()
                    }
                    
                case .paused:
                    // Hide loading indicators
                    self.alwaysVisibleLoadingIndicator.stopAnimating()
                    self.loadingIndicator.stopAnimating()
                    self.playPauseButton.isHidden = false
                    // Show replay icon if video finished, otherwise show play
                    let iconName = self.player?.didFinishPlaying == true
                        ? "arrow.counterclockwise"
                        : "play.fill"
                    UIView.transition(with: self.playPauseButton, duration: 0.15, options: .transitionCrossDissolve) {
                        self.playPauseButton.setImage(UIImage(systemName: iconName), for: .normal)
                    }
                    
                    // Cancel auto-hide timer - controls stay visible when paused
                    self.cancelControlsAutoHideTimer()
                    
                case .loading:
                    // Show loading indicator (always visible, independent of controls)
                    self.alwaysVisibleLoadingIndicator.startAnimating()
                    self.loadingIndicator.startAnimating()
                    self.playPauseButton.isHidden = true
                    
                    // Show controls during loading (unless user manually hid them)
                    if !self.userManuallyHidControls && self.controlsView.isHidden {
                        self.showControls()
                    }
                    
                    // Cancel auto-hide timer - controls stay visible during loading
                    self.cancelControlsAutoHideTimer()
                }
            }
            .store(in: &cancellables)

        // Observe didFinishPlaying for replay icon
        player.$didFinishPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] finished in
                guard let self, finished else { return }
                // Show replay icon on the play/pause button
                UIView.transition(with: self.playPauseButton, duration: 0.15, options: .transitionCrossDissolve) {
                    self.playPauseButton.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
                }
                self.playPauseButton.isHidden = false
                // Snap progress bar to 100%
                let trackWidth = self.progressBarTrack.bounds.width
                if trackWidth > 0 {
                    self.currentProgress = 1
                    self.progressFillWidthConstraint?.constant = trackWidth
                    self.progressThumbCenterXConstraint?.constant = trackWidth
                }
                // Show controls so user can see the replay option
                if self.controlsView.isHidden {
                    self.showControls()
                }
                self.cancelControlsAutoHideTimer()
            }
            .store(in: &cancellables)

        // Is Muted
        player.avPlayer.publisher(for: \.isMuted, options: [.initial, .new])
            .map {
                $0
                    ? UIImage(systemName: "speaker.slash.fill")
                    : UIImage(systemName: "speaker.wave.2.fill")
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                self?.muteButton.setImage(image, for: .normal)
            }
            .store(in: &cancellables)

        // Periodic time observer — updates live dot AND scrub bar
        timeObserver = player.avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let avPlayer = self.player?.avPlayer
            let item = avPlayer?.currentItem

            // Update scrub bar for recording mode
            if self.isRecordingMode, !self.isScrubbing,
               let item, let duration = item.duration as CMTime?,
               duration.isNumeric, !duration.isIndefinite {
                let currentSeconds = CMTimeGetSeconds(time)
                let totalSeconds = CMTimeGetSeconds(duration)
                if totalSeconds > 0 {
                    let progress = CGFloat(currentSeconds / totalSeconds)
                    self.currentProgress = progress
                    self.currentTimeLabel.text = "\(self.formatTime(currentSeconds)) / \(self.formatTime(totalSeconds))"
                    // Update progress bar fill and thumb position
                    let trackWidth = self.progressBarTrack.bounds.width
                    if trackWidth > 0 {
                        self.progressFillWidthConstraint?.constant = trackWidth * progress
                        self.progressThumbCenterXConstraint?.constant = trackWidth * progress
                    }
                }
            }

            // Live dot indicator
            guard let avPlayer, let item, avPlayer.rate > 0.5 else {
                self.liveDot.backgroundColor = self.isRecordingMode ? .systemBlue : .systemGray
                return
            }

            if self.isRecordingMode {
                self.liveDot.backgroundColor = .systemBlue
                return
            }

            guard let range = item.seekableTimeRanges.last?.timeRangeValue else {
                self.liveDot.backgroundColor = .systemGray
                return
            }

            let livePosition = CMTimeAdd(range.start, range.duration)
            let currentTime = item.currentTime()
            let difference = CMTimeSubtract(livePosition, currentTime)
            let secondsFromLive = CMTimeGetSeconds(difference)

            self.liveDot.backgroundColor = secondsFromLive <= 5 ? .systemRed : .systemGray
        }
    }
}
