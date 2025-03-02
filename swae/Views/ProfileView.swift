//
//  ProfileView.swift
//  swae
//
//  Created by Suhail Saqan on 2/23/25.
//

import SwiftUI
import NostrSDK

struct ProfileView: View {
    let appState: AppState
    let pfp_size: CGFloat = 90.0
    let bannerHeight: CGFloat = 150.0
    
    @StateObject private var viewModel: ProfileViewModel
    @State var is_zoomed: Bool = false
    @State var show_share_sheet: Bool = false
    @State var show_qr_code: Bool = false
    @State var action_sheet_presented: Bool = false
    @State var filter_state : FilterState = .liveActivities
    @State var yOffset: CGFloat = 0
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode

    init(appState: AppState, publicKeyHex: String? = nil) {
        self.appState = appState
        // Resolve publicKeyHex using the provided value or fallback to appState's active profile.
        let resolvedPublicKeyHex = publicKeyHex ?? appState.appSettings?.activeProfile?.publicKeyHex ?? ""
        _viewModel = StateObject(wrappedValue: ProfileViewModel(appState: appState, publicKeyHex: resolvedPublicKeyHex))
    }

    func bannerBlurViewOpacity() -> Double  {
        let progress = -(yOffset + navbarHeight) / 100
        return Double(-yOffset > navbarHeight ? progress : 0)
    }
    
    func getProfileInfo() -> (String, String) {
        let displayName = viewModel.profileMetadata?.displayName?.truncate(maxLength: 25) ?? ""
        let userName = viewModel.profileMetadata?.name?.truncate(maxLength: 25) ?? ""
        return (displayName, "@\(userName)")
    }
    
    func showFollowBtnInBlurrBanner() -> Bool {
        bannerBlurViewOpacity() > 1.0
    }

    var bannerSection: some View {
        GeometryReader { proxy -> AnyView in

            let minY = proxy.frame(in: .global).minY

            DispatchQueue.main.async {
                self.yOffset = minY
            }

            return AnyView(
                VStack(spacing: 0) {
                    ZStack {
                        BannerImageView(appState: appState, pubkey: viewModel.publicKeyHex, profile: viewModel.profileMetadata)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: minY > 0 ? bannerHeight + minY : bannerHeight)
                            .clipped()

                        VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial)).opacity(bannerBlurViewOpacity())
                    }

                    Divider().opacity(bannerBlurViewOpacity())
                }
                .frame(height: minY > 0 ? bannerHeight + minY : nil)
                .offset(y: minY > 0 ? -minY : -minY < navbarHeight ? 0 : -minY - navbarHeight)
            )

        }
        .frame(height: bannerHeight)
        .allowsHitTesting(false)
    }

    var navbarHeight: CGFloat {
        return 100.0 - (safeArea().top)
    }

    var settingsButton: some View {
        NavigationLink(destination: SettingsView(appState: appState)) {
            Image(systemName: "gearshape.fill")
                .frame(width: 33, height: 33)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
    }

//    func lnButton(unownedProfile: Profile?, record: ProfileRecord?) -> some View {
//        return ProfileZapLinkView(unownedProfileRecord: record, profileModel: self.profile) { reactions_enabled, lud16, lnurl in
//            Image(reactions_enabled ? "zap.fill" : "zap")
//                .foregroundColor(reactions_enabled ? .orange : Color.primary)
//                .profile_button_style(scheme: colorScheme)
//                .cornerRadius(24)
//        }
//    }

//    var dmButton: some View {
//        let dm_model = appState.dms.lookup_or_create(profile.pubkey)
//        return NavigationLink(value: Route.DMChat(dms: dm_model)) {
//            Image("messages")
//                .profile_button_style(scheme: colorScheme)
//        }
//    }
    
    private var followsYouBadge: some View {
        Text("Follows you", comment: "Text to indicate that a user is following your profile.")
            .padding([.leading, .trailing], 6.0)
            .padding([.top, .bottom], 2.0)
            .foregroundColor(.gray)
//            .background {
//                RoundedRectangle(cornerRadius: 5.0)
//                    .foregroundColor(Color(UIColor.systemGray))
//            }
            .font(.footnote)
    }

    func actionSection() -> some View {
        return Group {
//            if let record,
//               let profile = record.profile,
//               let lnurl = record.lnurl,
//               lnurl != ""
//            {
//                lnButton(unownedProfile: profile, record: record)
//            }

//            dmButton

            if viewModel.publicKeyHex != appState.appSettings?.activeProfile?.publicKeyHex {
                FollowButtonView(profileViewModel: viewModel)
            }
//            else if appState.keypair.privkey != nil {
//                NavigationLink(value: Route.EditMetadata) {
//                    ProfileEditButton(appState: appState)
//                }
//            }

        }
    }

    func pfpOffset() -> CGFloat {
        let progress = -yOffset / navbarHeight
        let offset = (pfp_size / 4.0) * (progress < 1.0 ? progress : 1)
        return offset > 0 ? offset : 0
    }

    func pfpScale() -> CGFloat {
        let progress = -yOffset / navbarHeight
        let scale = 1.0 - (0.5 * (progress < 1.0 ? progress : 1))
        return scale < 1 ? scale : 1
    }

    func nameSection(profile: UserMetadata?) -> some View {
        return Group {
            HStack(alignment: .center) {
                ProfilePicView(pubkey: viewModel.publicKeyHex, size: pfp_size, profile: viewModel.profileMetadata)
                    .padding(.top, -(pfp_size / 2.0))
                    .offset(y: pfpOffset())
                    .scaleEffect(pfpScale())
                    .onTapGesture {
                        is_zoomed.toggle()
                    }

                Spacer()
                
                if viewModel.followsYou {
                    followsYouBadge
                }
                
                actionSection()
            }
            ProfileNameView(publicKeyHex: viewModel.publicKeyHex)
        }
    }

    var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {

            nameSection(profile: viewModel.profileMetadata)

            if let about = viewModel.profileMetadata?.about {
                AboutView(about: about)
            }

//            if let url = profile_data?.profile?.website_url {
//                WebsiteLink(url: url)
//            }

            HStack {
                HStack {
                    Text("\(Text("\(viewModel.profileFollowList.count.formatted())").font(.subheadline.weight(.medium))) following")
                }

//                if let relays = profile.relays {
//                    Text("\(Text(verbatim: relays.keys.count.formatted()).font(.subheadline.weight(.medium))) relays")
//                }
            }
        }
        .padding(.horizontal)
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        bannerSection
                            .zIndex(1)
                        
                        VStack {
                            aboutSection
                            
                            VStack(spacing: 0) {
                                ProfileTabView()
                                Divider()
                                    .frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, safeArea().left)
                    .zIndex(-yOffset > navbarHeight ? 0 : 2)
                }
            }
            .padding(.bottom, tabBarHeight + getSafeAreaBottom())
            .ignoresSafeArea()
//            .navigationTitle("")
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
//                        navBackButton
//                            .padding(.top, 5)
//                            .accentColor(.white)
                        VStack(alignment: .leading, spacing: -4.5) {
                            Text(getProfileInfo().0) // Display name
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(getProfileInfo().1) // Username
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .opacity(bannerBlurViewOpacity())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, max(5, 15 + (yOffset / 30)))
                    }
                }
                if showFollowBtnInBlurrBanner() {
                    ToolbarItem(placement: .topBarTrailing) {
//                        FollowButtonView(
//                            target: profile.get_follow_target(),
//                            follows_you: profile.follows(pubkey: appState.pubkey),
//                            follow_state: appState.contacts.follow_state(profile.pubkey)
//                        )
//                        .padding(.top, 8)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        settingsButton
                            .padding(.top, 5)
                            .accentColor(.white)
                    }
                }
            }
            .toolbarBackground(.hidden)
            //            .onReceive(handle_notify(.switched_timeline)) { _ in
            //                dismiss()
            //            }
            //            .onAppear() {
            //                check_nip05_validity(pubkey: self.profile.pubkey, profiles: self.appState.profiles)
            //                profile.subscribe()
            //                //followers.subscribe()
            //            }
            //            .onDisappear {
            //                profile.unsubscribe()
            //                followers.unsubscribe()
            //                // our profilemodel needs a bit more help
            //            }
        }
        .onAppear {
            appState.pullMissingEventsFromPubkeysAndFollows([viewModel.publicKeyHex])
            
            appState.subscribeToProfile(for: viewModel.publicKeyHex)
        }
        .onDisappear {
            appState.unsubscribeFromProfile(for: viewModel.publicKeyHex)
        }
    }
}

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    var darkeningOpacity: CGFloat = 0.3 // degree of darkening

    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView {
        let effectView = UIVisualEffectView()
        effectView.backgroundColor = UIColor.black.withAlphaComponent(darkeningOpacity)
        return effectView
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) {
        uiView.effect = effect
        uiView.backgroundColor = UIColor.black.withAlphaComponent(darkeningOpacity)
    }
}

enum FilterState : Int {
    case liveActivities = 1
    case shorts = 0

    func filter(ev: NostrEvent) -> Bool {
        switch self {
        case .liveActivities:
            return ev.kind.rawValue == EventKind.liveActivities.rawValue
        case .shorts:
//            set to shorts kind
            return false
        }
    }
}
