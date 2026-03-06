import UIKit

/// Inline exposure bias slider that replaces the button grid inside ExpandedControlsModal
class InlineExposureView: UIView {
    
    // MARK: - Callbacks
    
    var onValueChanged: ((Float) -> Void)?
    var onReset: (() -> Void)?
    var onBack: (() -> Void)?
    
    // MARK: - Views
    
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let resetButton = UIButton(type: .system)
    private let minLabel = UILabel()
    private let maxLabel = UILabel()
    
    // MARK: - Init
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    // MARK: - Setup
    
    private func setup() {
        backgroundColor = .clear
        
        // Back button
        backButton.translatesAutoresizingMaskIntoConstraints = false
        let backConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfig), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)
        
        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "EXPOSURE"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        addSubview(titleLabel)
        
        // EV value label
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = "EV 0.0"
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .center
        addSubview(valueLabel)
        
        // Slider
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = -2.0
        slider.maximumValue = 2.0
        slider.value = 0.0
        slider.minimumTrackTintColor = .systemYellow
        slider.maximumTrackTintColor = UIColor(white: 0.4, alpha: 0.6)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        addSubview(slider)
        
        // Min/max labels
        minLabel.translatesAutoresizingMaskIntoConstraints = false
        minLabel.text = "-2"
        minLabel.font = .systemFont(ofSize: 11, weight: .medium)
        minLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        addSubview(minLabel)
        
        maxLabel.translatesAutoresizingMaskIntoConstraints = false
        maxLabel.text = "+2"
        maxLabel.font = .systemFont(ofSize: 11, weight: .medium)
        maxLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        maxLabel.textAlignment = .right
        addSubview(maxLabel)
        
        // Reset button
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.setTitle("Reset", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        resetButton.layer.cornerRadius = 16
        resetButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        addSubview(resetButton)
        
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),
            
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 32),
            
            slider.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 24),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            
            minLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 4),
            minLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            
            maxLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 4),
            maxLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            
            resetButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            resetButton.topAnchor.constraint(equalTo: minLabel.bottomAnchor, constant: 24),
        ])
    }
    
    // MARK: - Public
    
    func setValue(_ bias: Float) {
        slider.value = bias
        updateValueLabel(bias)
    }
    
    // MARK: - Actions
    
    @objc private func backTapped() { onBack?() }
    
    @objc private func sliderChanged() {
        // Snap to 0 when close
        let value = abs(slider.value) < 0.05 ? Float(0) : (slider.value * 10).rounded() / 10
        slider.value = value
        updateValueLabel(value)
        onValueChanged?(value)
    }
    
    @objc private func resetTapped() {
        slider.setValue(0, animated: true)
        updateValueLabel(0)
        onReset?()
    }
    
    private func updateValueLabel(_ value: Float) {
        let sign = value >= 0 ? "+" : ""
        valueLabel.text = "EV \(sign)\(String(format: "%.1f", value))"
    }
}
