import Testing
import Foundation
@testable import Hermit

/// Integration tests for LLMService.
/// These tests require the LLM (Gemma 4 E2B) to be downloaded on disk.
/// They pass as no-ops when the model is not available.
@MainActor
struct LLMServiceIntegrationTests {

    private func makeServiceIfModelAvailable() -> (LLMService, ModelManager)? {
        let manager = ModelManager()
        guard manager.llmModelDownloaded else { return nil }
        return (LLMService(modelManager: manager), manager)
    }

    @Test func loadModel_setsStateLLMLoaded() async throws {
        guard let (service, manager) = makeServiceIfModelAvailable() else { return }

        try await service.loadModel()
        #expect(manager.modelState == .llmLoaded)

        await service.unloadModel()
        #expect(manager.modelState == .idle)
    }

    @Test func generate_yieldsAtLeastOneToken() async throws {
        guard let (service, manager) = makeServiceIfModelAvailable() else { return }

        try await service.loadModel()

        let stream = try await service.generate(
            systemPrompt: "You are a helpful assistant.",
            userMessage: "Say hello in one word."
        )

        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
            if tokens.count >= 3 { break }
        }

        #expect(!tokens.isEmpty, "Stream should yield at least one token")

        await service.unloadModel()
        #expect(manager.modelState == .idle)
    }

    @Test func generate_completesWithNonEmptyResult() async throws {
        guard let (service, manager) = makeServiceIfModelAvailable() else { return }

        try await service.loadModel()

        let stream = try await service.generate(
            systemPrompt: "You are a concise assistant. Reply in one sentence.",
            userMessage: "What is 2+2?"
        )

        var fullResponse = ""
        for try await token in stream {
            fullResponse += token
        }

        #expect(!fullResponse.isEmpty, "Response should not be empty")

        await service.unloadModel()
        #expect(manager.modelState == .idle)
    }

    @Test func unloadModel_setsStateToIdle() async throws {
        guard let (service, manager) = makeServiceIfModelAvailable() else { return }

        try await service.loadModel()
        #expect(manager.modelState == .llmLoaded)

        await service.unloadModel()
        #expect(manager.modelState == .idle)
        #expect(manager.llmContainer == nil)
    }
}
