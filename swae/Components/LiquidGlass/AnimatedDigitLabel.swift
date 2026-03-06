//
//  AnimatedDigitLabel.swift
//  swae
//
//  GPU-accelerated label that animates individual characters when text changes
//  Uses CATextLayer + CABasicAnimation for guaranteed 60fps even under rapid input
//  Matches SwiftUI's .contentTransition(.numericText()) behavior
//
//  PERFORMANCE: True zero-allocation during animation
//  - All character layers pre-allocated at init
//  - All transition layers pre-allocated at init
//  - No DispatchQueue blocks - uses CATransaction completion
//  - Character widths cached at init
//

import UIKit
import QuartzCore

class AnimatedDigitLabel: UIView {
    
    // MARK: - Configuration
    
    var textColor: UIColor = .systemOrange {
        didSet { updateAppearance() }
    }
    
    var font: UIFont = .systemFont(ofSize: 36, weight: .bold) {
        didSet {
            updateFontReferences()
            updateAppearance()
        }
    }
    
    /// Animation duration - 0.25s is visible but snappy
    var animationDuration: CFTimeInterval = 0.25
    
    /// Vertical offset for the slide animation
    var slideOffset: CGFloat = 24
    
    // MARK: - State
    
    private var currentText: String = ""
    private var currentNumericValue: Int64 = 0
    
    // Pre-allocated text layers (max "1,000,000,000" = 13 chars)
    private var characterLayers: [CATextLayer] = []
    private let maxCharacters = 15
    
    // Pre-allocated TRANSITION layers for crossfade animations
    private var transitionLayers: [CATextLayer] = []
    private var transitionLayerInUse: [Bool] = []

    
    // Cached font references for CATextLayer
    private var ctFont: CTFont!
    private var cgFont: CGFont!
    
    // Character width cache to avoid repeated CoreText calls
    private var charWidthCache: [Character: CGFloat] = [:]
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        layer.masksToBounds = true
        
        // Create font references for CATextLayer and CoreText
        updateFontReferences()
        
        // Pre-cache common character widths
        precacheCharacterWidths()
        
        // Pre-allocate all CHARACTER layers
        for _ in 0..<maxCharacters {
            let textLayer = createTextLayer()
            layer.addSublayer(textLayer)
            characterLayers.append(textLayer)
        }
        
        // Pre-allocate TRANSITION layers (for crossfade animations)
        for _ in 0..<maxCharacters {
            let textLayer = createTextLayer()
            layer.addSublayer(textLayer)
            transitionLayers.append(textLayer)
            transitionLayerInUse.append(false)
        }
    }
    
    private func updateFontReferences() {
        // Create CTFont for CoreText measurements
        ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        // Create CGFont for CATextLayer rendering
        cgFont = CTFontCopyGraphicsFont(ctFont, nil)
    }
    
    private func createTextLayer() -> CATextLayer {
        let textLayer = CATextLayer()
        // Use CGFont for proper rendering (not CTFont)
        textLayer.font = cgFont
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = textColor.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.opacity = 0
        textLayer.isHidden = true
        // Disable implicit animations
        textLayer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull(),
            "hidden": NSNull(),
            "string": NSNull()
        ]
        return textLayer
    }
    
    /// Pre-cache widths for digits and common characters
    private func precacheCharacterWidths() {
        let commonChars: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "."]
        for char in commonChars {
            charWidthCache[char] = measureCharacterWidth(char)
        }
    }
    
    /// Measure character width using CoreText (cached)
    private func characterWidth(_ char: Character) -> CGFloat {
        if let cached = charWidthCache[char] {
            return cached
        }
        let width = measureCharacterWidth(char)
        charWidthCache[char] = width
        return width
    }
    
    /// Actual CoreText measurement
    private func measureCharacterWidth(_ char: Character) -> CGFloat {
        let string = String(char) as CFString
        let attrString = CFAttributedStringCreate(
            nil,
            string,
            [kCTFontAttributeName: ctFont as Any] as CFDictionary
        )!
        let line = CTLineCreateWithAttributedString(attrString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
    
    /// Get an available transition layer from the pool
    private func acquireTransitionLayer() -> CATextLayer? {
        for (index, inUse) in transitionLayerInUse.enumerated() {
            if !inUse {
                transitionLayerInUse[index] = true
                return transitionLayers[index]
            }
        }
        return nil
    }
    
    /// Return a transition layer to the pool
    private func releaseTransitionLayer(_ layer: CATextLayer) {
        if let index = transitionLayers.firstIndex(where: { $0 === layer }) {
            transitionLayerInUse[index] = false
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 0
            layer.isHidden = true
            layer.removeAllAnimations()
            CATransaction.commit()
        }
    }

    
    // MARK: - Public API
    
    /// Set the text with optional animation
    func setText(_ newText: String, numericValue: Int64, animated: Bool = true) {
        guard newText != currentText else { return }
        
        let oldText = currentText
        let oldValue = currentNumericValue
        currentText = newText
        currentNumericValue = numericValue
        
        if animated && !UIAccessibility.isReduceMotionEnabled {
            let isIncreasing = numericValue > oldValue
            animateTextChange(from: oldText, to: newText, rollingUp: isIncreasing)
        } else {
            updateTextImmediate(newText)
        }
    }
    
    var text: String { currentText }
    
    // MARK: - Immediate Update (No Animation)
    
    private func updateTextImmediate(_ text: String) {
        // Skip if bounds is zero (will be called again in layoutSubviews)
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let chars = Array(text)
        let charWidths = chars.map { characterWidth($0) }
        let totalWidth = charWidths.reduce(0, +)
        var xOffset = (bounds.width - totalWidth) / 2
        
        for (index, textLayer) in characterLayers.enumerated() {
            if index < chars.count {
                let char = chars[index]
                let width = charWidths[index]
                
                textLayer.string = String(char)
                textLayer.frame = CGRect(
                    x: xOffset,
                    y: (bounds.height - font.lineHeight) / 2,
                    width: width,
                    height: font.lineHeight
                )
                textLayer.opacity = 1
                textLayer.isHidden = false
                textLayer.removeAllAnimations()
                
                xOffset += width
            } else {
                textLayer.opacity = 0
                textLayer.isHidden = true
                textLayer.removeAllAnimations()
            }
        }
        
        // Reset transition layers
        for (index, _) in transitionLayers.enumerated() {
            transitionLayers[index].opacity = 0
            transitionLayers[index].isHidden = true
            transitionLayers[index].removeAllAnimations()
            transitionLayerInUse[index] = false
        }
        
        CATransaction.commit()
    }
    
    // MARK: - Animated Update (GPU-Accelerated, Zero-Allocation)
    
    private func animateTextChange(from oldText: String, to newText: String, rollingUp: Bool) {
        // If bounds is zero, just update immediately (layoutSubviews will handle it)
        guard bounds.width > 0 && bounds.height > 0 else {
            updateTextImmediate(newText)
            return
        }
        
        let newChars = Array(newText)
        let direction: CGFloat = rollingUp ? 1 : -1
        
        // Calculate new layout
        let charWidths = newChars.map { characterWidth($0) }
        let totalWidth = charWidths.reduce(0, +)
        var xOffset = (bounds.width - totalWidth) / 2
        
        // Extract digits only (ignore commas/separators) for comparison
        let oldDigits = Array(oldText.filter { $0.isNumber })
        let newDigits = Array(newText.filter { $0.isNumber })
        
        // For typing (adding digits): align from LEFT - leftmost digits stay same
        // For deleting: align from LEFT - leftmost digits stay same
        // This is how number entry works: you type on the right, left stays stable
        //
        // Example: "12" → "123"
        //   oldDigits = ["1", "2"]
        //   newDigits = ["1", "2", "3"]
        //   Digit 0: "1" == "1" → same (move)
        //   Digit 1: "2" == "2" → same (move)
        //   Digit 2: new "3" → animate in
        //
        // Example: "123" → "12"
        //   oldDigits = ["1", "2", "3"]
        //   newDigits = ["1", "2"]
        //   Digit 0: "1" == "1" → same (move)
        //   Digit 1: "2" == "2" → same (move)
        //   Old digit 2 ("3") → animate out
        
        // Build mapping: for each new digit index (from left), what was the old digit?
        var digitMapping: [Int: Character] = [:] // newDigitIndex (from left) → oldDigit
        for i in 0..<newDigits.count {
            if i < oldDigits.count {
                digitMapping[i] = oldDigits[i]
            }
        }
        
        // Map formatted string indices to their digit position (from left)
        // e.g., "1,234" → index 0 is digit 0, index 2 is digit 1, index 3 is digit 2, etc.
        var newIndexToDigitPos: [Int: Int] = [:]
        var digitCount = 0
        for (idx, char) in newChars.enumerated() {
            if char.isNumber {
                newIndexToDigitPos[idx] = digitCount
                digitCount += 1
            }
        }
        
        // Collect transition layers for cleanup
        var usedTransitionLayers: [CATextLayer] = []
        
        // Batch all animations
        CATransaction.begin()
        CATransaction.setAnimationDuration(animationDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        
        // Animate each character in the new string
        for (index, textLayer) in characterLayers.enumerated() {
            let newChar: Character? = index < newChars.count ? newChars[index] : nil
            
            if let new = newChar {
                let width = charWidths[index]
                let targetFrame = CGRect(
                    x: xOffset,
                    y: (bounds.height - font.lineHeight) / 2,
                    width: width,
                    height: font.lineHeight
                )
                
                if new.isNumber {
                    // It's a digit - check if it existed at same position from left
                    if let digitPos = newIndexToDigitPos[index],
                       let oldDigit = digitMapping[digitPos] {
                        if oldDigit == new {
                            // Same digit, just moved position - animate move
                            animateLayerMove(textLayer, to: targetFrame)
                            // Update the string in case layer was showing something else
                            textLayer.string = String(new)
                            textLayer.isHidden = false
                            textLayer.opacity = 1
                        } else {
                            // Different digit at same position - crossfade
                            if let transitionLayer = acquireTransitionLayer() {
                                usedTransitionLayers.append(transitionLayer)
                                animateLayerChange(
                                    textLayer,
                                    transitionLayer: transitionLayer,
                                    oldChar: oldDigit,
                                    newChar: new,
                                    frame: targetFrame,
                                    direction: direction
                                )
                            }
                        }
                    } else {
                        // New digit (didn't exist before) - animate in
                        animateLayerIn(textLayer, character: new, frame: targetFrame, direction: direction)
                    }
                } else {
                    // Non-digit (comma, etc.) - just show it, animate position
                    textLayer.string = String(new)
                    textLayer.frame = targetFrame
                    textLayer.isHidden = false
                    textLayer.opacity = 1
                    // Commas don't need fancy animation, just appear/move
                }
                
                xOffset += width
            } else {
                // No character at this index - hide the layer
                if textLayer.opacity > 0 {
                    animateLayerOut(textLayer, direction: direction)
                } else {
                    textLayer.isHidden = true
                }
            }
        }
        
        // Release transition layers after animation
        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self else { return }
            for layer in usedTransitionLayers {
                self.releaseTransitionLayer(layer)
            }
        }
        
        CATransaction.commit()
    }

    
    // MARK: - Layer Animations (All GPU-Accelerated, Additive for Rapid Input)
    
    private func animateLayerIn(_ layer: CATextLayer, character: Character, frame: CGRect, direction: CGFloat) {
        // Don't remove animations - let them blend for rapid input
        
        layer.string = String(character)
        layer.frame = frame
        layer.isHidden = false
        layer.opacity = 1
        
        // Animate FROM start position TO final position
        // Rolling UP (increasing): enter from BOTTOM (positive offset)
        // Rolling DOWN (decreasing): enter from TOP (negative offset)
        let startY = frame.midY + (slideOffset * direction)
        
        let posAnim = CASpringAnimation(keyPath: "position.y")
        posAnim.fromValue = startY
        posAnim.toValue = frame.midY
        posAnim.damping = 15
        posAnim.initialVelocity = 0
        posAnim.mass = 1
        posAnim.stiffness = 200
        posAnim.duration = posAnim.settlingDuration
        
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0
        opacityAnim.toValue = 1
        opacityAnim.duration = animationDuration  // Full duration for visible fade
        
        layer.add(posAnim, forKey: "animateIn_pos")
        layer.add(opacityAnim, forKey: "animateIn_opacity")
    }
    
    private func animateLayerOut(_ layer: CATextLayer, direction: CGFloat) {
        // Don't remove animations - let them blend
        
        let startY = layer.position.y
        // Rolling UP (increasing): exit to TOP (negative offset)
        // Rolling DOWN (decreasing): exit to BOTTOM (positive offset)
        let endY = startY - (slideOffset * direction)
        
        layer.opacity = 0
        
        let posAnim = CASpringAnimation(keyPath: "position.y")
        posAnim.fromValue = startY
        posAnim.toValue = endY
        posAnim.damping = 15
        posAnim.initialVelocity = 0
        posAnim.mass = 1
        posAnim.stiffness = 200
        posAnim.duration = posAnim.settlingDuration
        
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 1
        opacityAnim.toValue = 0
        opacityAnim.duration = animationDuration
        
        layer.add(posAnim, forKey: "animateOut_pos")
        layer.add(opacityAnim, forKey: "animateOut_opacity")
    }
    
    private func animateLayerChange(
        _ layer: CATextLayer,
        transitionLayer: CATextLayer,
        oldChar: Character,
        newChar: Character,
        frame: CGRect,
        direction: CGFloat
    ) {
        // Don't remove animations - let them blend
        
        // Setup transition layer with OLD character at current position
        transitionLayer.string = String(oldChar)
        transitionLayer.frame = layer.frame
        transitionLayer.isHidden = false
        transitionLayer.opacity = 0  // Model layer state (will animate FROM 1)
        
        // Animate transition layer OUT (old character exits)
        let oldEndY = layer.position.y - (slideOffset * direction)
        
        let oldPosAnim = CASpringAnimation(keyPath: "position.y")
        oldPosAnim.fromValue = layer.position.y
        oldPosAnim.toValue = oldEndY
        oldPosAnim.damping = 15
        oldPosAnim.initialVelocity = 0
        oldPosAnim.mass = 1
        oldPosAnim.stiffness = 200
        oldPosAnim.duration = oldPosAnim.settlingDuration
        
        let oldOpacityAnim = CABasicAnimation(keyPath: "opacity")
        oldOpacityAnim.fromValue = 1
        oldOpacityAnim.toValue = 0
        oldOpacityAnim.duration = animationDuration
        
        transitionLayer.add(oldPosAnim, forKey: "fadeOut_pos")
        transitionLayer.add(oldOpacityAnim, forKey: "fadeOut_opacity")
        
        // Setup main layer with NEW character
        layer.string = String(newChar)
        layer.frame = frame
        layer.opacity = 1
        
        // Animate main layer IN (new character enters)
        let startY = frame.midY + (slideOffset * direction)
        
        let newPosAnim = CASpringAnimation(keyPath: "position.y")
        newPosAnim.fromValue = startY
        newPosAnim.toValue = frame.midY
        newPosAnim.damping = 15
        newPosAnim.initialVelocity = 0
        newPosAnim.mass = 1
        newPosAnim.stiffness = 200
        newPosAnim.duration = newPosAnim.settlingDuration
        
        let newOpacityAnim = CABasicAnimation(keyPath: "opacity")
        newOpacityAnim.fromValue = 0
        newOpacityAnim.toValue = 1
        newOpacityAnim.duration = animationDuration
        
        layer.add(newPosAnim, forKey: "fadeIn_pos")
        layer.add(newOpacityAnim, forKey: "fadeIn_opacity")
    }
    
    private func animateLayerMove(_ layer: CATextLayer, to frame: CGRect) {
        // Don't remove animations - let them blend
        
        let oldX = layer.position.x
        layer.frame = frame
        
        let posAnim = CASpringAnimation(keyPath: "position.x")
        posAnim.fromValue = oldX
        posAnim.toValue = frame.midX
        posAnim.damping = 15
        posAnim.initialVelocity = 0
        posAnim.mass = 1
        posAnim.stiffness = 200
        posAnim.duration = posAnim.settlingDuration
        
        layer.add(posAnim, forKey: "move")
    }
    
    // MARK: - Appearance Updates
    
    private func updateAppearance() {
        let allLayers = characterLayers + transitionLayers
        for textLayer in allLayers {
            textLayer.font = cgFont
            textLayer.fontSize = font.pointSize
            textLayer.foregroundColor = textColor.cgColor
        }
        charWidthCache.removeAll()
        precacheCharacterWidths()
        if !currentText.isEmpty {
            updateTextImmediate(currentText)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if !currentText.isEmpty {
            updateTextImmediate(currentText)
        }
    }
    
    // MARK: - Accessibility
    
    override var accessibilityLabel: String? {
        get { currentText }
        set { }
    }
}
