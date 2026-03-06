//
//  StreamOverlayViewController.swift
//  swae
//
//  Native UIKit stream overlay controller.
//  Replaces the single full-screen UIHostingController with isolated UIKit containers
//  and small SwiftUI islands. This eliminates the _UIHostingView touch interception
//  bug that blocked tap-to-focus, pinch-to-zoom, and long-press-to-reset-focus.
//

import Collections
import Combine
import SDWebImage
import SwiftUI
import UIKit

class StreamOverlayViewController: UIViewController {

    // MARK: - Properties

    weak var model: Model?
    private var orientation: Orientation
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Native UIKit Views

    private let frontTorchView = UIView()
    private var frontTorchGradient: CAGradientLayer?

    // Chat
    private let chatContainerView = PassthroughView()
    private var chatCollectionView: UICollectionView!
    private var chatDataSource: UICollectionViewDiffableDataSource<Int, Int>!
    private let chatPausedBanner = UIView()
    private let chatPausedLabel = UILabel()
    private var chatBottomClearance: NSLayoutConstraint!
    private var chatWidthMultiplier: NSLayoutConstraint?
    private var chatHeightMultiplier: NSLayoutConstraint?

    // MARK: - SwiftUI Islands

    private var leftStatusHostingVC: UIHostingController<AnyView>?
    private var rightTopStatusHostingVC: UIHostingController<AnyView>?
    private var rightBottomHostingVC: UIHostingController<AnyView>?
    private var debugHostingVC: UIHostingController<AnyView>?

    // Constraint references for orientation updates
    private var leftLeadingConstraint: NSLayoutConstraint?
    private var debugLeadingConstraint: NSLayoutConstraint?

    // Post lookup for data source
    private var postLookup: [Int: ChatPost] = [:]

    // MARK: - Initialization

    init(model: Model, orientation: Orientation) {
        self.model = model
        self.orientation = orientation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = PassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupFrontTorch()
        setupChat()
        setupSwiftUIIslands()
        setupCombineSubscriptions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        frontTorchGradient?.frame = frontTorchView.bounds
    }

    // MARK: - Front Torch

    private func setupFrontTorch() {
        frontTorchView.backgroundColor = .white
        frontTorchView.isHidden = true
        frontTorchView.isUserInteractionEnabled = false
        frontTorchView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(frontTorchView)

        NSLayoutConstraint.activate([
            frontTorchView.topAnchor.constraint(equalTo: view.topAnchor),
            frontTorchView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frontTorchView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frontTorchView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.colors = [UIColor.clear.cgColor, UIColor.white.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        frontTorchView.layer.addSublayer(gradient)
        frontTorchGradient = gradient
    }

    // MARK: - Chat

    private func setupChat() {
        guard let model = model else { return }

        // Container
        chatContainerView.translatesAutoresizingMaskIntoConstraints = false
        chatContainerView.isUserInteractionEnabled = false // default: non-interactive
        view.addSubview(chatContainerView)

        NSLayoutConstraint.activate([
            chatContainerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            chatContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            chatContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Collection view with flow layout
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 1
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize

        chatCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        chatCollectionView.backgroundColor = .clear
        chatCollectionView.showsVerticalScrollIndicator = false
        chatCollectionView.translatesAutoresizingMaskIntoConstraints = false
        chatCollectionView.delegate = self
        chatContainerView.addSubview(chatCollectionView)

        // Apply inverted transform for "newest at bottom" (default: newMessagesAtTop = false)
        updateChatTransforms()

        // Chat collection view constraints — sized by chatSettings fractions
        let chatSettings = model.database.chat
        chatBottomClearance = chatCollectionView.bottomAnchor.constraint(
            equalTo: chatContainerView.bottomAnchor,
            constant: orientation.isPortrait ? -85 : -chatSettings.bottomPoints
        )

        NSLayoutConstraint.activate([
            chatCollectionView.leadingAnchor.constraint(equalTo: chatContainerView.leadingAnchor),
            chatBottomClearance,
        ])

        // Width and height as fractions of container
        updateChatSizeConstraints()

        // Register cells
        chatCollectionView.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.reuseIdentifier)
        chatCollectionView.register(ChatRedLineCell.self, forCellWithReuseIdentifier: ChatRedLineCell.reuseIdentifier)

        // Data source
        chatDataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: chatCollectionView) {
            [weak self] collectionView, indexPath, postId in
            guard let self, let post = self.postLookup[postId], let model = self.model else {
                return collectionView.dequeueReusableCell(withReuseIdentifier: ChatRedLineCell.reuseIdentifier, for: indexPath)
            }

            if post.user != nil {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
                // Apply inverted content transform
                if !model.database.chat.newMessagesAtTop {
                    cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
                } else {
                    cell.contentView.transform = .identity
                }
                let showDeleted = model.database.chat.showDeletedMessages
                if post.state.deleted && !showDeleted {
                    // Hidden — return empty cell
                    return cell
                }
                cell.configure(with: post, settings: model.database.chat, moreThanOnePlatform: model.chat.moreThanOneStreamingPlatform)
                return cell
            } else {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatRedLineCell.reuseIdentifier, for: indexPath)
                if !model.database.chat.newMessagesAtTop {
                    cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
                } else {
                    cell.contentView.transform = .identity
                }
                return cell
            }
        }

        // Paused banner
        chatPausedBanner.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        chatPausedBanner.layer.cornerRadius = 10
        chatPausedBanner.clipsToBounds = true
        chatPausedBanner.isHidden = true
        chatPausedBanner.isUserInteractionEnabled = false
        chatPausedBanner.translatesAutoresizingMaskIntoConstraints = false
        chatContainerView.addSubview(chatPausedBanner)

        chatPausedLabel.font = .boldSystemFont(ofSize: 14)
        chatPausedLabel.textColor = .white
        chatPausedLabel.translatesAutoresizingMaskIntoConstraints = false
        chatPausedBanner.addSubview(chatPausedLabel)

        NSLayoutConstraint.activate([
            chatPausedBanner.leadingAnchor.constraint(equalTo: chatContainerView.leadingAnchor, constant: 5),
            chatPausedBanner.bottomAnchor.constraint(equalTo: chatCollectionView.bottomAnchor, constant: -2),
            chatPausedLabel.topAnchor.constraint(equalTo: chatPausedBanner.topAnchor, constant: 5),
            chatPausedLabel.bottomAnchor.constraint(equalTo: chatPausedBanner.bottomAnchor, constant: -5),
            chatPausedLabel.leadingAnchor.constraint(equalTo: chatPausedBanner.leadingAnchor, constant: 10),
            chatPausedLabel.trailingAnchor.constraint(equalTo: chatPausedBanner.trailingAnchor, constant: -10),
        ])
    }

    private func updateChatTransforms() {
        guard let model = model else { return }
        let newMessagesAtTop = model.database.chat.newMessagesAtTop
        chatCollectionView.transform = newMessagesAtTop ? .identity : CGAffineTransform(scaleX: 1, y: -1)

        let mirrored = model.database.chat.mirrored
        chatContainerView.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    private func updateChatSizeConstraints() {
        guard let model = model else { return }
        let chatSettings = model.database.chat

        // Remove old constraints
        chatWidthMultiplier?.isActive = false
        chatHeightMultiplier?.isActive = false

        let widthFactor = orientation.isPortrait ? chatSettings.width : chatSettings.width * 0.95
        let heightFactor = chatSettings.height

        let w = chatCollectionView.widthAnchor.constraint(equalTo: chatContainerView.widthAnchor, multiplier: widthFactor)
        let h = chatCollectionView.heightAnchor.constraint(equalTo: chatContainerView.heightAnchor, multiplier: heightFactor)
        w.isActive = true
        h.isActive = true
        chatWidthMultiplier = w
        chatHeightMultiplier = h
    }

    // MARK: - SwiftUI Islands

    private func setupSwiftUIIslands() {
        guard let model = model else { return }
        let leadingPad = leadingPadding()
        let tapTargetExpansion: CGFloat = 20

        // Left status
        let leftView = LeftStatusContentView(model: model, database: model.database)
            .environmentObject(model)
        let leftVC = UIHostingController(rootView: AnyView(leftView))
        leftVC.view.backgroundColor = .clear
        leftVC.view.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.0, *) { leftVC.sizingOptions = .intrinsicContentSize }
        addChild(leftVC)
        view.addSubview(leftVC.view)
        leftVC.didMove(toParent: self)

        let leftLeading = leftVC.view.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: leadingPad - tapTargetExpansion
        )
        NSLayoutConstraint.activate([
            leftVC.view.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16 - tapTargetExpansion
            ),
            leftLeading,
        ])
        leftStatusHostingVC = leftVC
        leftLeadingConstraint = leftLeading

        // Right top status
        let rightTopView = RightTopStatusContentView(model: model, database: model.database)
            .environmentObject(model)
        let rightTopVC = UIHostingController(rootView: AnyView(rightTopView))
        rightTopVC.view.backgroundColor = .clear
        rightTopVC.view.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.0, *) { rightTopVC.sizingOptions = .intrinsicContentSize }
        addChild(rightTopVC)
        view.addSubview(rightTopVC.view)
        rightTopVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            rightTopVC.view.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16 - tapTargetExpansion
            ),
            rightTopVC.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -16
            ),
        ])
        rightTopStatusHostingVC = rightTopVC

        // Right bottom controls (SwiftUI island — rarely visible)
        let rightBottomView = RightOverlayBottomView(
            show: model.database.show,
            streamOverlay: model.streamOverlay,
            zoom: model.zoom,
            width: view.bounds.width
        ).environmentObject(model)
        let rightBottomVC = UIHostingController(rootView: AnyView(rightBottomView))
        rightBottomVC.view.backgroundColor = .clear
        rightBottomVC.view.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.0, *) { rightBottomVC.sizingOptions = .intrinsicContentSize }
        addChild(rightBottomVC)
        view.addSubview(rightBottomVC.view)
        rightBottomVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            rightBottomVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            rightBottomVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        rightBottomHostingVC = rightBottomVC

        // Debug overlay
        let debugView = StreamDebugOverlayView(debugOverlay: model.debugOverlay)
            .environmentObject(model)
        let debugVC = UIHostingController(rootView: AnyView(debugView))
        debugVC.view.backgroundColor = .clear
        debugVC.view.isUserInteractionEnabled = false
        debugVC.view.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.0, *) { debugVC.sizingOptions = .intrinsicContentSize }
        addChild(debugVC)
        view.addSubview(debugVC.view)
        debugVC.didMove(toParent: self)

        let debugLeading = debugVC.view.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: leadingPad
        )
        NSLayoutConstraint.activate([
            debugVC.view.topAnchor.constraint(equalTo: leftVC.view.bottomAnchor, constant: 4),
            debugLeading,
        ])
        debugHostingVC = debugVC
        debugLeadingConstraint = debugLeading
    }

    private func leadingPadding() -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad || orientation.isPortrait {
            return 15
        } else {
            return 0
        }
    }

    // MARK: - Combine Subscriptions

    private func setupCombineSubscriptions() {
        guard let model = model else { return }
        let chatSettings = model.database.chat
        let chat = model.chat
        let streamOverlay = model.streamOverlay

        // Front torch visibility
        Publishers.CombineLatest(streamOverlay.$isTorchOn, streamOverlay.$isFrontCameraSelected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] torch, front in
                self?.frontTorchView.isHidden = !(torch && front)
            }
            .store(in: &cancellables)

        // Chat visibility
        Publishers.CombineLatest(model.$showingPanel, chatSettings.$enabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] panel, enabled in
                self?.chatContainerView.isHidden = (panel == .chat) || !enabled
            }
            .store(in: &cancellables)

        // Chat interactivity
        chat.$interactiveChat
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interactive in
                self?.chatContainerView.isUserInteractionEnabled = interactive
            }
            .store(in: &cancellables)

        // Chat data
        chat.$posts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] posts in
                self?.applyChatSnapshot(posts: posts)
            }
            .store(in: &cancellables)

        // Chat paused banner
        Publishers.CombineLatest(chat.$paused, chat.$pausedPostsCount)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused, count in
                self?.chatPausedBanner.isHidden = !paused
                self?.chatPausedLabel.text = String(localized: "Chat paused: \(count) new messages")
            }
            .store(in: &cancellables)

        // Chat size settings
        Publishers.CombineLatest(chatSettings.$height, chatSettings.$width)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateChatSizeConstraints()
            }
            .store(in: &cancellables)

        // Chat transform settings
        Publishers.CombineLatest(chatSettings.$newMessagesAtTop, chatSettings.$mirrored)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateChatTransforms()
                self?.chatCollectionView.reloadData()
            }
            .store(in: &cancellables)

        // Chat appearance settings — reload all cells
        Publishers.MergeMany(
            chatSettings.$fontSize.map { _ in () }.eraseToAnyPublisher(),
            chatSettings.$boldUsername.map { _ in () }.eraseToAnyPublisher(),
            chatSettings.$boldMessage.map { _ in () }.eraseToAnyPublisher(),
            chatSettings.$backgroundColorEnabled.map { _ in () }.eraseToAnyPublisher(),
            chatSettings.$shadowColorEnabled.map { _ in () }.eraseToAnyPublisher(),
            chatSettings.$animatedEmotes.map { _ in () }.eraseToAnyPublisher(),
            chatSettings.$timestampColorEnabled.map { _ in () }.eraseToAnyPublisher(),
            chatSettings.$badges.map { _ in () }.eraseToAnyPublisher(),
            chatSettings.$platform.map { _ in () }.eraseToAnyPublisher(),
            chatSettings.$showDeletedMessages.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            self?.chatCollectionView.reloadData()
        }
        .store(in: &cancellables)

        // Scroll to bottom triggers
        chat.$triggerScrollToBottom
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.chatCollectionView.setContentOffset(.zero, animated: false)
            }
            .store(in: &cancellables)

        // Orientation changes
        orientation.$isPortrait
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLayoutForOrientation()
            }
            .store(in: &cancellables)
    }

    // MARK: - Chat Data

    private func applyChatSnapshot(posts: Deque<ChatPost>) {
        // Update lookup
        postLookup.removeAll(keepingCapacity: true)
        for post in posts {
            postLookup[post.id] = post
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(posts.map(\.id), toSection: 0)
        chatDataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Orientation

    private func updateLayoutForOrientation() {
        guard let model = model else { return }
        let chatSettings = model.database.chat
        let leadingPad = leadingPadding()
        let tapTargetExpansion: CGFloat = 20

        // Update chat bottom clearance
        chatBottomClearance.constant = orientation.isPortrait ? -85 : -chatSettings.bottomPoints

        // Update leading padding for left status and debug
        leftLeadingConstraint?.constant = leadingPad - tapTargetExpansion
        debugLeadingConstraint?.constant = leadingPad

        // Update chat size
        updateChatSizeConstraints()

        view.setNeedsLayout()
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension StreamOverlayViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // Use the collection view's width for cells, let height be automatic
        let width = collectionView.bounds.width
        guard let postId = chatDataSource.itemIdentifier(for: indexPath),
              let post = postLookup[postId] else {
            return CGSize(width: width, height: 6) // red line
        }
        if post.user == nil {
            return CGSize(width: width, height: 6)
        }
        // Estimate height based on content — use automatic sizing
        return CGSize(width: width, height: 1) // Will be overridden by auto-sizing
    }
}

// MARK: - UIScrollViewDelegate (Pause/Unpause)

extension StreamOverlayViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let model = model, model.chat.interactiveChat else { return }

        // In the inverted collection view, contentOffset.y ≈ 0 means
        // we're at the "bottom" (newest messages visible)
        let atBottom = scrollView.contentOffset.y < 20

        if atBottom && model.chat.paused {
            model.endOfChatReachedWhenPaused()
        } else if !atBottom && !model.chat.paused && !model.chat.posts.isEmpty {
            model.pauseChat()
        }
    }
}
