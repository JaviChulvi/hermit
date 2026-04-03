import Testing
import Foundation
@testable import Hermit

@MainActor
struct ModelManagerLoadTests {
    // MARK: - State Transitions

    @Test func unloadEmbeddingResetsStateToIdle() {
        let manager = ModelManager()
        manager.unloadEmbedding()
        #expect(manager.modelState == .idle)
        #expect(manager.embeddingContainer == nil)
    }

    @Test func unloadLLMResetsStateToIdle() {
        let manager = ModelManager()
        manager.unloadLLM()
        #expect(manager.modelState == .idle)
        #expect(manager.llmContainer == nil)
    }

    @Test func unloadAllResetsStateToIdle() {
        let manager = ModelManager()
        manager.unloadAll()
        #expect(manager.modelState == .idle)
        #expect(manager.embeddingContainer == nil)
        #expect(manager.llmContainer == nil)
    }

    // MARK: - Loading Without Downloaded Models

    @Test func loadEmbeddingThrowsWhenModelNotDownloaded() async {
        let manager = ModelManager()
        do {
            try await manager.loadEmbeddingModel()
            Issue.record("Expected modelNotDownloaded error")
        } catch let error as ModelManagerError {
            if case .modelNotDownloaded = error {
                // Expected
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(manager.modelState == .idle)
    }

    @Test func loadLLMThrowsWhenModelNotDownloaded() async {
        let manager = ModelManager()
        do {
            try await manager.loadLLM()
            Issue.record("Expected modelNotDownloaded error")
        } catch let error as ModelManagerError {
            if case .modelNotDownloaded = error {
                // Expected
            } else if case .insufficientMemory = error {
                // Also acceptable in constrained environments
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(manager.modelState == .idle)
    }

    // MARK: - State After Failed Load

    @Test func stateResetsToIdleAfterFailedEmbeddingLoad() async {
        let manager = ModelManager()
        try? await manager.loadEmbeddingModel()
        #expect(manager.modelState == .idle)
    }

    @Test func stateResetsToIdleAfterFailedLLMLoad() async {
        let manager = ModelManager()
        try? await manager.loadLLM()
        #expect(manager.modelState == .idle)
    }

    // MARK: - Containers Are Nil Initially

    @Test func containersAreNilInitially() {
        let manager = ModelManager()
        #expect(manager.embeddingContainer == nil)
        #expect(manager.llmContainer == nil)
    }
}
