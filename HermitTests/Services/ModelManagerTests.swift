import Testing
@testable import Hermit

@MainActor
struct ModelManagerTests {
    @Test func initialModelStateIsIdle() {
        let manager = ModelManager()
        #expect(manager.modelState == .idle)
        #expect(!manager.isBusy)
    }

    @Test func initialDownloadStatesReflectTheCache() {
        let manager = ModelManager()
        #expect(manager.embeddingDownloadState == (manager.embeddingModelDownloaded ? .completed : .notStarted))
        #expect(manager.llmDownloadState == (manager.llmModelDownloaded ? .completed : .notStarted))
    }
}
