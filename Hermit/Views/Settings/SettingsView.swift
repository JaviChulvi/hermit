import SwiftUI

struct SettingsView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @Environment(ModelManager.self) private var modelManager
    @Environment(VectorStore.self) private var vectorStore
    @Environment(DocumentViewModel.self) private var documentViewModel
    @Environment(ChatViewModel.self) private var chatViewModel

    @State private var showDeleteModelsConfirmation = false
    @State private var showDeleteDocumentsConfirmation = false
    @State private var showResetAppConfirmation = false

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
                    memorySection
                    documentsSection
                    dataManagementSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Color("BackgroundPrimary").ignoresSafeArea())
        .alert("Delete Models?", isPresented: $showDeleteModelsConfirmation) {
            Button("Delete", role: .destructive) {
                do {
                    try modelManager.deleteModels()
                    onboardingComplete = false
                } catch {
                    // Deletion failed
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded models. You'll need to download them again to use Hermit.")
        }
        .alert("Delete All Documents?", isPresented: $showDeleteDocumentsConfirmation) {
            Button("Delete", role: .destructive) {
                documentViewModel.deleteAllDocuments()
                chatViewModel.clearConversation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all imported documents and their embeddings. Your chat history will also be cleared.")
        }
        .alert("Reset App?", isPresented: $showResetAppConfirmation) {
            Button("Reset", role: .destructive) {
                documentViewModel.deleteAllDocuments()
                chatViewModel.clearConversation()
                do {
                    try modelManager.deleteModels()
                } catch {
                    // Deletion failed
                }
                onboardingComplete = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all documents, models, and reset the app to its initial state.")
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
                    modelId: ModelInfo.embeddingModel.id,
                    state: modelManager.embeddingDownloadState,
                    isLoaded: modelManager.modelState == .embeddingLoaded
                )
                modelRow(
                    name: ModelInfo.llmModel.name,
                    size: ModelInfo.llmModel.sizeDescription,
                    modelId: ModelInfo.llmModel.id,
                    state: modelManager.llmDownloadState,
                    isLoaded: modelManager.modelState == .llmLoaded
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Memory Section

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEMORY")
                .font(.caption.bold())
                .foregroundStyle(Color("TextSecondary"))
                .padding(.leading, 4)

            VStack(spacing: 1) {
                settingsRow(icon: "memorychip", title: "Available RAM", value: "\(modelManager.availableMemoryMB) MB")
                settingsRow(icon: "cpu", title: "Model State", value: modelStateText)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Documents Section

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DOCUMENTS")
                .font(.caption.bold())
                .foregroundStyle(Color("TextSecondary"))
                .padding(.leading, 4)

            VStack(spacing: 1) {
                settingsRow(icon: "doc.text", title: "Documents Imported", value: "\(documentViewModel.documents.count)")
                settingsRow(icon: "square.stack.3d.up", title: "Total Chunks", value: "\(vectorStore.chunks.count)")
                settingsRow(icon: "internaldrive", title: "Vector Store", value: vectorStoreSizeText)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Data Management Section

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DATA MANAGEMENT")
                .font(.caption.bold())
                .foregroundStyle(Color("TextSecondary"))
                .padding(.leading, 4)

            VStack(spacing: 1) {
                if !documentViewModel.documents.isEmpty {
                    destructiveButton(icon: "trash", title: "Delete All Documents") {
                        showDeleteDocumentsConfirmation = true
                    }
                }

                if modelManager.embeddingModelDownloaded || modelManager.llmModelDownloaded {
                    destructiveButton(icon: "arrow.down.circle.dotted", title: "Delete Models") {
                        showDeleteModelsConfirmation = true
                    }
                }

                destructiveButton(icon: "arrow.counterclockwise", title: "Reset App") {
                    showResetAppConfirmation = true
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
                settingsRow(
                    icon: "cube.box",
                    title: "Embedding Model",
                    value: ModelInfo.embeddingModel.id
                )
                settingsRow(
                    icon: "cube.box.fill",
                    title: "LLM",
                    value: ModelInfo.llmModel.id
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

    private func modelRow(name: String, size: String, modelId: String, state: DownloadState, isLoaded: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon(for: state))
                .font(.body)
                .foregroundStyle(statusColor(for: state))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body)
                        .foregroundStyle(.white)
                    if isLoaded {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                }
                HStack(spacing: 4) {
                    Text(size)
                    Text("·")
                    Text(statusText(for: state))
                }
                .font(.caption)
                .foregroundStyle(Color("TextSecondary"))
            }

            Spacer()

            if isLoaded {
                Text("Loaded")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.15))
                    .clipShape(Capsule())
            }
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
                .font(.footnote)
                .lineLimit(1)
        }
        .padding(14)
        .background(Color("BackgroundSecondary"))
    }

    private func destructiveButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 24)
                Text(title)
                Spacer()
            }
            .foregroundStyle(.red)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("BackgroundSecondary"))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Properties

    private var modelStateText: String {
        switch modelManager.modelState {
        case .idle: "Idle"
        case .embeddingLoaded: "Embedding Loaded"
        case .llmLoaded: "LLM Loaded"
        case .transitioning: "Transitioning..."
        }
    }

    private var vectorStoreSizeText: String {
        let mb = vectorStore.storageSizeMB()
        if mb > 0 {
            return "\(mb) MB"
        }
        let kb = vectorStoreApproxKB()
        return kb > 0 ? "<1 MB" : "0 MB"
    }

    private func vectorStoreApproxKB() -> Int {
        // Rough estimate: if chunks exist, there's at least some data
        vectorStore.chunks.isEmpty ? 0 : 1
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
        .environment(VectorStore())
        .environment(DocumentViewModel(ragEngine: RAGEngine(embeddingService: EmbeddingService(modelManager: ModelManager()), vectorStore: VectorStore(), modelManager: ModelManager()), vectorStore: VectorStore()))
        .environment({
            let mm = ModelManager()
            let vs = VectorStore()
            let ls = LLMService(modelManager: mm)
            let re = RAGEngine(embeddingService: EmbeddingService(modelManager: mm), vectorStore: vs, modelManager: mm)
            return ChatViewModel(ragEngine: re, llmService: ls)
        }())
        .preferredColorScheme(.dark)
}
