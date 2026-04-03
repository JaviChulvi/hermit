import SwiftUI

struct OnboardingView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @Environment(ModelManager.self) private var modelManager
    @State private var viewModel: OnboardingViewModel?

    var body: some View {
        Group {
            if let viewModel {
                onboardingContent(viewModel)
            } else {
                Color("BackgroundPrimary").ignoresSafeArea()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = OnboardingViewModel(modelManager: modelManager)
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func onboardingContent(_ viewModel: OnboardingViewModel) -> some View {
        TabView(selection: stepBinding(viewModel)) {
            welcomeStep(viewModel)
                .tag(0)

            downloadStep(viewModel)
                .tag(1)

            readyStep
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color("BackgroundPrimary").ignoresSafeArea())
        .animation(.easeInOut, value: viewModel.currentStep)
    }

    private func stepBinding(_ viewModel: OnboardingViewModel) -> Binding<Int> {
        Binding(
            get: {
                switch viewModel.currentStep {
                case .welcome: 0
                case .downloading: 1
                case .ready: 2
                }
            },
            set: { newValue in
                switch newValue {
                case 0: viewModel.currentStep = .welcome
                case 2: viewModel.currentStep = .ready
                default: viewModel.currentStep = .downloading
                }
            }
        )
    }

    // MARK: - Step 1: Welcome

    private func welcomeStep(_ viewModel: OnboardingViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)

            Text("Hermit")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text("Private AI on your iPhone")
                .font(.title3)
                .foregroundStyle(Color("TextSecondary"))

            VStack(alignment: .leading, spacing: 12) {
                privacyRow(icon: "iphone", text: "100% on-device processing")
                privacyRow(icon: "wifi.slash", text: "No internet required after setup")
                privacyRow(icon: "eye.slash.fill", text: "Your data never leaves your device")
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer()

            Button {
                viewModel.startDownloads()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentColor"))
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 2: Download

    private func downloadStep(_ viewModel: OnboardingViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color("AccentColor"))

            Text("Download Models")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Hermit needs two AI models to work.\nThis is a one-time download.")
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                DownloadProgressView(
                    modelName: ModelInfo.embeddingModel.name,
                    sizeLabel: ModelInfo.embeddingModel.sizeDescription,
                    state: viewModel.embeddingDownloadState,
                    onRetry: { viewModel.retryDownloads() }
                )

                DownloadProgressView(
                    modelName: ModelInfo.llmModel.name,
                    sizeLabel: ModelInfo.llmModel.sizeDescription,
                    state: viewModel.llmDownloadState,
                    onRetry: { viewModel.retryDownloads() }
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            if viewModel.hasError {
                Button {
                    viewModel.retryDownloads()
                } label: {
                    Text("Retry Download")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("AccentColor"))
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            } else if viewModel.isDownloading {
                Button {
                    viewModel.cancelDownloads()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundStyle(Color("TextSecondary"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
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
                .foregroundStyle(.white)

            Text("Hermit is ready to use.\nImport a document and start chatting.")
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                onboardingComplete = true
            } label: {
                Text("Start Using Hermit")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentColor"))
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Helpers

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 28)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(ModelManager())
}
