import SwiftUI

struct OnboardingView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var currentStep = 0

    // Placeholder download states
    @State private var embeddingState: DownloadState = .notStarted
    @State private var llmState: DownloadState = .notStarted

    var body: some View {
        TabView(selection: $currentStep) {
            welcomeStep
                .tag(0)

            downloadStep
                .tag(1)

            readyStep
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)

            Text("Hermit")
                .font(.largeTitle.bold())

            Text("Private AI on your iPhone")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                privacyRow(icon: "iphone", text: "100% on-device processing")
                privacyRow(icon: "wifi.slash", text: "No internet required after setup")
                privacyRow(icon: "eye.slash.fill", text: "Your data never leaves your device")
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer()

            Button {
                withAnimation {
                    currentStep = 1
                }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 2: Download

    private var downloadStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Download Models")
                .font(.title2.bold())

            Text("Hermit needs two AI models to work.\nThis is a one-time download.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                DownloadProgressView(
                    modelName: ModelInfo.embeddingModel.name,
                    sizeLabel: ModelInfo.embeddingModel.sizeDescription,
                    state: embeddingState
                )

                DownloadProgressView(
                    modelName: ModelInfo.llmModel.name,
                    sizeLabel: ModelInfo.llmModel.sizeDescription,
                    state: llmState
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                // Placeholder: simulate download starting
                embeddingState = .downloading(progress: 0)
                llmState = .downloading(progress: 0)
                withAnimation {
                    currentStep = 2
                }
            } label: {
                Text("Download Models")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 3: Ready

    private var readyStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.largeTitle.bold())

            Text("Hermit is ready to use.\nImport a document and start chatting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                onboardingComplete = true
            } label: {
                Text("Start Using Hermit")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Helpers

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    OnboardingView()
}
