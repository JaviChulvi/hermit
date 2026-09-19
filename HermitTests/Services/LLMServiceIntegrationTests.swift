import Testing
import Foundation
@testable import Hermit

// Explicitly opt in on a physical device with both models downloaded.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HERMIT_MODEL_TESTS"] == "1"), .serialized)
@MainActor
struct LLMServiceIntegrationTests {
    @Test func structuredConversationAndModelSwap() async throws {
        let manager = ModelManager()
        try #require(manager.llmModelDownloaded && manager.embeddingModelDownloaded)
        defer { manager.unloadAll() }
        let service = LLMService(modelManager: manager)
        let question = ChatMessage(role: .user, content: "My name is Elena. Say hello briefly.")
        var updates: [String] = []
        let answer = try await service.respond(to: question, history: []) { updates.append($0) }
        #expect(!answer.content.isEmpty)
        #expect(updates.last == answer.content)
        #expect(manager.modelState == .llmLoaded)

        let followup = ChatMessage(role: .user, content: "What is my name?")
        let response = try await service.respond(to: followup, history: [question, answer]) { _ in }
        #expect(response.content.localizedCaseInsensitiveContains("Elena"))

        _ = try await EmbeddingService(modelManager: manager).embed(text: "A short document.")
        #expect(manager.modelState == .idle)
        let rebuilt = try await service.respond(to: followup, history: [question, answer]) { _ in }
        #expect(rebuilt.content.localizedCaseInsensitiveContains("Elena"))
    }
}
