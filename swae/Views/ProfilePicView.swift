//
//  ProfilePictureView.swift
//  swae
//
//  Created by Suhail Saqan on 2/1/25.
//

import Kingfisher
import SwiftUI
import NostrSDK

struct ProfilePicView: View {
    let pubkey: String
    let size: CGFloat
    let profile: UserMetadata?
//    let zappability_indicator: Bool
    
    init(pubkey: String, size: CGFloat, profile: UserMetadata?, picture: String? = nil, show_zappability: Bool? = nil) {
        self.pubkey = pubkey
        self.profile = profile
        self.size = size
//        self._picture = State(initialValue: picture)
//        self.zappability_indicator = show_zappability ?? false
    }
    
//    func get_lnurl() -> String? {
//        return profile.lookup_with_timestamp(pubkey)?.unsafeUnownedValue?.lnurl
//    }
    

    
    var body: some View {
        ZStack (alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
            InnerProfilePicView(url: profile?.pictureURL, fallbackUrl: URL(string: robohash(pubkey)), pubkey: pubkey, size: size)
//                .onReceive(handle_notify(.profile_updated)) { updated in
//                    guard updated.pubkey == self.pubkey else {
//                        return
//                    }
//                    
//                    switch updated {
//                        case .manual(_, let profile):
//                            if let pic = profile.picture {
//                                self.picture = pic
//                            }
//                        case .remote(pubkey: let pk):
//                            let profile_txn = profile.lookup(id: pk)
//                            let profile = profile_txn?.unsafeUnownedValue
//                            if let pic = profile?.picture {
//                                self.picture = pic
//                            }
//                    }
//                }
            
//            if self.zappability_indicator, let lnurl = self.get_lnurl(), lnurl != "" {
//                Image("zap.fill")
//                    .resizable()
//                    .frame(
//                        width: size * 0.24,
//                        height: size * 0.24
//                    )
//                    .padding(size * 0.04)
//                    .foregroundColor(.white)
//                    .background(Color.orange)
//                    .clipShape(Circle())
//            }
        }
    }
}

struct InnerProfilePicView: View {
    let url: URL?
    let fallbackUrl: URL?
    let pubkey: String
    let size: CGFloat
    
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    
    func imageBorderColor() -> Color {
        colorScheme == .light ? .white : .black
    }

    var Placeholder: some View {
        Circle()
            .frame(width: size, height: size)
            .foregroundColor(.gray)
            .overlay(Circle().stroke(imageBorderColor(), lineWidth: 3))
            .padding(2)
    }

    var body: some View {
        NavigationLink(destination: ProfileView(appState: appState, publicKeyHex: pubkey)) {
            KFAnimatedImage(url)
                .imageContext(.pfp)
                .onFailure(fallbackUrl: fallbackUrl, cacheKey: url?.absoluteString)
                .cancelOnDisappear(true)
                .configure { view in
                    view.framePreloadCount = 3
                }
                .placeholder { _ in
                    Placeholder
                }
                .scaledToFill()
                .frame(width: size, height: size)
                .kfClickable()
                .clipShape(Circle())
                .overlay(Circle().stroke(imageBorderColor(), lineWidth: 3))
        }
    }
}

func robohash(_ publicKeyHex: String) -> String {
    return "https://robohash.org/\(publicKeyHex)?set=set4"
}
