//
//  LiveVideoEmbeddedView.swift
//  swae
//
//  Mini player view that's always present in the view hierarchy
//

import AVFoundation
import Combine
import UIKit

class LiveVideoEmbeddedView: UIView {
    
    // MARK: - Video Player
    let playerView = PlayerView()
    
    // MARK: - Top Overlay (Live badge, viewer count, close button)
    private let topOverlay = UIView()
    private let liveDot = UIView()
    private let liveLabel = UILabel()
    private let viewerIcon = UIImageView()
    private let viewerCountLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    
    // MARK: - Center Play Button & Loading Indicator
    private let playButton = UIButton(type: .custom)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    
    // MARK: - Bottom Overlay (Title with gradient)
    private let bottomGradient = CAGradientLayer()
    private let titleLabel = UILabel()
    
    // MARK: - Other Views
    private let streamEndedView = UIView()
    private let streamEndedLabel = UILabel()
    
    // Chevrons for edge indicators (when dragged to edge)
    private let leftChevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let rightChevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    // MARK: - Properties
    var onClose: (() -> Void)?
    
    @Published var showChevron = false
    var playbackStateCancellable: AnyCancellable?
    private var chevronCancellable: AnyCancellable?
    
    private var liveStream: LiveStream?

    var player: VideoPlayer? {
        didSet {
            let hasPlayer = player != nil
            streamEndedView.isHidden = hasPlayer
            // Hide play button and loading indicator when stream ended
            playButton.isHidden = !hasPlayer
            loadingIndicator.stopAnimating()
            
            if let player = player {
                playerView.player = player.avPlayer
            } else {
                playerView.player = nil
            }
        }
    }

    // MARK: - Init
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update gradient frame
        bottomGradient.frame = CGRect(x: 0, y: bounds.height - 36, width: bounds.width, height: 36)
    }

    // MARK: - Setup
    
    private func setupView() {
        backgroundColor = .black
        layer.cornerRadius = 12
        layer.masksToBounds = true  // Clip all content to rounded corners
        
        // No border
        layer.borderWidth = 0
        layer.borderColor = nil

        setupPlayerView()
        setupStreamEndedView()  // Add BEFORE overlays so buttons are on top
        setupTopOverlay()
        setupPlayButton()
        setupBottomOverlay()
        setupChevrons()
        
        // Subscribe to showChevron changes
        chevronCancellable = $showChevron
            .sink { [weak self] show in
                self?.leftChevron.isHidden = !show
                self?.rightChevron.isHidden = !show
            }
    }
    
    private func setupPlayerView() {
        addSubview(playerView)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.layer.cornerRadius = 12
        playerView.clipsToBounds = true  // Clip video content to rounded corners
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    
    private func setupTopOverlay() {
        // No background - transparent overlay, just the elements with shadows
        topOverlay.backgroundColor = .clear
        topOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topOverlay)
        
        // Live dot - add shadow for visibility
        liveDot.backgroundColor = .systemRed
        liveDot.layer.cornerRadius = 4
        liveDot.layer.shadowColor = UIColor.black.cgColor
        liveDot.layer.shadowOffset = CGSize(width: 0, height: 1)
        liveDot.layer.shadowRadius = 2
        liveDot.layer.shadowOpacity = 0.6
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        topOverlay.addSubview(liveDot)
        
        // Live label
        liveLabel.text = "LIVE"
        liveLabel.font = .systemFont(ofSize: 10, weight: .bold)
        liveLabel.textColor = .white
        liveLabel.layer.shadowColor = UIColor.black.cgColor
        liveLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        liveLabel.layer.shadowRadius = 2
        liveLabel.layer.shadowOpacity = 0.6
        liveLabel.translatesAutoresizingMaskIntoConstraints = false
        topOverlay.addSubview(liveLabel)
        
        // Viewer icon
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        viewerIcon.image = UIImage(systemName: "eye.fill", withConfiguration: config)
        viewerIcon.tintColor = .white
        viewerIcon.layer.shadowColor = UIColor.black.cgColor
        viewerIcon.layer.shadowOffset = CGSize(width: 0, height: 1)
        viewerIcon.layer.shadowRadius = 2
        viewerIcon.layer.shadowOpacity = 0.6
        viewerIcon.translatesAutoresizingMaskIntoConstraints = false
        topOverlay.addSubview(viewerIcon)
        
        // Viewer count label
        viewerCountLabel.text = "0"
        viewerCountLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        viewerCountLabel.textColor = .white
        viewerCountLabel.layer.shadowColor = UIColor.black.cgColor
        viewerCountLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        viewerCountLabel.layer.shadowRadius = 2
        viewerCountLabel.layer.shadowOpacity = 0.6
        viewerCountLabel.translatesAutoresizingMaskIntoConstraints = false
        topOverlay.addSubview(viewerCountLabel)
        
        // Close button
        let closeConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: closeConfig), for: .normal)
        closeButton.tintColor = .white
        closeButton.layer.shadowColor = UIColor.black.cgColor
        closeButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        closeButton.layer.shadowRadius = 2
        closeButton.layer.shadowOpacity = 0.6
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        topOverlay.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            // Top overlay
            topOverlay.topAnchor.constraint(equalTo: topAnchor),
            topOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            topOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            topOverlay.heightAnchor.constraint(equalToConstant: 24),
            
            // Live dot
            liveDot.leadingAnchor.constraint(equalTo: topOverlay.leadingAnchor, constant: 8),
            liveDot.centerYAnchor.constraint(equalTo: topOverlay.centerYAnchor),
            liveDot.widthAnchor.constraint(equalToConstant: 8),
            liveDot.heightAnchor.constraint(equalToConstant: 8),
            
            // Live label
            liveLabel.leadingAnchor.constraint(equalTo: liveDot.trailingAnchor, constant: 4),
            liveLabel.centerYAnchor.constraint(equalTo: topOverlay.centerYAnchor),
            
            // Viewer icon
            viewerIcon.leadingAnchor.constraint(equalTo: liveLabel.trailingAnchor, constant: 8),
            viewerIcon.centerYAnchor.constraint(equalTo: topOverlay.centerYAnchor),
            
            // Viewer count
            viewerCountLabel.leadingAnchor.constraint(equalTo: viewerIcon.trailingAnchor, constant: 3),
            viewerCountLabel.centerYAnchor.constraint(equalTo: topOverlay.centerYAnchor),
            
            // Close button
            closeButton.trailingAnchor.constraint(equalTo: topOverlay.trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: topOverlay.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
    
    private func setupPlayButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .selected)
        playButton.tintColor = .white
        // No background - just the icon with shadow for visibility
        playButton.layer.shadowColor = UIColor.black.cgColor
        playButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        playButton.layer.shadowRadius = 3
        playButton.layer.shadowOpacity = 0.6
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        addSubview(playButton)
        
        // Loading indicator (shown during buffering)
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    
    private func setupBottomOverlay() {
        // Gradient layer (transparent to black)
        bottomGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.7).cgColor
        ]
        bottomGradient.locations = [0.0, 1.0]
        layer.addSublayer(bottomGradient)
        
        // Title label
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }
    
    private func setupStreamEndedView() {
        streamEndedView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        streamEndedView.isHidden = true
        streamEndedView.layer.cornerRadius = 12
        streamEndedView.clipsToBounds = true
        streamEndedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(streamEndedView)
        
        streamEndedLabel.text = "STREAM ENDED"
        streamEndedLabel.textColor = .gray
        streamEndedLabel.font = UIFont.boldSystemFont(ofSize: 12)
        streamEndedLabel.textAlignment = .center
        streamEndedLabel.translatesAutoresizingMaskIntoConstraints = false
        streamEndedView.addSubview(streamEndedLabel)
        
        NSLayoutConstraint.activate([
            streamEndedView.topAnchor.constraint(equalTo: topAnchor),
            streamEndedView.bottomAnchor.constraint(equalTo: bottomAnchor),
            streamEndedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            streamEndedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            streamEndedLabel.centerXAnchor.constraint(equalTo: streamEndedView.centerXAnchor),
            streamEndedLabel.centerYAnchor.constraint(equalTo: streamEndedView.centerYAnchor),
        ])
    }
    
    private func setupChevrons() {
        // Left chevron (rotated to point left)
        leftChevron.translatesAutoresizingMaskIntoConstraints = false
        leftChevron.transform = .init(rotationAngle: .pi)
        leftChevron.tintColor = .white
        leftChevron.isHidden = true
        addSubview(leftChevron)
        
        // Right chevron
        rightChevron.translatesAutoresizingMaskIntoConstraints = false
        rightChevron.tintColor = .white
        rightChevron.isHidden = true
        addSubview(rightChevron)
        
        NSLayoutConstraint.activate([
            leftChevron.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftChevron.topAnchor.constraint(equalTo: topAnchor),
            leftChevron.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            rightChevron.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightChevron.topAnchor.constraint(equalTo: topAnchor),
            rightChevron.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Public Methods
    
    func setup(player: VideoPlayer, liveStream: LiveStream) {
        self.player = player
        self.liveStream = liveStream
        playerView.player = player.avPlayer
        
        // Update UI with stream info
        titleLabel.text = liveStream.title
        viewerCountLabel.text = "\(liveStream.viewerCount)"

        // Update live/replay/ended indicators
        if liveStream.isLive {
            liveDot.backgroundColor = .systemRed
            liveLabel.text = "LIVE"
            liveLabel.textColor = .white
        } else if liveStream.hasRecording {
            liveDot.backgroundColor = .systemBlue
            liveLabel.text = "REPLAY"
            liveLabel.textColor = .white
        } else {
            // Ended with no recording — not playable
            liveDot.backgroundColor = .systemGray
            liveLabel.text = "ENDED"
            liveLabel.textColor = .white.withAlphaComponent(0.6)
        }

        // Subscribe to playback state changes
        playbackStateCancellable = player.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updatePlayButtonState(state: state)
            }
    }

    func removePlayer() {
        player = nil
        liveStream = nil
        playbackStateCancellable = nil
        titleLabel.text = nil
        viewerCountLabel.text = "0"
        loadingIndicator.stopAnimating()
    }

    // MARK: - Private Methods
    
    private func updatePlayButtonState(state: PlaybackState) {
        switch state {
        case .playing:
            // Show pause icon, hide loading
            loadingIndicator.stopAnimating()
            playButton.isHidden = false
            playButton.isSelected = false  // .normal state shows pause icon
            
        case .paused:
            // Show play icon, hide loading
            loadingIndicator.stopAnimating()
            playButton.isHidden = false
            playButton.isSelected = true  // .selected state shows play icon
            
        case .loading:
            // Show loading indicator, hide play button
            playButton.isHidden = true
            loadingIndicator.startAnimating()
        }
        
        // Animate the button
        if !playButton.isHidden {
            playButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0.5
            ) {
                self.playButton.transform = .identity
            }
        }
    }

    // MARK: - Actions
    
    @objc private func playButtonTapped() {
        guard let player = player else { return }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Toggle play/pause based on current state
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    @objc private func closeButtonTapped() {
        // Clear the controller reference (this will hide the mini player via didSet)
        RootViewController.instance.liveVideoController = nil
        onClose?()
    }
}
