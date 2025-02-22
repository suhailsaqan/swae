//
//  VideoListView.swift
//  swae
//
//  Created by Suhail Saqan on 11/24/24.
//

import Kingfisher
import NostrSDK
import SwiftData
import SwiftUI

struct VideoListView: View, MetadataCoding {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var orientationMonitor: OrientationMonitor

    @State var eventListType: EventListType
    @State private var timeTabFilter: TimeTabs = .past
    @State private var showAllEvents: Bool = true
    @State private var filteredEvents: [LiveActivitiesEvent] = []
    @ObservedObject private var searchViewModel = SearchViewModel()

    // Event selection and detail view state
    @State var selectedEvent: LiveActivitiesEvent?
    @State var showDetailPage: Bool = false

    // UI animation states
    @Namespace var animation
    @State var animateView: Bool = false
    @State var animateContent: Bool = false

    // Scroll and layout states
    @State private var scrollOffset: CGFloat = 0
    @State private var lastScrollOffset: CGFloat = 0

    // Section expansion states
    @State private var isProfilesSectionExpanded: Bool = false

    // Pagination states
    @State private var currentPage: Int = 0
    @State private var isLoadingMore: Bool = false
    @State private var hasMoreData: Bool = true

    // Topbar
    @State private var selectedIndex: Int = 1
    @State private var hideTopBar: Bool = false


    var body: some View {
        customTabView()
            .edgesIgnoringSafeArea([.bottom])
            .onAppear {
                filteredEvents = events(timeTabFilter)
            }
            .onChange(of: appState.liveActivitiesEvents) { _, newValue in
                filteredEvents = events(timeTabFilter)
            }
            .onChange(of: timeTabFilter) { _, newValue in
                filteredEvents = events(newValue)
            }
//            .searchable(text: $searchViewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "search here")
            .overlay {
                if let currentItem = selectedEvent, showDetailPage {
                    DetailView(item: currentItem)
//                        .edgesIgnoringSafeArea([.bottom])
//                        .ignoresSafeArea(.container, edges: orientationMonitor.isLandscape ? [.top, .bottom] : [.leading, .trailing])
                }
            }
//            .background(alignment: .top) {
//                Rectangle()
//                    .fill(Color(UIColor.systemBackground))
//                    .frame(height: animateView ? nil : 250, alignment: .top)
//                    .scaleEffect(animateView ? 1 : 0.93)
//                    .opacity(animateView ? 1 : 0)
//                    .ignoresSafeArea()
//            }
    }
    
    /// Computes the total height of our top bar: safe area inset + content height.
    var topBarHeight: CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.top
        }
        return 0
    }
    
    private func customTabView() -> some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedIndex) {
                Text("hi")
                    .tag(0)
                vidListView()
                    .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .edgesIgnoringSafeArea([.top, .bottom])
            
            TopTabBar(selectedIndex: $selectedIndex)
                .frame(height: topBarHeight*2)
                .offset(y: hideTopBar ? -topBarHeight*2 : 0) // Slide the bar up (hidden) by offsetting it by its full height.
                .edgesIgnoringSafeArea([.top])
        }
    }
    
    struct TopTabBar: View {
        @Environment(\.colorScheme) var colorScheme
        @Binding var selectedIndex: Int

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    GlassView(style: .regular)
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .black.opacity(1), location: 0.0),
                                    .init(color: .black.opacity(1), location: 0.80),
                                    .init(color: .clear, location: 1),
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    VStack {
                        HStack {
                            TabButton(title: "Following", tag: 0, selectedIndex: $selectedIndex)
                            TabButton(title: "For You", tag: 1, selectedIndex: $selectedIndex)
                        }
                        .padding(.horizontal, 30)
                        
                        Indicator(selectedIndex: $selectedIndex)
                            .padding(.horizontal, 30)
                            .padding(.vertical, -10)
                        
                        Spacer()
                    }
                    .offset(y: geometry.size.height / 2) // Offset so the top edge of the VStack starts at mid-height.
                }
            }
        }
    }
    
    struct TabButton: View {
        let title: String
        let tag: Int
        @Binding var selectedIndex: Int

        var body: some View {
            Button {
                // Animate the change when tapped.
                withAnimation {
                    selectedIndex = tag
                }
            } label: {
                Text(title)
                    .foregroundColor(selectedIndex == tag ? .purple : Color(.label))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    /// A sliding capsule indicator that sits under the active tab.
    struct Indicator: View {
        @Binding var selectedIndex: Int
        
        var body: some View {
            GeometryReader { geo in
                // Each button occupies half of the available width.
                let buttonWidth = geo.size.width / 2
                Capsule()
                    .fill(Color.purple)
                    .frame(width: 60, height: 2)
                // Calculate the horizontal offset for the capsule.
                    .offset(x: selectedIndex == 0
                            ? (buttonWidth - 60) / 2
                            : buttonWidth + (buttonWidth - 60) / 2)
                    .animation(.easeInOut, value: selectedIndex)
            }
        }
    }
    
    private func vidListView(/*scrollViewProxy: ScrollViewProxy*/) -> some View {
        VStack {
//            CustomSegmentedPicker(selectedTimeTab: $timeTabFilter) {
//                withAnimation {
//                    scrollViewProxy.scrollTo("event-list-view-top")
//                }
//            }
//            .padding([.leading, .trailing], 16)
            
//            if eventListType == .all && appState.publicKey != nil {
//                Button(
//                    action: {
//                        showAllEvents.toggle()
//                    },
//                    label: {
//                        Image(systemName: "figure.stand.line.dotted.figure.stand")
//                            .resizable()
//                            .scaledToFit()
//                            .frame(width: 30)
//                            .foregroundStyle(showAllEvents ? .secondary : .primary)
//                    }
//                )
//                .frame(maxWidth: .infinity, alignment: .trailing)
//                .padding([.leading, .trailing], 16)
//            }
            
            if filteredEvents.isEmpty {
                VStack {
                    Spacer()
                    Text("its boring here")
                        .font(.title)
                        .foregroundColor(.purple)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        EmptyView().id("event-list-view-top")
                        
                        Color.clear
                            .frame(height: topBarHeight)
                            .background(
                                GeometryReader { proxy -> Color in
                                    // Read the minY value of the content within the named coordinate space.
                                    let newOffset = proxy.frame(in: .named("scroll")).minY
                                    // Use DispatchQueue.main.async to avoid updating state during view updates.
                                    DispatchQueue.main.async {
                                        let delta = newOffset - lastScrollOffset
                                        if delta < -15 {
                                            // Scrolling down: hide the tabbar.
                                            withAnimation(.linear(duration:0.15)) {
                                                notify(.display_tabbar(false))
                                            }
                                            hide_topbar(true)
                                        } else if delta > 15 {
                                            // Scrolling up: show the tabbar.
                                            withAnimation(.linear(duration:0.15)) {
                                                notify(.display_tabbar(true))
                                            }
                                            hide_topbar(false)
                                        }
                                        lastScrollOffset = newOffset
                                    }
                                    return Color.clear
                                }
                            )
                        
                        ForEach(filteredEvents.prefix(currentPage * 10), id: \.self) { event in
                            Button {
//                                withAnimation(
//                                    .interactiveSpring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.7)
//                                ) {
//                                    selectedEvent = event
//                                    showDetailPage = true
//                                    animateView = true
//                                    notify(.display_tabbar(false))
//                                }
//                                withAnimation(
//                                    .interactiveSpring(response: 0.6,
//                                                       dampingFraction: 0.7,
//                                                       blendDuration: 0.7)
//                                    .delay(0.05)
//                                ) {
//                                    animateContent = true
//                                }
                                appState.playerConfig.selectedLiveActivitiesEvent = event
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    appState.playerConfig.showMiniPlayer = true
                                }
                            } label: {
                                CardView(item: event)
                                    .scaleEffect(selectedEvent?.id == event.id && showDetailPage ? 1 : 0.93)
                            }
                            .buttonStyle(ScaledButtonStyle())
                            .opacity(showDetailPage ? (selectedEvent?.id == event.id ? 1 : 0) : 1)
                        }
                        
                        // Loading indicator view
                        if isLoadingMore {
                            VStack(alignment: .leading) {
                                Spacer()
                                LoadingCircleView(showBackground: false)
                                Spacer()
                            }
                            .frame(height: 100)
                        } else {
                            GeometryReader { proxy -> Color in
                                let minY = proxy.frame(in: .named("scroll")).minY
                                let height = UIScreen.main.bounds.height
                                if !filteredEvents.isEmpty && minY < height && hasMoreData {
                                    DispatchQueue.main.async {
                                        loadMoreEvents()
                                    }
                                }
                                return Color.clear
                            }
                            .frame(height: 0)
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
                .refreshable {
                    appState.refresh(hardRefresh: true)
                }
            }
        }
    }

    @ViewBuilder
    private func CardView(item: LiveActivitiesEvent, isDetailPage: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if !showDetailPage && !(selectedEvent?.id == item.id) {
                ZStack(alignment: .topLeading) {
                    GeometryReader { proxy in
                        let size = proxy.size

                        KFImage.url(item.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: size.width,
                                height: size.height
                            )
                            .clipShape(
                                CustomCorner(
                                    corners: [
                                        .bottomLeft, .bottomRight, .topLeft, .topRight,
                                    ], radius: 10))
                    }
                    .frame(height: 250)
                    .offset(y: selectedEvent?.id == item.id && animateView ? safeArea().top : 0)
                }
            } else if showDetailPage && (selectedEvent?.id == item.id) && isDetailPage {
                HStack {
                    if let url = item.recording ?? item.streaming {
                        GeometryReader { proxy in
                            let size = proxy.size
                            let safeArea = proxy.safeAreaInsets
                            
//                            VideoPlayerView(
//                                size: size, safeArea: safeArea, url: url,
//                                onDragDown: closeDetailView,
//                                onDragUp: fullScreen
//                            )
//                            .background(Color.clear)
                        }
                    } else {
                        HStack {}
                            .frame(height: 250)
                            .background(Color.clear)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: orientationMonitor.isLandscape ? .infinity : .infinity)
                .ignoresSafeArea(.container, edges: orientationMonitor.isLandscape ? [.top, .bottom] : [.leading, .trailing])
            } else {
                HStack {}
                    .frame(height: 250)
                    .background(Color.clear)
            }

            if !orientationMonitor.isLandscape {
                HStack(spacing: 12) {
                    ProfilePictureView(publicKeyHex: item.participants.first(where: { $0.role == "host" })?.pubkey?.hex)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? "no title")
                            .font(.body)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                        
                        Text(item.status == .ended ? "ENDED" : "LIVE")
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.opacity(showDetailPage ? 0 : 1)
            }
        }
//        .background(Color(UIColor.systemBackground))
//        .frame(maxHeight: 250)
        .matchedGeometryEffect(
            id: item.id, in: animation,
            isSource: selectedEvent?.id == item.id && animateView)
    }

    private func DetailView(item: LiveActivitiesEvent) -> some View {
        VStack {
            VStack {
                CardView(item: item, isDetailPage: true)
                    .scaleEffect(animateView ? 1 : 0.93)
                    .zIndex(1) // Keeps it on top
                
                if !orientationMonitor.isLandscape {
                    LiveChatView(liveActivitiesEvent: item)
                        .offset(y: scrollOffset > 0 ? scrollOffset : 0)
                        .opacity(animateContent ? 1 : 0)
                        .scaleEffect(animateView ? 1 : 0, anchor: .top)
                }
            }
            .offset(y: scrollOffset > 0 ? -scrollOffset : 0)
            .offset(offset: $scrollOffset)
        }
        .overlay(
            alignment: .topLeading,
            content: {
                Button {
                    closeDetailView()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                }
                .padding()
                .opacity(animateView ? 1 : 0)
            }
        )
        .onAppear {
            withAnimation(
                .interactiveSpring(
                    response: 0.6, dampingFraction: 0.7, blendDuration: 0.7)
            ) {
                animateView = true
            }
            withAnimation(
                .interactiveSpring(
                    response: 0.6, dampingFraction: 0.7, blendDuration: 0.7)
                .delay(0.05)
            ) {
                animateContent = true
            }
        }
        .transition(.identity)
//        .matchedGeometryEffect(id: item.id, in: animation, isSource: false)
    }

    func events(_ timeTabFilter: TimeTabs) -> [LiveActivitiesEvent] {
        if eventListType == .all,
            let searchText = searchViewModel.debouncedSearchText.trimmedOrNilIfEmpty
        {
//            // Search by npub.
//            if let authorPublicKey = PublicKey(npub: searchText) {
//                switch timeTabFilter {
//                case .upcoming:
//                    return appState.upcomingProfileEvents(authorPublicKey.hex)
//                case .past:
//                    return appState.pastProfileEvents(authorPublicKey.hex)
//                }
//            }
            if let metadata = try? decodedMetadata(from: searchText), let kind = metadata.kind,
                let pubkey = metadata.pubkey, let publicKey = PublicKey(hex: pubkey)
            {
                if kind == EventKind.liveActivities.rawValue {
                    // Search by naddr.
                    if let identifier = metadata.identifier,
                        let eventCoordinates = try? EventCoordinates(
                            kind: EventKind(rawValue: Int(kind)), pubkey: publicKey,
                            identifier: identifier),
                        let liveActivitiesEvent = appState.liveActivitiesEvents[
                            eventCoordinates.tag.value]
                    {
                        if timeTabFilter == .upcoming && !liveActivitiesEvent.isUpcoming {
                            self.timeTabFilter = .past
                        } else if timeTabFilter == .past && !liveActivitiesEvent.isPast {
                            self.timeTabFilter = .upcoming
                        }
                        return [liveActivitiesEvent]
                        // Search by nevent.
                    } else if let eventId = metadata.eventId {
                        let results = Set(appState.eventsTrie.find(key: eventId))
                        let events = appState.liveActivitiesEvents.filter {
                            results.contains($0.key)
                        }.map { $0.value }
                        switch timeTabFilter {
                        case .upcoming:
                            return appState.upcomingEvents(events)
                        case .past:
                            return appState.pastEvents(events)
                        }
                    }
                }
                //                    else if kind == EventKind.liveActivities.rawValue,
                //                              let identifier = metadata.identifier,
                //                              let coordinates = try? EventCoordinates(kind: EventKind(rawValue: Int(kind)), pubkey: publicKey, identifier: identifier) {
                //                        let coordinatesString = coordinates.tag.value
                //                        switch timeTabFilter {
                //                        case .upcoming:
                //                            return appState.upcomingEventsOnCalendarList(coordinatesString)
                //                        case .past:
                //                            return appState.pastEventsOnCalendarList(coordinatesString)
                //                        }
                //                    }
            }

            // Search by event tags and content.
            let results = appState.eventsTrie.find(key: searchText.localizedLowercase)
            let events = appState.liveActivitiesEvents.filter { results.contains($0.key) }.map {
                $0.value
            }
            switch timeTabFilter {
            case .upcoming:
                return appState.upcomingEvents(events)
            case .past:
                return appState.pastEvents(events)
            }
        }

        if !showAllEvents && eventListType == .all && appState.publicKey != nil {
            switch timeTabFilter {
            case .upcoming:
                return appState.upcomingFollowedEvents
            case .past:
                return appState.pastFollowedEvents
            }
        }

        let events =
            switch eventListType {
            case .all:
                switch timeTabFilter {
                case .upcoming:
                    appState.allUpcomingEvents
                case .past:
                    appState.allPastEvents
                }
            case .profile(let publicKeyHex):
                switch timeTabFilter {
                case .upcoming:
                    appState.upcomingProfileEvents(publicKeyHex)
                case .past:
                    appState.pastProfileEvents(publicKeyHex)
                }
            }
        return events
    }

    private func loadMoreEvents() {
        guard !isLoadingMore else { return }

        isLoadingMore = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let newEvents = self.events(self.timeTabFilter)
            if newEvents.count > self.currentPage * 10 {
                self.currentPage += 1
            } else {
                self.hasMoreData = false
            }

            self.isLoadingMore = false
        }
    }

    func closeDetailView() {
        withAnimation(
            .interactiveSpring(
                response: 0.6, dampingFraction: 0.7,
                blendDuration: 0.7)
        ) {
            if orientationMonitor.isLandscape {
                orientationMonitor.setOrientation(to: .portrait)
            }
            animateView = false
            animateContent = false
        }

        withAnimation(
            .interactiveSpring(
                response: 0.6, dampingFraction: 0.7,
                blendDuration: 0.7)
            .delay(0.05)
        ) {
            selectedEvent = nil
            showDetailPage = false
            notify(.display_tabbar(true))
        }
    }
    
    func fullScreen() {
        let orientationIsLandscape = orientationMonitor.isLandscape
        withAnimation(.easeInOut(duration: 0.2)) {
            orientationMonitor.setOrientation(to: orientationIsLandscape ? .portrait : .landscape)
        }
    }
    
    /// Call this method with `true` to slide the top bar offscreen, or `false` to reveal it.
    func hide_topbar(_ shouldHide: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            hideTopBar = shouldHide
        }
    }
}

struct CustomSegmentedPicker: View {
    @Binding var selectedTimeTab: TimeTabs

    let onTapAction: () -> Void

    var body: some View {
        HStack {
            ForEach(TimeTabs.allCases, id: \.self) { timeTab in
                CustomSegmentedPickerItem(
                    title: timeTab.localizedStringResource, timeTab: timeTab,
                    selectedTimeTab: $selectedTimeTab, onTapAction: onTapAction)
            }
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}

struct CustomSegmentedPickerItem: View {
    let title: LocalizedStringResource
    let timeTab: TimeTabs
    @Binding var selectedTimeTab: TimeTabs

    let onTapAction: () -> Void

    var body: some View {
        Text(title)
            .font(.subheadline)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(selectedTimeTab == timeTab ? .blue : Color.clear)
            .foregroundColor(selectedTimeTab == timeTab ? .white : .secondary)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedTimeTab = timeTab
                onTapAction()
            }
    }
}

extension Date {
    var isInCurrentYear: Bool {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.component(.year, from: .now) == calendar.component(.year, from: self)
    }
}

enum EventListType: Equatable {
    case all
    case profile(String)
    //    case liveActivity(String)
}

enum TimeTabs: CaseIterable {
    case upcoming
    case past

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .upcoming:
            "upcoming"
        case .past:
            "past"
        }
    }
}

//struct EventListView_Previews: PreviewProvider {
//
//    @State static var appState = AppState()
//
//    static var previews: some View {
//        EventListView(eventListType: .all)
//    }
//}
