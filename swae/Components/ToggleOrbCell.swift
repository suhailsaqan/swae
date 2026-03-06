//
//  ToggleOrbCell.swift
//  swae
//
//  Collection view cell containing a mini liquid orb toggle
//

import MetalKit
import UIKit

// MARK: - Toggle Type

enum ToggleOrbType {
    case widget
    case lut
    case mic
    case torch
    case mute
    case flip
    case scene
    case obs
    case streams
    
    var icon: String {
        switch self {
        case .widget: return "square.grid.3x3"
        case .lut: return "camera.filters"
        case .mic: return "mic.fill"
        case .torch: return "flashlight.on.fill"
        case .mute: return "speaker.wave.2.fill"
        case .flip: return "camera.rotate"
        case .scene: return "photo.on.rectangle"
        case .obs: return "video.fill"
        case .streams: return "dot.radiowaves.left.and.right"
        }
    }
    
    var title: String {
        switch self {
        case .widget: return "Widget"
        case .lut: return "LUT"
        case .mic: return "Mic"
        case .torch: return "Torch"
        case .mute: return "Mute"
        case .flip: return "Flip"
        case .scene: return "Scene"
        case .obs: return "OBS"
        case .streams: return "Streams"
        }
    }
    
    func config(isOn: Bool) -> MiniOrbConfig {
        switch self {
        case .widget: return .widget(isOn: isOn)
        case .lut: return .lut(isOn: isOn)
        case .mic: return .mic(isOn: isOn)
        case .torch: return .torch(isOn: isOn)
        case .mute: return .mute(isOn: isOn)
        case .flip: return .flip(isOn: isOn)
        case .scene: return .scene(isOn: isOn)
        case .obs: return .obs(isOn: isOn)
        case .streams: return .scene(isOn: isOn)  // Reuse scene config for streams
        }
    }
}

// MARK: - ToggleOrbCell

class ToggleOrbCell: UICollectionViewCell {
    
    // MARK: - Properties
    
    static let reuseIdentifier = "ToggleOrbCell"
    
    private var orbView: MiniOrbView!
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var action: (() -> Void)?
    private var toggleType: ToggleOrbType = .widget
    private var isOn: Bool = false
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupGesture()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        // Create orb view
        orbView = MiniOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        orbView.translatesAutoresizingMaskIntoConstraints = false
        orbView.isUserInteractionEnabled = false
        
        contentView.addSubview(orbView)
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        
        let orbSize: CGFloat = 44
        
        NSLayoutConstraint.activate([
            // Orb centered horizontally, near top
            orbView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            orbView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            orbView.widthAnchor.constraint(equalToConstant: orbSize),
            orbView.heightAnchor.constraint(equalToConstant: orbSize),
            
            // Icon centered on orb
            iconImageView.centerXAnchor.constraint(equalTo: orbView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: orbView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 20),
            iconImageView.heightAnchor.constraint(equalToConstant: 20),
            
            // Title below orb
            titleLabel.topAnchor.constraint(equalTo: orbView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        
        contentView.backgroundColor = .clear
        backgroundColor = .clear
    }
    
    private func setupGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Configuration
    
    func configure(type: ToggleOrbType, isOn: Bool, action: @escaping () -> Void) {
        self.toggleType = type
        self.isOn = isOn
        self.action = action
        
        // Set icon
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iconImageView.image = UIImage(systemName: type.icon, withConfiguration: config)
        
        // Set title
        titleLabel.text = type.title
        
        // Set orb config
        orbView.config = type.config(isOn: isOn)
        
        // Update icon color based on state
        iconImageView.tintColor = isOn ? .white : .white.withAlphaComponent(0.7)
        
        // Accessibility
        contentView.isAccessibilityElement = true
        contentView.accessibilityLabel = type.title
        contentView.accessibilityValue = isOn ? "On" : "Off"
        contentView.accessibilityHint = "Double tap to toggle"
        contentView.accessibilityTraits = .button
    }
    
    // MARK: - Actions
    
    @objc private func handleTap() {
        // Haptic feedback
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        
        // Animate the orb
        if toggleType == .flip {
            // Flip is momentary, just flash
            orbView.flash()
        }
        
        // Execute action
        action?()
    }
    
    // MARK: - Touch Forwarding
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // Forward to orb for squish effect
        orbView.touchesBegan(touches, with: event)
        
        // Scale down slightly
        UIView.animate(withDuration: 0.1) {
            self.contentView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        orbView.touchesEnded(touches, with: event)
        
        UIView.animate(withDuration: 0.1) {
            self.contentView.transform = .identity
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        orbView.touchesCancelled(touches, with: event)
        
        UIView.animate(withDuration: 0.1) {
            self.contentView.transform = .identity
        }
    }
    
    // MARK: - Reuse
    
    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.image = nil
        titleLabel.text = nil
        action = nil
        orbView.config = .off
        contentView.transform = .identity
    }
}
