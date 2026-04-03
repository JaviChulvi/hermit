import SwiftUI

@main
struct HermitApp: App {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var modelManager: ModelManager
    @State private var vectorStore: VectorStore
    @State private var ragEngine: RAGEngine
    @State private var documentViewModel: DocumentViewModel

    init() {
        let mm = ModelManager()
        let vs = VectorStore()
        let es = EmbeddingService(modelManager: mm)
        let re = RAGEngine(embeddingService: es, vectorStore: vs, modelManager: mm)
        let dvm = DocumentViewModel(ragEngine: re, vectorStore: vs)

        _modelManager = State(initialValue: mm)
        _vectorStore = State(initialValue: vs)
        _ragEngine = State(initialValue: re)
        _documentViewModel = State(initialValue: dvm)
    }

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
            .environment(vectorStore)
            .environment(ragEngine)
            .environment(documentViewModel)
        }
    }
}
