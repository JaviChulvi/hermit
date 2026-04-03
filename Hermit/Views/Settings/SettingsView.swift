import SwiftUI

struct SettingsView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @Environment(ModelManager.self) private var modelManager
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Text("Settings")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    modelsSection
                    storageSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
        .background(Color("BackgroundPrimary").ignoresSafeArea())
        .alert("Delete Models?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                do {
                    try modelManager.deleteModels()
                    onboardingComplete = false
                } catch {
                    // Deletion failed silently
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded models. You'll need to download them again to use Hermit.")
        }
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODELS")
                .font(.caption.bold())
                .foregroundStyle(Color("TextSecondary"))
                .padding(.leading, 4)

            VStack(spacing: 1) {
                modelRow(
                    name: ModelInfo.embeddingModel.name,
                    size: ModelInfo.embeddingModel.sizeDescription,
                    state: modelManager.embeddingDownloadState
                )
                modelRow(
                    name: ModelInfo.llmModel.name,
                    size: ModelInfo.llmModel.sizeDescription,
                    state: modelManager.llmDownloadState
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STORAGE")
                .font(.caption.bold())
                .foregroundStyle(Color("TextSecondary"))
                .padding(.leading, 4)

            VStack(spacing: 1) {
                settingsRow(icon: "internaldrive", title: "Used", value: "\(modelManager.diskSpaceUsedMB()) MB")
                settingsRow(icon: "memorychip", title: "Available RAM", value: "\(modelManager.availableMemoryMB) MB")

                if modelManager.embeddingModelDownloaded || modelManager.llmModelDownloaded {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .font(.body)
                                .frame(width: 24)
                            Text("Delete All Models")
                            Spacer()
                        }
                        .foregroundStyle(.red)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color("BackgroundSecondary"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABOUT")
                .font(.caption.bold())
                .foregroundStyle(Color("TextSecondary"))
                .padding(.leading, 4)

            VStack(spacing: 1) {
                settingsRow(
                    icon: "info.circle",
                    title: "Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                )

                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.body)
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 24)
                    Text("100% On-Device")
                        .foregroundStyle(.white)
                    Spacer()
                    PrivacyBadge()
                }
                .padding(14)
                .background(Color("BackgroundSecondary"))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Reusable Components

    private func modelRow(name: String, size: String, state: DownloadState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon(for: state))
                .font(.body)
                .foregroundStyle(statusColor(for: state))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(size)
                    Text("·")
                    Text(statusText(for: state))
                }
                .font(.caption)
                .foregroundStyle(Color("TextSecondary"))
            }

            Spacer()
        }
        .padding(14)
        .background(Color("BackgroundSecondary"))
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color("TextSecondary"))
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .foregroundStyle(Color("TextSecondary"))
        }
        .padding(14)
        .background(Color("BackgroundSecondary"))
    }

    // MARK: - Status Helpers

    private func statusText(for state: DownloadState) -> String {
        switch state {
        case .notStarted: "Not downloaded"
        case .downloading(let progress): "Downloading \(Int(progress * 100))%"
        case .completed: "Downloaded"
        case .error(let message): "Error: \(message)"
        }
    }

    private func statusIcon(for state: DownloadState) -> String {
        switch state {
        case .notStarted: "arrow.down.circle"
        case .downloading: "arrow.down.circle.dotted"
        case .completed: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for state: DownloadState) -> Color {
        switch state {
        case .notStarted: Color("TextSecondary")
        case .downloading: Color("AccentColor")
        case .completed: .green
        case .error: .red
        }
    }
}

#Preview {
    SettingsView()
        .environment(ModelManager())
        .preferredColorScheme(.dark)
}
