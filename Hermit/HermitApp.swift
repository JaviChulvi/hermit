import SwiftUI

@main
struct HermitApp: App {
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            if onboardingComplete {
                ContentView()
            } else {
                OnboardingView()
            }
        }
    }
}
