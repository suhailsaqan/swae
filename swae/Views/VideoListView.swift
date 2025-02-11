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
import UIKit

struct VideoListView: View, MetadataCoding {

    @State var eventListType: EventListType
    @EnvironmentObject var appState: AppState
    @State private var timeTabFilter: TimeTabs = .past
    @State private var showAllEvents: Bool = true
    @State private var filteredEvents: [LiveActivitiesEvent] = []
    @ObservedObject private var searchViewModel = SearchViewModel()
    @State private var isProfilesSectionExpanded: Bool = false

    @State var selectedEvent: LiveActivitiesEvent?
    @State var showDetailPage: Bool = false

    @Namespace var animation

    @State var animateView: Bool = false
    @State var animateContent: Bool = false
    @State var scrollOffset: CGFloat = 0

    // Pagination states
    @State private var currentPage: Int = 0
    @State private var isLoadingMore: Bool = false
    @State private var hasMoreData: Bool = true
    
    @EnvironmentObject var orientationMonitor: OrientationMonitor

    var body: some View {
        ScrollViewReader { scrollViewProxy in
            vidListView(scrollViewProxy: scrollViewProxy)
                .onAppear {
                    filteredEvents = events(timeTabFilter)
                }
                .onChange(of: appState.liveActivitiesEvents) { _, newValue in
                    filteredEvents = events(timeTabFilter)
                }
                .onChange(of: timeTabFilter) { _, newValue in
                    filteredEvents = events(newValue)
                }
//                .searchable(text: $searchViewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "search here")
        }
        .overlay {
            if let currentItem = selectedEvent, showDetailPage {
                DetailView(item: currentItem)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .background(alignment: .top) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .frame(height: animateView ? nil : 250, alignment: .top)
                .scaleEffect(animateView ? 1 : 0.93)
                .opacity(animateView ? 1 : 0)
                .ignoresSafeArea()
        }
    }

    private func vidListView(scrollViewProxy: ScrollViewProxy) -> some View {
        VStack {
            CustomSegmentedPicker(selectedTimeTab: $timeTabFilter) {
                withAnimation {
                    scrollViewProxy.scrollTo("event-list-view-top")
                }
            }
            .padding([.leading, .trailing], 16)
            
            if eventListType == .all && appState.publicKey != nil {
                Button(
                    action: {
                        showAllEvents.toggle()
                    },
                    label: {
                        Image(systemName: "figure.stand.line.dotted.figure.stand")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30)
                            .foregroundStyle(showAllEvents ? .secondary : .primary)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding([.leading, .trailing], 16)
            }
            
            if filteredEvents.isEmpty {
                VStack {
                    Spacer()
                    Text("its boring here")
                        .font(.title)
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    EmptyView().id("event-list-view-top")
                    
                    ForEach(filteredEvents.prefix(currentPage * 10), id: \.self) { event in
                        Button {
                            withAnimation(
                                .interactiveSpring(
                                    response: 0.6, dampingFraction: 0.7,
                                    blendDuration: 0.7)
                            ) {
                                selectedEvent = event
                                showDetailPage = true
                                animateView = true
                                notify(.display_tabbar(false))
                            }
                            
                            withAnimation(
                                .interactiveSpring(
                                    response: 0.6, dampingFraction: 0.7,
                                    blendDuration: 0.7
                                ).delay(0.1)
                            ) {
                                animateContent = true
                            }
                        } label: {
                            CardView(item: event)
                                .scaleEffect(
                                    selectedEvent?.id == event.id
                                    && showDetailPage ? 1 : 0.93
                                )
                        }
                        .buttonStyle(ScaledButtonStyle())
                        .opacity(
                            showDetailPage
                            ? (selectedEvent?.id == event.id ? 1 : 0) : 1)
                    }
                    
                    // Loading more indicator
                    if isLoadingMore {
                        LoadingCircleView(showBackground: false)
                    } else {
                        GeometryReader { proxy -> Color in
                            let minY = proxy.frame(in: .global).minY
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
                .refreshable {
                    appState.refresh(hardRefresh: true)
                }
            }
        }
        .padding(.vertical)
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
                                        .topLeft, .topRight,
                                    ], radius: 15))
                    }
                    .frame(height: 250)

                    //                    LinearGradient(
                    //                        colors: [
                    //                            .black.opacity(0.5),
                    //                            .black.opacity(0.2),
                    //                            .clear,
                    //                        ], startPoint: .top, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title ?? "no title")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .offset(y: selectedEvent?.id == item.id && animateView ? safeArea().top : 0)
                }
            } else if showDetailPage && (selectedEvent?.id == item.id) && isDetailPage {
                HStack {
                    if let url = item.recording ?? item.streaming {
                        GeometryReader { proxy in
                            let size = proxy.size
                            let safeArea = proxy.safeAreaInsets
                            
                            VideoPlayerView(
                                size: size, safeArea: safeArea, url: url,
                                onDragDown: closeDetailView,
                                onDragUp: fullScreen
                            )
                            .background(Color.clear)
                        }
                    } else {
                        HStack {}
                            .frame(height: 250)
                            .background(Color.clear)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: orientationMonitor.isLandscape ? .infinity : 250)
                .ignoresSafeArea(orientationMonitor.isLandscape ? .all : [])
            } else {
                HStack {}
                    .frame(height: 250)
                    .background(Color.clear)
            }

            if !orientationMonitor.isLandscape {
                HStack(spacing: 12) {
                    KFImage.url(item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 30, height: 30)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 10, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title?.uppercased() ?? "no title")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                        
                        Text(item.status == .ended ? "STREAM ENDED" : "STREAM LIVE")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding([.horizontal])
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(UIColor.systemBackground))
        }
        .matchedGeometryEffect(
            id: item.id, in: animation,
            isSource: selectedEvent?.id == item.id && animateView)
    }

    private func DetailView(item: LiveActivitiesEvent) -> some View {
        ZStack {
            VStack {
                CardView(item: item, isDetailPage: true)
                    .scaleEffect(animateView ? 1 : 0.93)
                
                if !orientationMonitor.isLandscape {
                    VStack {
                        LiveChatView(liveActivitiesEvent: item)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                    .offset(y: scrollOffset > 0 ? scrollOffset : 0)
                    .opacity(animateContent ? 1 : 0)
                    .scaleEffect(animateView ? 1 : 0, anchor: .top)
                }
            }
            .offset(y: scrollOffset > 0 ? -scrollOffset : 0)
            .offset(offset: $scrollOffset)
        }
        .edgesIgnoringSafeArea(.all)
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
                //                .padding(.top, safeArea().top)
                //                .offset(y: -10)
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
                    response: 0.6, dampingFraction: 0.7, blendDuration: 0.7
                ).delay(0.1)
            ) {
                animateContent = true
            }
        }
        .transition(.identity)
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
            //            print("this one:", events)
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
//        print("events \(events)")
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
                blendDuration: 0.7
            ).delay(0.1)
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
