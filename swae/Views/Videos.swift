//
//  Videos.swift
//  swae
//
//  Created by Suhail Saqan on 11/21/24.
//

import Combine
import SwiftUI

struct Videos: View {
    @State var currentItem: Today?
    @State var showDetailPage: Bool = false

    @Namespace var animation

    @State var animateView: Bool = false
    @State var animateContent: Bool = false
    @State var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)
                .padding(.bottom)
                .opacity(showDetailPage ? 0 : 1)

                ForEach(todayItems) { item in
                    Button {
                        withAnimation(
                            .interactiveSpring(
                                response: 0.6, dampingFraction: 0.7,
                                blendDuration: 0.7)
                        ) {
                            currentItem = item
                            showDetailPage = true
                            animateView = true
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
                        CardView(item: item)
                            .scaleEffect(
                                currentItem?.id == item.id
                                    && showDetailPage ? 1 : 0.93
                            )
                    }
                    .buttonStyle(ScaledButtonStyle())
                    .opacity(
                        showDetailPage
                            ? (currentItem?.id == item.id ? 1 : 0) : 1)
                }
            }
            .padding(.vertical)
        }
        .overlay {
            if let currentItem = currentItem, showDetailPage {
                DetailView(item: currentItem)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .background(alignment: .top) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .frame(height: animateView ? nil : 350, alignment: .top)
                .scaleEffect(animateView ? 1 : 0.93)
                .opacity(animateView ? 1 : 0)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func CardView(item: Today) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if !showDetailPage && !(currentItem?.id == item.id) {
                ZStack(alignment: .topLeading) {
                    GeometryReader { proxy in
                        let size = proxy.size

                        Image(item.artwork)
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
                    .frame(height: 400)

                    LinearGradient(
                        colors: [
                            .black.opacity(0.5),
                            .black.opacity(0.2),
                            .clear,
                        ], startPoint: .top, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.platformTitle.uppercased())
                            .font(.callout)
                            .fontWeight(.semibold)

                        Text(item.bannerTitle)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .offset(
                        y: currentItem?.id == item.id && animateView
                            ? safeArea().top : 0)
                }
            } else {
                HStack {
                    Spacer()  // Pushes the content to the full width
                    Text("yoooo")
                    Spacer()  // Pushes the content to the full width
                }
                .frame(height: 400)
                .background(Color.blue)
            }

            HStack(spacing: 12) {
                Image(item.appLogo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.platformTitle.uppercased())
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text(item.appName)
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text(item.appDescription)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {

                } label: {
                    Text("GET")
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                }
            }
            .padding([.horizontal, .bottom])
        }
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(UIColor.systemBackground))
        }
        .matchedGeometryEffect(
            id: item.id, in: animation,
            isSource: currentItem?.id == item.id && animateView)
    }

    private func DetailView(item: Today) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                CardView(item: item)
                    .scaleEffect(animateView ? 1 : 0.93)

                VStack(spacing: 15) {
                    Text(item.appDescription)
                }
                .padding()
                .offset(y: scrollOffset > 0 ? scrollOffset : 0)
                .opacity(animateContent ? 1 : 0)
                .scaleEffect(animateView ? 1 : 0, anchor: .top)
            }
            .offset(y: scrollOffset > 0 ? -scrollOffset : 0)
            .offset(offset: $scrollOffset)
        }
        .overlay(
            alignment: .topTrailing,
            content: {
                Button {
                    withAnimation(
                        .interactiveSpring(
                            response: 0.6, dampingFraction: 0.7,
                            blendDuration: 0.7)
                    ) {
                        animateView = false
                        animateContent = false
                    }

                    withAnimation(
                        .interactiveSpring(
                            response: 0.6, dampingFraction: 0.7,
                            blendDuration: 0.7
                        ).delay(0.05)
                    ) {
                        currentItem = nil
                        showDetailPage = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                .padding()
                .padding(.top, safeArea().top)
                .offset(y: -10)
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
        //        .matchedGeometryEffect(id: item.id, in: animation, isSource: false)
    }

    var todayItems: [Today] = [
        Today(
            id: "Lego", appName: "battle", appDescription: "cool app",
            appLogo: "Unsplash0", bannerTitle: "smashhhh", platformTitle: "yeaaa",
            artwork: "Unsplash1"),
        Today(
            id: "Lego1", appName: "battle1", appDescription: "cool app1",
            appLogo: "Unsplash2", bannerTitle: "smashhhh", platformTitle: "yeaaa",
            artwork: "Unsplash3"),
        Today(
            id: "Lego2", appName: "battle1", appDescription: "cool app1",
            appLogo: "Unsplash2", bannerTitle: "smashhhh", platformTitle: "yeaaa",
            artwork: "Unsplash3"),
        Today(
            id: "Lego3", appName: "battle1", appDescription: "cool app1",
            appLogo: "Unsplash2", bannerTitle: "smashhhh", platformTitle: "yeaaa",
            artwork: "Unsplash3"),
        Today(
            id: "Lego4", appName: "battle1", appDescription: "cool app1",
            appLogo: "Unsplash2", bannerTitle: "smashhhh", platformTitle: "yeaaa",
            artwork: "Unsplash3"),
        Today(
            id: "Lego5", appName: "battle1", appDescription: "cool app1",
            appLogo: "Unsplash2", bannerTitle: "smashhhh", platformTitle: "yeaaa",
            artwork: "Unsplash3"),
        Today(
            id: "Lego6", appName: "battle1", appDescription: "cool app1",
            appLogo: "Unsplash2", bannerTitle: "smashhhh", platformTitle: "yeaaa",
            artwork: "Unsplash3"),
        Today(
            id: "Lego7", appName: "battle1", appDescription: "cool app1",
            appLogo: "Unsplash2", bannerTitle: "smashhhh", platformTitle: "yeaaa",
            artwork: "Unsplash3"),
    ]
}

struct CustomCorner: Shape {
    var corners: UIRectCorner
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect, byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius))

        return Path(path.cgPath)
    }
}

struct Today: Identifiable, Hashable {
    var id: String
    var appName: String
    var appDescription: String
    var appLogo: String
    var bannerTitle: String
    var platformTitle: String
    var artwork: String
}

struct SafeArea: EnvironmentKey {
    static var defaultValue: UIEdgeInsets = .zero
}

extension EnvironmentValues {
    var safeArea: UIEdgeInsets {
        self[SafeArea.self]
    }
}

extension View {
    func safeArea() -> UIEdgeInsets {
        if let screen = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if let safeArea = screen.windows.first?.safeAreaInsets {
                return safeArea
            }
        }
        return .zero
    }

    func offset(offset: Binding<CGFloat>) -> some View {
        self
            .overlay {
                GeometryReader { proxy in
                    let minY = proxy.frame(in: .named("SCROLL")).minY
                    Color.clear
                        .preference(key: OffsetKey.self, value: minY)
                }
            }
            .onPreferenceChange(OffsetKey.self) { value in
                offset.wrappedValue = value
            }
    }
}

struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {}
}

struct ScaledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(
                .spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.7),
                value: configuration.isPressed)
    }
}

struct HeroExample_Previews: PreviewProvider {
    static var previews: some View {
        Videos()
    }
}
