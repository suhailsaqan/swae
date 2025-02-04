//
//  ContentView.swift
//  swae
//
//  Created by Suhail Saqan on 8/11/24.
//

import AVFoundation
import NostrSDK
import SwiftData
import SwiftUI

struct ContentView: View {

    let modelContext: ModelContext
    @EnvironmentObject var appState: AppState
    @SceneStorage("ContentView.selected_tab") var selected_tab: ScreenTabs = .home

    @State var isShowingCreationConfirmation: Bool = false
    @State private var isSideBarOpened = false
    @StateObject var navigationCoordinator: NavigationCoordinator = NavigationCoordinator()
    @State var hide_bar: Bool = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var body: some View {
        return NavigationStack(path: $navigationCoordinator.path) {
            VStack(alignment: .leading, spacing: 0) {
                TabView {
                    MainContent(appState: appState)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                //                .navigationDestination(for: Route.self) { route in
                //                    route.view(navigationCoordinator: navigationCoordinator, appState: appState)
                //                }
                .onReceive(handle_notify(.switched_tab)) { _ in
                    navigationCoordinator.popToRoot()
                }
                if !hide_bar {
                    TabBar(
                        selected: $selected_tab, settings: appState.appSettings,
                        action: switch_selected_tab
                    )
                    .padding([.bottom], 8)
                    .background(Color(uiColor: .systemBackground).ignoresSafeArea())
                } else {
                    Text("")
                }
            }
        }
        .navigationViewStyle(.stack)
        .ignoresSafeArea(.keyboard)
        .edgesIgnoringSafeArea(hide_bar ? [.bottom] : [])
        .onReceive(handle_notify(.display_tabbar)) { display in
            let show = display
            self.hide_bar = !show
        }

        func MainContent(appState: AppState) -> some View {
            return ZStack {
                switch selected_tab {
                case .home:
                    VideoListView(eventListType: .all)
                        .navigationBarTitleDisplayMode(.inline)
                case .live:
                    IngestView()
                case .profile:
                    SignInView()
                }
            }
        }

        func switch_selected_tab(_ screenTab: ScreenTabs) {
            self.isSideBarOpened = false
            let navWasAtRoot = self.navIsAtRoot()
            self.popToRoot()

            notify(.switched_tab(screenTab))

            if screenTab == self.selected_tab && navWasAtRoot {
                notify(.scroll_to_top)
                return
            }

            self.selected_tab = screenTab
        }

        func popToRoot() {
            navigationCoordinator.popToRoot()
            isSideBarOpened = false
        }

        struct CustomTabBar: View {
            @Binding var selectedTab: HomeTabs

            let isSignedIn: Bool
            let onTapAction: () -> Void

            var body: some View {
                HStack {
                    CustomTabBarItem(
                        iconName: "house.fill", title: "home", tab: HomeTabs.home,
                        selectedTab: $selectedTab, onTapAction: onTapAction)

                    CustomTabBarItem(
                        iconName: "camera", title: "tab2", tab: HomeTabs.live,
                        selectedTab: $selectedTab, onTapAction: onTapAction)

                    CustomTabBarItem(
                        iconName: "person", title: "tab3", tab: HomeTabs.profile,
                        selectedTab: $selectedTab, onTapAction: onTapAction)
                }
                .frame(height: 50)
                .background(Color.gray.opacity(0.2))
            }
        }

        struct CustomTabBarItem: View {
            let iconName: String
            let title: LocalizedStringResource
            let tab: HomeTabs
            @Binding var selectedTab: HomeTabs

            let onTapAction: () -> Void

            var body: some View {
                VStack {
                    Image(systemName: iconName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                    Text(title)
                        .font(.caption)
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTab = tab
                    onTapAction()
                }
                .foregroundColor(selectedTab == tab ? .blue : .gray)
                .frame(maxWidth: .infinity)
            }
        }
    }

    func navIsAtRoot() -> Bool {
        return navigationCoordinator.isAtRoot()
    }

    func popToRoot() {
        navigationCoordinator.popToRoot()
        isSideBarOpened = false
    }

    func screen_tab_name(_ screen_tab: ScreenTabs?) -> String {
        guard let screen_tab else {
            return ""
        }
        switch screen_tab {
        case .home:
            return NSLocalizedString(
                "Home",
                comment:
                    "Navigation bar title for Home view where notes and replies appear from those who the user is following."
            )
        case .live:
            return NSLocalizedString(
                "Live",
                comment:
                    "Navigation bar title for Live view."
            )
        case .profile:
            return NSLocalizedString(
                "Profile",
                comment:
                    "Navigation bar title for profile view."
            )
        }
    }
}
