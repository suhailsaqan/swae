//
//  LiveBadgeView.swift
//  swae
//
//  Animated live/ended badge with connected viewer count pill
//

import UIKit

/// Animated live/ended badge with integrated viewer count
final class LiveBadgeView: UIView {
    private let dotView = UIView()
    private let label = UILabel()
    private let countContainer = UIView()
    private let countLabel = UILabel()
    private var isLive = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        layer.cornerRadius = 12
        clipsToBounds = true

        // Pulsing dot
        dotView.backgroundColor = .white
        dotView.layer.cornerRadius = 3
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        // Status label (LIVE / ENDED)
        label.text = "LIVE"
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // Viewer count container — solid black section on the right
        countContainer.backgroundColor = .black
        countContainer.translatesAutoresizingMaskIntoConstraints = false
        countContainer.isHidden = true
        addSubview(countContainer)

        // Viewer count label
        countLabel.font = .systemFont(ofSize: 11, weight: .bold)
        countLabel.textColor = .white
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countContainer.addSubview(countLabel)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6),

            label.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Count container flush against the right edge
            countContainer.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            countContainer.topAnchor.constraint(equalTo: topAnchor),
            countContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            countContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Count label inside container with padding
            countLabel.leadingAnchor.constraint(equalTo: countContainer.leadingAnchor, constant: 6),
            countLabel.trailingAnchor.constraint(equalTo: countContainer.trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: countContainer.centerYAnchor),

            heightAnchor.constraint(equalToConstant: 24),
        ])

        startPulseAnimation()
    }

    func setLive(_ live: Bool) {
        isLive = live
        if live {
            backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
            label.text = "LIVE"
            startPulseAnimation()
        } else {
            backgroundColor = UIColor.systemGray.withAlphaComponent(0.9)
            label.text = "ENDED"
            dotView.layer.removeAllAnimations()
        }
    }

    /// Set replay state — ended stream with a playable recording
    func setReplay() {
        isLive = false
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        label.text = "REPLAY"
        dotView.backgroundColor = .white
        dotView.layer.removeAllAnimations()
    }

    /// Set the viewer/participant count. Pass nil or 0 to hide.
    func setViewerCount(_ count: Int) {
        if count > 0 {
            countLabel.text = "\(count)"
            countContainer.isHidden = false
        } else {
            countContainer.isHidden = true
        }
    }

    private func startPulseAnimation() {
        guard isLive else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 1.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        dotView.layer.add(animation, forKey: "pulse")
    }
    
    func resetAnimations() {
        dotView.layer.removeAllAnimations()
    }
}
