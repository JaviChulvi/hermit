import SwiftUI

@main
struct HermitApp: App {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var modelManager: ModelManager
    @State private var vectorStore: VectorStore
    @State private var ragEngine: RAGEngine
    @State private var documentViewModel: DocumentViewModel
    @State private var chatViewModel: ChatViewModel
    @State private var isLoading = true

    init() {
        let mm = ModelManager()
        let vs = VectorStore()
        let es = EmbeddingService(modelManager: mm)
        let ls = LLMService(modelManager: mm)
        let re = RAGEngine(embeddingService: es, vectorStore: vs)
        let dvm = DocumentViewModel(ragEngine: re, vectorStore: vs)
        let cvm = ChatViewModel(ragEngine: re, llmService: ls)

        _modelManager = State(initialValue: mm)
        _vectorStore = State(initialValue: vs)
        _ragEngine = State(initialValue: re)
        _documentViewModel = State(initialValue: dvm)
        _chatViewModel = State(initialValue: cvm)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoading {
                    ProgressView().tint(Color("AccentColor"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color("BackgroundPrimary").ignoresSafeArea())
                } else if onboardingComplete {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .task {
                do {
                    try await vectorStore.loadAll()
                    try await documentViewModel.loadDocuments()
                } catch { documentViewModel.errorMessage = error.localizedDescription }
                isLoading = false
            }
            .preferredColorScheme(.dark)
            .environment(modelManager)
            .environment(vectorStore)
            .environment(ragEngine)
            .environment(documentViewModel)
            .environment(chatViewModel)
        }
    }
}
