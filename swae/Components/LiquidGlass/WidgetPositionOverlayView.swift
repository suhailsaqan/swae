import UIKit

/// Overlay view for visually positioning widgets on the camera preview.
/// Shows bounding boxes for all widgets in the current scene. The selected widget
/// gets a blue border with corner handles for move/resize. Unselected widgets show
/// a dimmed border and can be tapped to select.
///
/// Coordinate system: widget positions are percentages (0–100) matching
/// SettingsSceneWidget.x/y/width/height. The overlay converts between screen
/// points and percentages using the provided preview rect.
class WidgetPositionOverlayView: UIView {

    // MARK: - Types

    struct WidgetRect {
        let widgetId: UUID
        let name: String
        let type: SettingsWidgetType
    }

    // MARK: - Callbacks

    /// Called at ≤30 fps during drag with updated percentage values.
    var onPositionChanged: ((UUID, Double, Double, Double, Double) -> Void)?

    /// Called once when drag ends so the caller can call sceneUpdated().
    var onDragEnded: (() -> Void)?

    // MARK: - Configuration

    /// The rect (in this view's coordinate space) that corresponds to the camera preview.
    /// Widget percentages are mapped to/from this rect.
    private var previewRect: CGRect = .zero

    /// All widgets in the current scene.
    private var widgets: [WidgetRect] = []

    /// Percentage-based positions keyed by widget ID (mirrors SettingsSceneWidget values).
    private var positions: [UUID: CGRect] = [:]

    /// Currently selected widget ID.
    private(set) var selectedWidgetId: UUID?

    // MARK: - Layers & Views

    /// One shape layer per widget for the bounding box.
    private var boxLayers: [UUID: CAShapeLayer] = [:]

    /// Corner handle layers for the selected widget (topLeft, topRight, bottomLeft, bottomRight).
    private var handleLayers: [AnchorPoint: CAShapeLayer] = [:]

    /// Snap guide lines (horizontal/vertical at 0%, 50%, 100%).
    private var snapGuideH: CAShapeLayer?
    private var snapGuideV: CAShapeLayer?

    // MARK: - Gesture State

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    private var dragAnchor: AnchorPoint?
    private var dragOffset: CGSize = .zero
    private var lastUpdateTime: CFTimeInterval = 0
    private let updateInterval: CFTimeInterval = 1.0 / 30.0 // 30 fps throttle

    private let snapThreshold: CGFloat = 2.0 // percentage units
    private let handleRadius: CGFloat = 8.0

    /// Stores the raw (unsnapped) position so snap doesn't feed back into the next frame.
    private var rawPositions: [UUID: CGRect] = [:]

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.25)
        isUserInteractionEnabled = true

        // Snap guide layers (hidden by default)
        snapGuideH = makeSnapGuideLayer()
        snapGuideV = makeSnapGuideLayer()
        layer.addSublayer(snapGuideH!)
        layer.addSublayer(snapGuideV!)

        // Gestures
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)

        // Pan should not block tap
        tapGesture.require(toFail: panGesture)
    }

    // MARK: - Public API

    /// Configure the overlay with widgets and the preview rect.
    /// - Parameters:
    ///   - widgets: All widgets in the current scene.
    ///   - positions: Current percentage positions keyed by widget ID (x, y, width, height as CGRect).
    ///   - previewRect: The rect in this view's coordinate space that maps to the camera preview.
    ///   - preselectId: Optional widget ID to pre-select.
    func configure(
        widgets: [WidgetRect],
        positions: [UUID: CGRect],
        previewRect: CGRect,
        preselectId: UUID? = nil
    ) {
        self.widgets = widgets
        self.positions = positions
        self.previewRect = previewRect

        // Clear old layers
        boxLayers.values.forEach { $0.removeFromSuperlayer() }
        boxLayers.removeAll()
        clearHandles()

        // Create box layers for each widget
        for widget in widgets {
            let boxLayer = CAShapeLayer()
            boxLayer.fillColor = UIColor.clear.cgColor
            boxLayer.lineWidth = 1.5
            layer.addSublayer(boxLayer)
            boxLayers[widget.widgetId] = boxLayer
        }

        // Select if requested
        selectedWidgetId = preselectId ?? widgets.first?.widgetId
        rawPositions = positions
        rebuildAllBoxes()
    }

    /// Update a single widget's position (called externally if model changes).
    func updatePosition(widgetId: UUID, rect: CGRect) {
        positions[widgetId] = rect
        rawPositions[widgetId] = rect
        updateBoxLayer(for: widgetId)
        if widgetId == selectedWidgetId {
            updateHandles()
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert percentage rect (0–100) to points in this view's coordinate space.
    private func percentToPoints(_ pct: CGRect) -> CGRect {
        let x = previewRect.origin.x + (pct.origin.x / 100.0) * previewRect.width
        let y = previewRect.origin.y + (pct.origin.y / 100.0) * previewRect.height
        let w = (pct.size.width / 100.0) * previewRect.width
        let h = (pct.size.height / 100.0) * previewRect.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Convert points in this view's coordinate space to percentage rect (0–100).
    private func pointsToPercent(_ pts: CGRect) -> CGRect {
        let x = ((pts.origin.x - previewRect.origin.x) / previewRect.width) * 100.0
        let y = ((pts.origin.y - previewRect.origin.y) / previewRect.height) * 100.0
        let w = (pts.size.width / previewRect.width) * 100.0
        let h = (pts.size.height / previewRect.height) * 100.0
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Convert a point in this view to percentage coordinates.
    private func pointToPercent(_ pt: CGPoint) -> CGPoint {
        let x = ((pt.x - previewRect.origin.x) / previewRect.width) * 100.0
        let y = ((pt.y - previewRect.origin.y) / previewRect.height) * 100.0
        return CGPoint(x: x, y: y)
    }

    // MARK: - Box Drawing

    private func rebuildAllBoxes() {
        for widget in widgets {
            updateBoxLayer(for: widget.widgetId)
        }
        updateHandles()
    }

    private func updateBoxLayer(for widgetId: UUID) {
        guard let boxLayer = boxLayers[widgetId],
              let pctRect = positions[widgetId] else { return }

        let frame = percentToPoints(pctRect)
        let path = UIBezierPath(roundedRect: frame, cornerRadius: 2)
        boxLayer.path = path.cgPath

        let isSelected = widgetId == selectedWidgetId
        boxLayer.strokeColor = isSelected
            ? UIColor.systemBlue.cgColor
            : UIColor.white.withAlphaComponent(0.4).cgColor
        boxLayer.lineWidth = isSelected ? 2.0 : 1.0
        boxLayer.lineDashPattern = isSelected ? nil : [4, 4]
    }

    // MARK: - Corner Handles

    private func updateHandles() {
        clearHandles()
        guard let selectedId = selectedWidgetId,
              let pctRect = positions[selectedId] else { return }

        let frame = percentToPoints(pctRect)
        let corners: [(AnchorPoint, CGPoint)] = [
            (.topLeft, CGPoint(x: frame.minX, y: frame.minY)),
            (.topRight, CGPoint(x: frame.maxX, y: frame.minY)),
            (.bottomLeft, CGPoint(x: frame.minX, y: frame.maxY)),
            (.bottomRight, CGPoint(x: frame.maxX, y: frame.maxY)),
        ]

        for (anchor, center) in corners {
            let handleLayer = CAShapeLayer()
            let handleRect = CGRect(
                x: center.x - handleRadius,
                y: center.y - handleRadius,
                width: handleRadius * 2,
                height: handleRadius * 2
            )
            handleLayer.path = UIBezierPath(ovalIn: handleRect).cgPath
            handleLayer.fillColor = UIColor.systemBlue.cgColor
            handleLayer.strokeColor = UIColor.white.cgColor
            handleLayer.lineWidth = 1.5
            layer.addSublayer(handleLayer)
            handleLayers[anchor] = handleLayer
        }
    }

    private func clearHandles() {
        handleLayers.values.forEach { $0.removeFromSuperlayer() }
        handleLayers.removeAll()
    }

    // MARK: - Snap Guides

    private func makeSnapGuideLayer() -> CAShapeLayer {
        let l = CAShapeLayer()
        l.strokeColor = UIColor.systemYellow.cgColor
        l.lineWidth = 0.5
        l.lineDashPattern = [3, 3]
        l.isHidden = true
        return l
    }

    /// Show snap guides if any edge is near 0%, 50%, or 100%.
    private func updateSnapGuides(for pctRect: CGRect) {
        let snapValues: [CGFloat] = [0, 50, 100]
        var showH = false
        var showV = false
        var hY: CGFloat = 0
        var vX: CGFloat = 0

        // Check horizontal edges (top, bottom, centerY)
        let edges: [(CGFloat, Bool)] = [
            (pctRect.minX, false), (pctRect.maxX, false), (pctRect.midX, false),
            (pctRect.minY, true), (pctRect.maxY, true), (pctRect.midY, true),
        ]

        for (val, isHorizontal) in edges {
            for snap in snapValues {
                if abs(val - snap) < snapThreshold {
                    if isHorizontal {
                        showH = true
                        hY = snap
                    } else {
                        showV = true
                        vX = snap
                    }
                }
            }
        }

        if showH, let guide = snapGuideH {
            let y = previewRect.origin.y + (hY / 100.0) * previewRect.height
            let path = UIBezierPath()
            path.move(to: CGPoint(x: previewRect.minX, y: y))
            path.addLine(to: CGPoint(x: previewRect.maxX, y: y))
            guide.path = path.cgPath
            guide.isHidden = false
        } else {
            snapGuideH?.isHidden = true
        }

        if showV, let guide = snapGuideV {
            let x = previewRect.origin.x + (vX / 100.0) * previewRect.width
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: previewRect.minY))
            path.addLine(to: CGPoint(x: x, y: previewRect.maxY))
            guide.path = path.cgPath
            guide.isHidden = false
        } else {
            snapGuideV?.isHidden = true
        }
    }

    private func hideSnapGuides() {
        snapGuideH?.isHidden = true
        snapGuideV?.isHidden = true
    }

    /// Snap a percentage value to 0, 50, or 100 if within threshold.
    private func snap(_ value: CGFloat) -> CGFloat {
        for s: CGFloat in [0, 50, 100] {
            if abs(value - s) < snapThreshold { return s }
        }
        return value
    }

    /// Apply snap to a widget rect by checking all six semantic edges/centers
    /// (left, right, centerX, top, bottom, centerY) against the guide values
    /// (0%, 50%, 100%). Only the closest matching edge per axis is snapped,
    /// and the entire rect is shifted so that edge lands on the guide.
    /// Width and height are never modified — only x and y shift.
    private func snapRect(_ raw: CGRect) -> CGRect {
        var x = raw.origin.x
        var y = raw.origin.y
        let w = raw.size.width
        let h = raw.size.height

        let snapValues: [CGFloat] = [0, 50, 100]

        // Horizontal: check left edge, center, right edge
        let hEdges: [(CGFloat, CGFloat)] = [
            (x, 0),              // left edge → shift = snapVal - x
            (x + w / 2, w / 2),  // centerX  → shift = snapVal - (x + w/2), so x = snapVal - w/2
            (x + w, w),          // right edge → shift = snapVal - (x + w), so x = snapVal - w
        ]
        var bestHDist: CGFloat = .greatestFiniteMagnitude
        var bestHX: CGFloat = x
        for (edgeVal, offset) in hEdges {
            for sv in snapValues {
                let dist = abs(edgeVal - sv)
                if dist < snapThreshold && dist < bestHDist {
                    bestHDist = dist
                    bestHX = sv - offset
                }
            }
        }
        x = bestHX

        // Vertical: check top edge, center, bottom edge
        let vEdges: [(CGFloat, CGFloat)] = [
            (y, 0),              // top edge
            (y + h / 2, h / 2),  // centerY
            (y + h, h),          // bottom edge
        ]
        var bestVDist: CGFloat = .greatestFiniteMagnitude
        var bestVY: CGFloat = y
        for (edgeVal, offset) in vEdges {
            for sv in snapValues {
                let dist = abs(edgeVal - sv)
                if dist < snapThreshold && dist < bestVDist {
                    bestVDist = dist
                    bestVY = sv - offset
                }
            }
        }
        y = bestVY

        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Info Label

    /// Notify callback for info text changes (called by gesture handlers).
    var onInfoTextChanged: ((String) -> Void)?

    private func notifyInfoTextChanged() {
        onInfoTextChanged?(selectedWidgetInfoText())
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)

        // Check if tap is on a widget box (prefer selected widget's handles first)
        for widget in widgets {
            guard let pctRect = positions[widget.widgetId] else { continue }
            let frame = percentToPoints(pctRect)
            let hitArea = frame.insetBy(dx: -20, dy: -20) // generous hit area
            if hitArea.contains(location) {
                selectWidget(widget.widgetId)
                notifyInfoTextChanged()
                return
            }
        }

        // Tap on empty area — deselect
        selectedWidgetId = nil
        rebuildAllBoxes()
        notifyInfoTextChanged()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let selectedId = selectedWidgetId,
              var pctRect = rawPositions[selectedId] else { return }

        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            // Determine anchor point: corner handle or center drag.
            // Use the original touch-down point (before pan movement) for hit testing,
            // because UIPanGestureRecognizer fires .began after the finger has already
            // moved a few points. Without this correction, the user places their finger
            // on a corner handle but the detected location has drifted away from it.
            let translation = gesture.translation(in: self)
            let touchDownLocation = CGPoint(
                x: location.x - translation.x,
                y: location.y - translation.y
            )
            
            // Use the snapped (displayed) position for corner hit testing so the hit
            // zones match the visible blue dots, not the raw unsnapped position.
            let displayRect = positions[selectedId] ?? pctRect
            let frame = percentToPoints(displayRect)
            let pctLocation = pointToPercent(touchDownLocation)

            // Check corner handles first (generous hit area)
            let corners: [(AnchorPoint, CGPoint)] = [
                (.topLeft, CGPoint(x: frame.minX, y: frame.minY)),
                (.topRight, CGPoint(x: frame.maxX, y: frame.minY)),
                (.bottomLeft, CGPoint(x: frame.minX, y: frame.maxY)),
                (.bottomRight, CGPoint(x: frame.maxX, y: frame.maxY)),
            ]

            dragAnchor = nil
            for (anchor, cornerPt) in corners {
                let dist = hypot(touchDownLocation.x - cornerPt.x, touchDownLocation.y - cornerPt.y)
                if dist < handleRadius * 3 {
                    dragAnchor = anchor
                    break
                }
            }

            if dragAnchor == nil {
                // Center drag — compute offset from widget center
                dragAnchor = .center
                let centerX = pctRect.midX
                let centerY = pctRect.midY
                dragOffset = CGSize(
                    width: centerX - pctLocation.x,
                    height: centerY - pctLocation.y
                )
            } else {
                dragOffset = .zero
            }

            lastUpdateTime = CACurrentMediaTime()

        case .changed:
            let pctLocation = pointToPercent(location)

            let (newX, newY, newMaxX, newMaxY) = calculatePositioningRectangle(
                dragAnchor,
                pctRect.origin.x / 100.0,
                pctRect.origin.y / 100.0,
                pctRect.size.width / 100.0,
                pctRect.size.height / 100.0,
                CGPoint(x: pctLocation.x + dragOffset.width, y: pctLocation.y + dragOffset.height),
                CGSize(width: 100, height: 100),
                .zero
            )

            // Convert back from 0–1 to 0–100. This is the raw (unsnapped) position.
            let rawRect = CGRect(
                x: newX * 100,
                y: newY * 100,
                width: max(5, (newMaxX - newX) * 100),
                height: max(4, (newMaxY - newY) * 100)
            )

            // Store raw position so the next frame's calculation isn't affected by snap
            rawPositions[selectedId] = rawRect

            // Apply snap for display and model update
            let snappedRect = snapRect(rawRect)
            positions[selectedId] = snappedRect

            // Update visuals immediately (CAShapeLayer is GPU-composited)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updateBoxLayer(for: selectedId)
            updateHandles()
            CATransaction.commit()

            updateSnapGuides(for: snappedRect)
            notifyInfoTextChanged()

            // Throttle model updates to 30 fps
            let now = CACurrentMediaTime()
            if now - lastUpdateTime >= updateInterval {
                lastUpdateTime = now
                onPositionChanged?(
                    selectedId,
                    Double(snappedRect.origin.x),
                    Double(snappedRect.origin.y),
                    Double(snappedRect.size.width),
                    Double(snappedRect.size.height)
                )
            }

        case .ended, .cancelled:
            // Final position update using snapped position
            if let finalRect = positions[selectedId] {
                onPositionChanged?(
                    selectedId,
                    Double(finalRect.origin.x),
                    Double(finalRect.origin.y),
                    Double(finalRect.size.width),
                    Double(finalRect.size.height)
                )
            }
            hideSnapGuides()
            onDragEnded?()
            dragAnchor = nil
            dragOffset = .zero

            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        default:
            break
        }
    }

    // MARK: - Selection

    func selectWidget(_ widgetId: UUID) {
        selectedWidgetId = widgetId
        rebuildAllBoxes()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Returns the info string for the currently selected widget (name + position).
    func selectedWidgetInfoText() -> String {
        guard let selectedId = selectedWidgetId,
              let widget = widgets.first(where: { $0.widgetId == selectedId }),
              let pct = positions[selectedId] else {
            return "Tap a widget to select"
        }
        let x = Int(pct.origin.x)
        let y = Int(pct.origin.y)
        let w = Int(pct.size.width)
        let h = Int(pct.size.height)
        return "\(widget.name)  x:\(x) y:\(y) w:\(w) h:\(h)"
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Claim all touches within bounds for widget manipulation gestures
        return self.point(inside: point, with: event) ? self : nil
    }
}

// MARK: - UIGestureRecognizerDelegate

extension WidgetPositionOverlayView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return true
    }
}
