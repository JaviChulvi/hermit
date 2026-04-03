import SwiftUI

@main
struct HermitApp: App {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var modelManager = ModelManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .preferredColorScheme(.dark)
            .environment(modelManager)
        }
    }
}
