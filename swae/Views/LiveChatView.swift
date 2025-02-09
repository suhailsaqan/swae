//
//  ChatView.swift
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
    @State private var text = ""

    private let liveActivitiesEvent: LiveActivitiesEvent
    @State private var liveChatMessages: [LiveChatMessageEvent] = []
    @State private var cancellables = Set<AnyCancellable>()

    @State var chatBoxMessage: String = ""
    @State var autoScrollEnabled: Bool = true

    init(liveActivitiesEvent: LiveActivitiesEvent) {
        self.liveActivitiesEvent = liveActivitiesEvent
    }

    var body: some View {
        GeometryReader { geoProxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10.0) {
                        ForEach(liveChatMessages, id: \.self) { message in
                            Text(message.content)
                                .padding(5)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .onChange(of: liveChatMessages) { messages in
                        if autoScrollEnabled, let lastMessage = messages.last {
                            scrollProxy.scrollTo(lastMessage, anchor: .bottom)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if !autoScrollEnabled, !liveChatMessages.isEmpty,
                       let lastMessage = liveChatMessages.last {
                        Button("Resume Scroll") {
                            autoScrollEnabled = true
                            scrollProxy.scrollTo(lastMessage, anchor: .bottom)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 5.0)
                    }
                }
            }
        }
        .onTapGesture {
            isFocused = false
        }
        .gesture(
            DragGesture().onChanged { value in
                if value.translation.height > 0 {
                    autoScrollEnabled = false
                }
            }
        )
        .onAppear {
            appState.subscribeToLiveChat(for: liveActivitiesEvent)
            
            let key = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value ?? ""
            
            // Listen for updates to the relevant live chat messages
            appState.$liveChatMessagesEvents
                .map { $0[key] ?? [] }
                .receive(on: DispatchQueue.main)
                .sink { messages in
                    liveChatMessages = messages
                }
                .store(in: &cancellables)
        }
        .onDisappear {
            appState.unsubscribeFromLiveChat(for: liveActivitiesEvent)
            cancellables.removeAll()
        }
    }
}
