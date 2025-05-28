//
//  LiveChatView.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import SwiftUI
import NostrSDK
import Combine
import Kingfisher

struct LiveChatView: View {
    @EnvironmentObject var appState: AppState

    private let liveActivitiesEvent: LiveActivitiesEvent
    
    private let pageSize: Int = 50
    private let topHeaderHeight: CGFloat = 50.0
    
    // Create the view model as a StateObject.
    @StateObject private var viewModel: ViewModel
    
    @ObservedObject private var keyboardObserver = KeyboardObserver()
    @State private var safeAreaInsets = EdgeInsets()
    
    // Chat state
    @State private var liveChatMessages: [LiveChatMessageEvent] = []
    @State private var cancellables = Set<AnyCancellable>()

    @State private var autoScrollEnabled: Bool = true
    @State private var isPaginating: Bool = false
    @State private var isLoadingPage: Bool = false
    @State private var hasMoreMessages: Bool = true

    @State private var scrollOffset: CGFloat = 0
    @State private var lastScrollOffset: CGFloat = 0
    
    @State private var hideTopBar: Bool = false
    
    @State private var pubkeysToPullMetadata = Set<String>()
    @State private var metadataPullCancellable: AnyCancellable?

    init(liveActivitiesEvent: LiveActivitiesEvent) {
        self.liveActivitiesEvent = liveActivitiesEvent
        _viewModel = StateObject(wrappedValue: ViewModel(liveActivitiesEvent: liveActivitiesEvent))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top header
                topHeader
                    .offset(y: hideTopBar ? -topHeaderHeight*2 : 0)
                    .zIndex(1)
                
                // Chat messages
                chatMessagesView
                
                // Chat input bar
                chatInputBar
            }
            .padding(.bottom, keyboardObserver.keyboardHeight > 0 ? keyboardObserver.keyboardHeight : geometry.safeAreaInsets.bottom + max(20, geometry.safeAreaInsets.bottom / 2))
            .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
            .onAppear {
                safeAreaInsets = geometry.safeAreaInsets
                viewModel.appState = appState
                subscribeToLiveChat()
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .dismissKeyboardOnTap()
    }
    
    private var chatMessagesView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("livechat_scroll")).minY
                            )
                    }
                    .frame(height: 0)
                    
                    ForEach(Array(liveChatMessages.enumerated()), id: \.offset) { index, message in
                        chatMessageRow(message: message, index: index)
                    }
                    
                    // Spacer to ensure last message is visible above input
                    Color.clear
                        .frame(height: 20)
                        .id("chat_list_bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .coordinateSpace(name: "livechat_scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
                handleScrollOffset(newOffset)
            }
            // Auto-scroll to the bottom when new messages arrive or keyboard appears
            .onChange(of: liveChatMessages) { _, messages in
                if autoScrollEnabled && !isPaginating && !messages.isEmpty {
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollProxy.scrollTo("chat_list_bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: keyboardObserver.keyboardHeight) { _, keyboardHeight in
                print("Keyboard height changed to: \(keyboardHeight)")
//                if keyboardHeight > 0 && autoScrollEnabled {
//                    // Small delay to ensure the view has adjusted to keyboard
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                        withAnimation(.easeOut(duration: 0.3)) {
//                            scrollProxy.scrollTo("chat_list_bottom", anchor: .bottom)
//                        }
//                    }
//                }
            }
        }
    }
    
    private func chatMessageRow(message: LiveChatMessageEvent, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProfilePicView(
                pubkey: message.pubkey,
                size: 40,
                profile: appState.metadataEvents[message.pubkey]?.userMetadata
            )
            
            VStack(alignment: .leading, spacing: 4) {
                ProfileNameView(publicKeyHex: message.pubkey)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .id(index)
        .onAppear {
            if index == 0, hasMoreMessages, !isLoadingPage {
                loadMoreMessages()
            }
        }
    }
    
    private func handleScrollOffset(_ newOffset: CGFloat) {
        DispatchQueue.main.async {
            let delta = newOffset - lastScrollOffset
            if delta < -15 {
                // Scrolling down: show the top bar.
                hide_top_bar(false)
            } else if delta > 15 {
                // Pause autoscroll when user scrolls up
                autoScrollEnabled = false
                // Scrolling up: hide the top bar.
                hide_top_bar(true)
            }
            lastScrollOffset = newOffset
        }
    }
    
    private var chatInputBar: some View {
        VStack(spacing: 0) {
            // Subtle separator
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
            
            HStack(spacing: 12) {
                TextField("Type a message...", text: $viewModel.messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...4)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                                      Color(.systemGray4) : Color.purple)
                        )
                }
                .disabled(viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .ignoresSafeArea(.keyboard)
    }
    
    private func sendMessage() {
        guard !viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        if viewModel.saveLiveChatMessageEvent() {
            viewModel.messageText = ""
            autoScrollEnabled = true
        }
    }
    
    private var topHeader: some View {
        HStack(spacing: 12) {
            if let publicKeyHex = liveActivitiesEvent.participants.first(where: { $0.role == "host" })?.pubkey?.hex {
                ProfilePicView(pubkey: publicKeyHex, size: 45, profile: appState.metadataEvents[publicKeyHex]?.userMetadata)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(liveActivitiesEvent.title ?? "no title")
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(liveActivitiesEvent.status == .ended ? Color.gray : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(liveActivitiesEvent.status == .ended ? "ENDED" : "LIVE")
                        .font(.caption)
                        .foregroundColor(liveActivitiesEvent.status == .ended ? .gray : .red)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            zapAmount
        }
        .frame(height: topHeaderHeight)
        .padding(.horizontal, 16)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    private var zapAmount: some View {
        HStack(spacing: 4) {
            let coordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value ?? ""
            let zapAmount = (appState.eventZapTotals[coordinates] ?? 0) / 1000
            
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundColor(.orange)
            
            Text("\(zapAmount.formatted()) \(pluralize("sat", count: zapAmount))")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(8)
    }
    
    /// Call this method with `true` to slide the top bar offscreen, or `false` to reveal it.
    func hide_top_bar(_ shouldHide: Bool) {
        withAnimation(.easeInOut(duration: 0.25)) {
            hideTopBar = shouldHide
        }
    }
    
    // MARK: - Live Chat Subscription and Pagination
    
    private func subscribeToLiveChat() {
        appState.subscribeToLiveChat(for: liveActivitiesEvent)
        
        let coordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value ?? ""
        
        // Subscribe to incoming live chat messages.
        appState.$liveChatMessagesEvents
            .map { $0[coordinates] ?? [] }
            .receive(on: DispatchQueue.main)
            .sink { incomingMessages in
                if liveChatMessages.isEmpty {
                    // On first appearance, take the latest page and sort it.
                    let latestPage = Array(incomingMessages.suffix(pageSize))
                    liveChatMessages = latestPage.sorted { $0.createdAt < $1.createdAt }
                    hasMoreMessages = incomingMessages.count > pageSize
                } else {
                    // Try to find the index of the last visible message in the incoming batch.
                    if let lastMessage = liveChatMessages.last,
                       let lastIndex = incomingMessages.firstIndex(where: { $0.id == lastMessage.id }),
                       lastIndex + 1 < incomingMessages.count {
                        // Get only the new messages.
                        let newMessages = Array(incomingMessages[(lastIndex + 1)...])
                        
                        // If the new messages are already in order, simply append.
                        if let firstNew = newMessages.first, lastMessage.createdAt <= firstNew.createdAt {
                            liveChatMessages.append(contentsOf: newMessages)
                        } else {
                            // Otherwise, sort the new messages and merge them.
                            let sortedNewMessages = newMessages.sorted { $0.createdAt < $1.createdAt }
                            liveChatMessages = mergeSortedMessages(liveChatMessages, sortedNewMessages)
                        }
                    }
                }
                
                // Accumulate pubkeys.
                incomingMessages.forEach { message in
                    pubkeysToPullMetadata.insert(message.pubkey)
                }
                
                // Debounce the metadata pull to avoid calling it too frequently.
                scheduleMetadataPull()
            }
            .store(in: &cancellables)
    }
    
    private func scheduleMetadataPull() {
        // Cancel any previous scheduled call.
        metadataPullCancellable?.cancel()
        // Schedule a new call after 0.5 seconds of inactivity.
        metadataPullCancellable = Just(())
            .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { _ in
                let pubkeysArray = Array(self.pubkeysToPullMetadata)
                self.appState.pullMissingEventsFromPubkeysAndFollows(pubkeysArray)
                // Optionally clear the set if you no longer need the pubkeys.
                self.pubkeysToPullMetadata.removeAll()
            }
    }
    
    private func loadMoreMessages() {
        guard let coordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value,
              let allMessages = appState.liveChatMessagesEvents[coordinates],
              let currentFirstMessage = liveChatMessages.first,
              let currentFirstIndex = allMessages.firstIndex(of: currentFirstMessage)
        else {
            return
        }
        
        isLoadingPage = true
        isPaginating = true  // Mark that we are paginating so auto-scroll won't trigger.
        
        // Determine how many messages precede the current first (oldest) message.
        let remainingMessagesCount = currentFirstIndex // because allMessages is sorted oldest → newest
        if remainingMessagesCount > 0 {
            let start = max(0, remainingMessagesCount - pageSize)
            let olderPage = allMessages[start..<remainingMessagesCount]
            // Prepend the older messages.
            liveChatMessages.insert(contentsOf: olderPage, at: 0)
            hasMoreMessages = (start > 0)
        } else {
            hasMoreMessages = false
        }
        isLoadingPage = false
        
        // Reset the paginating flag on the next runloop cycle.
        DispatchQueue.main.async {
            self.isPaginating = false
        }
    }
    
    /// A helper function to merge two sorted arrays.
    func mergeSortedMessages(_ left: [LiveChatMessageEvent],
                             _ right: [LiveChatMessageEvent]) -> [LiveChatMessageEvent] {
        var merged: [LiveChatMessageEvent] = []
        merged.reserveCapacity(left.count + right.count)
        
        var i = 0, j = 0
        while i < left.count && j < right.count {
            let leftMsg = left[i]
            let rightMsg = right[j]
            
            // Compare based on createdAt
            if leftMsg.createdAt < rightMsg.createdAt {
                // Only add if last message in merged is not the same (by id)
                if merged.last?.id != leftMsg.id { merged.append(leftMsg) }
                i += 1
            } else if leftMsg.createdAt > rightMsg.createdAt {
                if merged.last?.id != rightMsg.id { merged.append(rightMsg) }
                j += 1
            } else { // createdAt is equal; check IDs
                if leftMsg.id == rightMsg.id {
                    // Same message – add one instance.
                    if merged.last?.id != leftMsg.id { merged.append(leftMsg) }
                    i += 1
                    j += 1
                } else {
                    // Same timestamp but different messages – add both.
                    if merged.last?.id != leftMsg.id { merged.append(leftMsg) }
                    i += 1
                    if merged.last?.id != rightMsg.id { merged.append(rightMsg) }
                    j += 1
                }
            }
        }
        
        // Append remaining messages from left.
        while i < left.count {
            let msg = left[i]
            if merged.last?.id != msg.id { merged.append(msg) }
            i += 1
        }
        // Append remaining messages from right.
        while j < right.count {
            let msg = right[j]
            if merged.last?.id != msg.id { merged.append(msg) }
            j += 1
        }
        
        return merged
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
