//
//  OnboardingView.swift
//  swae
//
//  Created by Suhail Saqan on 4/12/25.
//

import SwiftUI

struct OnboardingStep {
    let image: String
    let title: String
    let description: String
}

struct OnboardingView: View {
    // Control whether onboarding is shown
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    // Control which step is currently displayed
    @State private var currentStep = 0
    
    // Define your onboarding steps
    let onboardingSteps = [
        OnboardingStep(
            image: "play.circle.fill",
            title: "Watch Videos",
            description: "Stream the latest content from creators around the world"
        ),
        OnboardingStep(
            image: "tv.and.mediabox.fill",
            title: "Go Live",
            description: "Create and share your own livestreams with your followers"
        ),
        OnboardingStep(
            image: "person.2.fill",
            title: "Connect",
            description: "Follow your favorite creators and build your community"
        ),
        OnboardingStep(
            image: "wallet.pass.fill",
            title: "Support Creators",
            description: "Use the integrated wallet to support creators you love"
        )
    ]
    
    var body: some View {
        ZStack {
            Color(.black.opacity(0.05))
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                // Logo or App Name
                Text("SwaeApp")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 50)
                
                // Image for current step
                Image(systemName: onboardingSteps[currentStep].image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150, height: 150)
                    .foregroundColor(.blue)
                    .padding()
                
                // Title for current step
                Text(onboardingSteps[currentStep].title)
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // Description for current step
                Text(onboardingSteps[currentStep].description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                
                Spacer()
                
                // Page indicator
                HStack(spacing: 10) {
                    ForEach(0..<onboardingSteps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.5))
                            .frame(width: 10, height: 10)
                            .animation(.easeInOut, value: currentStep)
                    }
                }
                .padding(.bottom, 20)
                
                // Next button or Get Started button
                Button(action: {
                    if currentStep < onboardingSteps.count - 1 {
                        currentStep += 1
                    } else {
                        // Mark onboarding as completed
                        hasCompletedOnboarding = true
                    }
                }) {
                    Text(currentStep < onboardingSteps.count - 1 ? "Next" : "Get Started")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                
                // Skip button (only show if not on last step)
                if currentStep < onboardingSteps.count - 1 {
                    Button("Skip") {
                        hasCompletedOnboarding = true
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                } else {
                    Spacer().frame(height: 40)
                }
            }
        }
    }
}
