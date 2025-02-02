//
//  LiveActivityListEventView.swift
//  swae
//
//  Created by Suhail Saqan on 11/24/24.
//

import Kingfisher
import NostrSDK
import SwiftUI

struct LiveActivityEventView: View {

    @EnvironmentObject private var appState: AppState

    @State var liveActivityEventCoordinates: String

    @State private var isDescriptionExpanded: Bool = false

    private let maxDescriptionLength = 140

    private var liveActivityEvent: LiveActivitiesEvent? {
        appState.liveActivitiesEvents[liveActivityEventCoordinates]
    }

    private var naddr: String? {
        if let liveActivityEvent {
            let relays = appState.persistentNostrEvent(liveActivityEvent.id)?.relays ?? []
            return try? liveActivityEvent.shareableEventCoordinates(
                relayURLStrings: relays.map { $0.absoluteString })
        }
        return nil
    }

    private var liveActivityURL: URL? {
        if let naddr, let njumpURL = URL(string: "https://njump.me/\(naddr)"),
            UIApplication.shared.canOpenURL(njumpURL)
        {
            return njumpURL
        }
        return nil
    }

    var body: some View {
        if let liveActivityEvent {
            VStack {
                if let imageURL = liveActivityEvent.image {
                    KFImage.url(imageURL)
                        .resizable()
                        .placeholder { ProgressView() }
                        .scaledToFit()
                        .frame(width: 40)
                        .clipShape(.circle)
                }

                //                Text(liveActivityEvent.title ?? liveActivityEvent.firstValueForRawTagName("name") ?? "No title")
                //                    .font(.headline)

                if let description = liveActivityEvent.content.trimmedOrNilIfEmpty {
                    VStack(alignment: .leading) {
                        if isDescriptionExpanded || description.count <= maxDescriptionLength {
                            Text(.init(description))
                                .font(.subheadline)
                        } else {
                            Text(.init(description.prefix(maxDescriptionLength) + "..."))
                                .font(.subheadline)
                        }

                        if description.count > maxDescriptionLength {
                            Button(
                                action: {
                                    isDescriptionExpanded.toggle()
                                },
                                label: {
                                    if isDescriptionExpanded {
                                        Text("show less")
                                            .font(.subheadline)
                                    } else {
                                        Text("show more")
                                            .font(.subheadline)
                                    }
                                })
                        }
                    }
                }

                //                VideoListView(eventListType: .all)
                //                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationBarTitleDisplayMode(.inline)
            //            .toolbar {
            //                ToolbarItem(placement: .navigationBarTrailing) {
            //                    Menu {
            //                        Button(action: {
            //                            UIPasteboard.general.string = naddr
            //                        }, label: {
            //                            Text("Copy id")
            //                        })
            //
            //                        if let liveActivityURL = liveActivityURL {
            //                            Button(action: {
            //                                UIPasteboard.general.string = liveActivityURL.absoluteString
            //                            }, label: {
            //                                Text("Copy URL")
            //                            })
            //                        }
            //                    } label: {
            //                        Label("Menu", systemImage: "ellipsis.circle")
            //                    }
            //                }
            //            }
        } else {
            EmptyView()
        }
    }
}
