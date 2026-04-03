import Testing
import Foundation
@testable import Hermit

@MainActor
struct ModelManagerTests {
    @Test func initialModelStateIsIdle() {
        let manager = ModelManager()
        #expect(manager.modelState == .idle)
    }

    @Test func initialDownloadStatesAreNotStarted() {
        let manager = ModelManager()
        // Models are not on disk, so states should remain .notStarted
        #expect(manager.embeddingDownloadState == .notStarted)
        #expect(manager.llmDownloadState == .notStarted)
    }

    @Test func modelDirectoryReturnsURLInsideDocumentsModels() {
        let manager = ModelManager()
        let url = manager.modelDirectory(for: "mlx-community/all-MiniLM-L6-v2-bf16")
        let path = url.path
        #expect(path.contains("Documents/models/mlx-community/all-MiniLM-L6-v2-bf16"))
    }

    @Test func embeddingModelNotDownloadedByDefault() {
        let manager = ModelManager()
        #expect(manager.embeddingModelDownloaded == false)
    }

    @Test func llmModelNotDownloadedByDefault() {
        let manager = ModelManager()
        #expect(manager.llmModelDownloaded == false)
    }
}
