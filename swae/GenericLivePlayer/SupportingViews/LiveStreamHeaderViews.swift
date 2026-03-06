//
//  LiveStreamHeaderViews.swift
//  swae
//
//  Header views for live streaming
//

import UIKit

class LiveStreamSmallHeaderView: UIStackView {
    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let countLabel: UILabel = {
        let label = UILabel()
        label.text = "-"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let liveIcon: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let liveLabel: UILabel = {
        let label = UILabel()
        label.text = "Live"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let viewersIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "eye"))
        iv.tintColor = .secondaryLabel
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        axis = .vertical
        spacing = 2
        alignment = .leading
        layoutMargins = UIEdgeInsets(top: 20, left: 177, bottom: 20, right: 12)
        isLayoutMarginsRelativeArrangement = true

        let secondInfoRow = UIStackView(arrangedSubviews: [
            liveIcon, liveLabel, viewersIcon, countLabel,
        ])
        secondInfoRow.axis = .horizontal
        secondInfoRow.spacing = 6
        secondInfoRow.alignment = .center

        addArrangedSubview(titleLabel)
        addArrangedSubview(secondInfoRow)

        NSLayoutConstraint.activate([
            liveIcon.widthAnchor.constraint(equalToConstant: 6),
            liveIcon.heightAnchor.constraint(equalToConstant: 6),
            viewersIcon.widthAnchor.constraint(equalToConstant: 12),
            viewersIcon.heightAnchor.constraint(equalToConstant: 12),
        ])
    }
}

class LiveStreamHeaderView: UIStackView {
    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let timeLabel: UILabel = {
        let label = UILabel()
        label.text = "Started"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let countLabel: UILabel = {
        let label = UILabel()
        label.text = "-"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let liveIcon: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let liveLabel: UILabel = {
        let label = UILabel()
        label.text = "Live"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let viewersIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "eye"))
        iv.tintColor = .secondaryLabel
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        axis = .horizontal
        alignment = .top
        layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 12, right: 16)
        isLayoutMarginsRelativeArrangement = true

        let secondInfoRow = UIStackView(arrangedSubviews: [
            liveIcon, liveLabel, timeLabel, viewersIcon, countLabel,
        ])
        secondInfoRow.axis = .horizontal
        secondInfoRow.spacing = 10
        secondInfoRow.alignment = .center

        let leftStack = UIStackView(arrangedSubviews: [titleLabel, secondInfoRow])
        leftStack.axis = .vertical
        leftStack.spacing = 2
        leftStack.alignment = .leading

        addArrangedSubview(leftStack)

        NSLayoutConstraint.activate([
            liveIcon.widthAnchor.constraint(equalToConstant: 6),
            liveIcon.heightAnchor.constraint(equalToConstant: 6),
            viewersIcon.widthAnchor.constraint(equalToConstant: 12),
            viewersIcon.heightAnchor.constraint(equalToConstant: 12),
        ])
    }
}

class AutoHidingView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        updateHiddenState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        updateHiddenState()
    }

    override func willRemoveSubview(_ subview: UIView) {
        isHidden = subviews.count <= 1
        super.willRemoveSubview(subview)
    }

    private func updateHiddenState() {
        isHidden = subviews.isEmpty
    }
}



