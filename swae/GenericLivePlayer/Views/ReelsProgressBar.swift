//
//  ReelsProgressBar.swift
//  swae
//
//  Instagram Reels-style progress bar.
//  Tap anywhere to seek. Drag to scrub. Large 44pt hit area.
//  Track expands on touch for visual feedback.
//

import AVFoundation
import UIKit

class ReelsProgressBar: UIView {

    let track: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        v.layer.cornerRadius = 0.75
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let fill: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        l.textColor = .white
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var fillWidthConstraint: NSLayoutConstraint?
    private var trackHeightConstraint: NSLayoutConstraint?

    /// Exposed so the parent controller can set `panGesture.require(toFail:)`.
    private(set) var scrubGesture: UIPanGestureRecognizer?

    private var isScrubbing = false

    /// True while waiting for a seek to complete — prevents time-observer from snapping the bar back.
    private(set) var isSeeking = false

    /// Callback fired when the user finishes scrubbing. Parameter is progress 0...1.
    var onScrubEnded: ((CGFloat) -> Void)?

    /// Callback fired during scrub. Parameter is progress 0...1.
    var onScrubChanged: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false

        addSubview(track)
        track.addSubview(fill)
        addSubview(timeLabel)

        trackHeightConstraint = track.heightAnchor.constraint(equalToConstant: 1.5)
        fillWidthConstraint = fill.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            trackHeightConstraint!,

            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidthConstraint!,

            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            timeLabel.bottomAnchor.constraint(equalTo: track.topAnchor, constant: -4),
        ])

        // Pan gesture on the entire view (44pt hit area)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleScrub(_:)))
        addGestureRecognizer(pan)
        isUserInteractionEnabled = true
        scrubGesture = pan

        // Tap gesture on the entire view — tap anywhere to seek
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Hit Testing

    // Expand the touch area upward so it's easier to hit
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = bounds.insetBy(dx: 0, dy: -15)
        return expandedBounds.contains(point)
    }

    // MARK: - Public

    func updateProgress(_ progress: CGFloat) {
        guard !isScrubbing, !isSeeking else { return }
        let trackWidth = track.bounds.width
        guard trackWidth > 0 else { return }
        fillWidthConstraint?.constant = trackWidth * progress
    }

    func updateTimeLabel(current: Double, total: Double) {
        guard !isScrubbing, !isSeeking else { return }
        timeLabel.text = "\(formatTime(current)) / \(formatTime(total))"
    }

    /// Call when a seek begins — locks the bar at the tapped position.
    func beginSeeking() {
        isSeeking = true
    }

    /// Call when the seek completes — unlocks the bar.
    func endSeeking() {
        isSeeking = false
    }

    // MARK: - Scrub Gestures

    @objc private func handleScrub(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: track)
        let trackWidth = track.bounds.width
        guard trackWidth > 0 else { return }
        let progress = max(0, min(1, location.x / trackWidth))

        switch gesture.state {
        case .began:
            isScrubbing = true
            timeLabel.isHidden = false
            UIView.animate(withDuration: 0.15) {
                self.trackHeightConstraint?.constant = 4
                self.track.layer.cornerRadius = 2
                self.track.backgroundColor = UIColor.white.withAlphaComponent(0.3)
                self.fill.backgroundColor = .white
                self.layoutIfNeeded()
            }
            applyScrubProgress(progress)
            onScrubChanged?(progress)
        case .changed:
            applyScrubProgress(progress)
            onScrubChanged?(progress)
        case .ended, .cancelled:
            applyScrubProgress(progress)
            onScrubEnded?(progress)
            isScrubbing = false
            // Collapse track and hide time label
            UIView.animate(withDuration: 0.25) {
                self.trackHeightConstraint?.constant = 1.5
                self.track.layer.cornerRadius = 0.75
                self.track.backgroundColor = UIColor.white.withAlphaComponent(0.15)
                self.fill.backgroundColor = UIColor.white.withAlphaComponent(0.8)
                self.layoutIfNeeded()
            }
            timeLabel.isHidden = true
        default: break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: track)
        let trackWidth = track.bounds.width
        guard trackWidth > 0 else { return }
        let progress = max(0, min(1, location.x / trackWidth))

        // Visual feedback — briefly expand
        UIView.animate(withDuration: 0.1) {
            self.trackHeightConstraint?.constant = 4
            self.track.layer.cornerRadius = 2
            self.track.backgroundColor = UIColor.white.withAlphaComponent(0.3)
            self.fill.backgroundColor = .white
            self.layoutIfNeeded()
        }

        applyScrubProgress(progress)
        onScrubEnded?(progress)

        UIView.animate(withDuration: 0.25, delay: 0.1) {
            self.trackHeightConstraint?.constant = 1.5
            self.track.layer.cornerRadius = 0.75
            self.track.backgroundColor = UIColor.white.withAlphaComponent(0.15)
            self.fill.backgroundColor = UIColor.white.withAlphaComponent(0.8)
            self.layoutIfNeeded()
        }
    }

    private func applyScrubProgress(_ progress: CGFloat) {
        let trackWidth = track.bounds.width
        guard trackWidth > 0 else { return }
        fillWidthConstraint?.constant = trackWidth * progress
    }

    // MARK: - Helpers

    private func formatTime(_ totalSeconds: Double) -> String {
        guard totalSeconds.isFinite && !totalSeconds.isNaN else { return "0:00" }
        let seconds = Int(max(0, totalSeconds))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
