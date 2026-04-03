import SwiftUI

struct SettingsView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @Environment(ModelManager.self) private var modelManager
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                } header: {
                    Text("Models")
                        .foregroundStyle(Color("TextSecondary"))
                }
                .listRowBackground(Color("BackgroundSecondary"))

                Section {
                    Label {
                        HStack {
                            Text("Used")
                            Spacer()
                            Text("\(modelManager.diskSpaceUsedMB()) MB")
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    } icon: {
                        Image(systemName: "internaldrive")
                    }

                    if modelManager.embeddingModelDownloaded || modelManager.llmModelDownloaded {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete All Models", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Storage")
                        .foregroundStyle(Color("TextSecondary"))
                }
                .listRowBackground(Color("BackgroundSecondary"))

                Section {
                    Label {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    } icon: {
                        Image(systemName: "info.circle")
                    }

                    HStack {
                        Label {
                            Text("100% On-Device")
                        } icon: {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(Color("AccentColor"))
                        }
                        Spacer()
                        PrivacyBadge()
                    }
                } header: {
                    Text("About")
                        .foregroundStyle(Color("TextSecondary"))
                }
                .listRowBackground(Color("BackgroundSecondary"))
            }
            .scrollContentBackground(.hidden)
            .background(Color("BackgroundPrimary"))
            .navigationTitle("Settings")
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color("BackgroundPrimary"), for: .navigationBar)
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
    }

    private func modelRow(name: String, size: String, state: DownloadState) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                HStack(spacing: 4) {
                    Text(size)
                    Text("·")
                    Text(statusText(for: state))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: statusIcon(for: state))
                .foregroundStyle(statusColor(for: state))
        }
    }

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
        case .notStarted: .secondary
        case .downloading: Color("AccentColor")
        case .completed: .green
        case .error: .red
        }
    }
}

#Preview {
    SettingsView()
        .environment(ModelManager())
}
