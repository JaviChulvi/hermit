import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Models") {
                    modelRow(
                        name: ModelInfo.embeddingModel.name,
                        size: ModelInfo.embeddingModel.sizeDescription,
                        isDownloaded: false
                    )
                    modelRow(
                        name: ModelInfo.llmModel.name,
                        size: ModelInfo.llmModel.sizeDescription,
                        isDownloaded: false
                    )
                }

                Section("Storage") {
                    Label {
                        HStack {
                            Text("Used")
                            Spacer()
                            Text("0 MB")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "internaldrive")
                    }
                }

                Section("About") {
                    Label {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "info.circle")
                    }

                    HStack {
                        Label {
                            Text("100% On-Device")
                        } icon: {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        PrivacyBadge()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("BackgroundPrimary"))
            .navigationTitle("Settings")
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
}
