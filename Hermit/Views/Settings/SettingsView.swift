import SwiftUI

struct SettingsView: View {
    @Environment(ModelManager.self) private var modelManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    modelRow(
                        name: ModelInfo.embeddingModel.name,
                        size: ModelInfo.embeddingModel.sizeDescription,
                        isDownloaded: modelManager.embeddingModelDownloaded
                    )
                    modelRow(
                        name: ModelInfo.llmModel.name,
                        size: ModelInfo.llmModel.sizeDescription,
                        isDownloaded: modelManager.llmModelDownloaded
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
                            Text("0 MB")
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    } icon: {
                        Image(systemName: "internaldrive")
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
        }
    }

    private func modelRow(name: String, size: String, isDownloaded: Bool) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                HStack(spacing: 4) {
                    Text(size)
                    Text("·")
                    Text(isDownloaded ? "Downloaded" : "Not downloaded")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(isDownloaded ? .green : .secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environment(ModelManager())
}
