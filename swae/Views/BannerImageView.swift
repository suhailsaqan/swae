//
//  EditBannerImageView.swift
//  swae
//
//  Created by Suhail Saqan on 2/23/25.
//

import SwiftUI
import Kingfisher
import NostrSDK

struct EditBannerImageView: View {
    var appState: AppState
    let callback: (URL?) -> Void
    let safeAreaInsets: EdgeInsets
    let profile: UserMetadata?
    let pubkey: String
    
    @State private var bannerImage: URL?
    
    private let defaultImage = UIImage(named: "swae") ?? UIImage()
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            KFAnimatedImage(getBannerURL())
                .imageContext(.banner)
                .configure { $0.framePreloadCount = .max }
                .placeholder { Color(uiColor: .secondarySystemBackground) }
                .onFailureImage(defaultImage)
                .kfClickable()
        }
    }
    
    private func getBannerURL() -> URL? {
        appState.metadataEvents[pubkey]?.userMetadata?.bannerPictureURL
    }
}

struct InnerBannerImageView: View {
    let url: URL?
    private let defaultImage = UIImage(named: "swae") ?? UIImage()
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if let url = url {
                KFAnimatedImage(url)
                    .imageContext(.banner)
                    .configure { $0.framePreloadCount = 3 }
                    .placeholder { Color(uiColor: .secondarySystemBackground) }
                    .onFailureImage(defaultImage)
                    .kfClickable()
            } else {
                Image(uiImage: defaultImage).resizable()
            }
        }
    }
}

struct BannerImageView: View {
    var appState: AppState
    let pubkey: String?
    let profile: UserMetadata?
    
    @State private var banner: String?
    
    init(appState: AppState, pubkey: String?, profile: UserMetadata?, banner: String? = nil) {
        self.appState = appState
        self.pubkey = pubkey
        self.profile = profile
        self._banner = State(initialValue: banner)
    }
    
    var body: some View {
        InnerBannerImageView(url: getBannerURL())
    }
    
    private func getBannerURL() -> URL? {
        if let pubkey {
            appState.metadataEvents[pubkey]?.userMetadata?.bannerPictureURL
        } else {
            URL(fileURLWithPath: "swae")
        }
    }
}

extension View {
    func backwardsCompatibleSafeAreaPadding(_ insets: EdgeInsets) -> some View {
        Group {
            if #available(iOS 17.0, *) {
                self.safeAreaPadding(insets)
            } else {
                self.padding(.top, insets.top)
            }
        }
    }
}
