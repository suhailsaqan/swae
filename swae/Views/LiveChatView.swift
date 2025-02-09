//
//  LiveChatView.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import SwiftUI
import NostrSDK
import Combine

struct LiveChatView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isFocused: Bool

    private let liveActivitiesEvent: LiveActivitiesEvent
    @State private var liveChatMessages: [LiveChatMessageEvent] = []
    @State private var cancellables = Set<AnyCancellable>()
    
    // When auto-scroll is enabled the view scrolls to the newest (bottom) message.
    @State private var autoScrollEnabled: Bool = true
    // Flag to indicate whether we are in the process of paginating older messages.
    @State private var isPaginating: Bool = false

    // Pagination state – adjust pageSize as needed.
    private let pageSize = 50
    @State private var isLoadingPage: Bool = false
    @State private var hasMoreMessages: Bool = true

    init(liveActivitiesEvent: LiveActivitiesEvent) {
        self.liveActivitiesEvent = liveActivitiesEvent
    }

    var body: some View {
        GeometryReader { geoProxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(liveChatMessages.enumerated()), id: \.offset) { index, message in
                            Text(message.content)
                                .padding(5)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                                .id(index)  // Unique id based on the index.
                                .onAppear {
                                    // Trigger pagination when the first (oldest) message appears.
                                    if index == 0, hasMoreMessages, !isLoadingPage {
                                        loadMoreMessages()
                                    }
                                }
                        }
                    }
                    .onChange(of: liveChatMessages) { messages in
                        // Only auto-scroll if not paginating and auto-scroll is enabled.
                        if autoScrollEnabled, !isPaginating, let lastIndex = messages.indices.last {
                            DispatchQueue.main.async {
                                withAnimation {
                                    scrollProxy.scrollTo(lastIndex, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                // Show a “Resume Scroll” button if the user has scrolled up.
                .overlay(alignment: .bottom) {
                    if !autoScrollEnabled,
                       !liveChatMessages.isEmpty,
                       let lastMessage = liveChatMessages.last {
                        Button("Resume Scroll") {
                            autoScrollEnabled = true
                            // Scroll to the bottom when resuming.
                            DispatchQueue.main.async {
                                withAnimation {
                                    scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 5)
                    }
                }
                // Disable auto-scroll if the user is dragging upward.
                .gesture(
                    DragGesture().onChanged { value in
                        if value.translation.height > 0 {
                            autoScrollEnabled = false
                        }
                    }
                )
                .onAppear {
                    appState.subscribeToLiveChat(for: liveActivitiesEvent)
                    
                    let coordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value ?? ""
                    
                    // Subscribe to incoming live chat messages.
                    // (Assume that appState.liveChatMessagesEvents[coordinates] is a full, chronologically sorted array.)
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
                        }
                        .store(in: &cancellables)
                }
            }
        }
        .onTapGesture {
            isFocused = false
        }
        .onDisappear {
            appState.unsubscribeFromLiveChat(for: liveActivitiesEvent)
            cancellables.removeAll()
        }
    }
    
    /// Loads an older page of messages from your full history.
    private func loadMoreMessages() {
        guard let coordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value,
              let allMessages = appState.liveChatMessagesEvents[coordinates],
              let currentFirstMessage = liveChatMessages.first,
              let currentFirstIndex = allMessages.firstIndex(of: currentFirstMessage)
        else {
            return
        }
        
        isLoadingPage = true
        isPaginating = true  // Mark that we are paginating so auto-scroll won’t trigger.
        
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
