import Testing
import Foundation
import UIKit
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

    @Test func cancellationAndMemoryWarningDuringGeneration() async throws {
        let manager = ModelManager()
        try #require(manager.llmModelDownloaded && manager.embeddingModelDownloaded)
        defer { manager.unloadAll() }
        let service = LLMService(modelManager: manager)

        for sendMemoryWarning in [false, true] {
            var interrupted = false
            var generation: Task<ChatMessage, Error>?
            generation = Task {
                try await service.respond(to: ChatMessage(role: .user,
                    content: "Count from 1 to 500, writing every number on a separate line."), history: []) { text in
                    guard !interrupted, !text.isEmpty else { return }
                    interrupted = true
                    if sendMemoryWarning {
                        NotificationCenter.default.post(
                            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
                    } else {
                        generation?.cancel()
                    }
                }
            }
            do {
                _ = try await generation!.value
                Issue.record("Expected cancellation during GPU generation")
            } catch is CancellationError {}
            generation = nil
            #expect(interrupted)
            #expect(!manager.isBusy)
            if sendMemoryWarning { #expect(manager.modelState == .idle) }
            // A completed cancellation must permit a safe model swap and fresh generation.
            _ = try await EmbeddingService(modelManager: manager).embed(text: "Recovery after cancellation.")
            #expect(manager.modelState == .idle)
            let reply = try await service.respond(
                to: ChatMessage(role: .user, content: "Reply only OK."), history: [], onUpdate: { _ in })
            #expect(!reply.content.isEmpty)
            manager.unloadAll()
        }
    }
}
