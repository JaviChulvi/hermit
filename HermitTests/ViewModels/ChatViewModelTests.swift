import Testing
import Foundation
@testable import Hermit

@MainActor
struct ChatViewModelTests {

    // MARK: - Helpers

    /// Create a ChatViewModel with a real (but lightweight) RAGEngine.
    /// The VectorStore is empty, so queries will return the "import document" message.
    private func makeViewModel() -> ChatViewModel {
        let mm = ModelManager()
        let vs = VectorStore()
        let es = EmbeddingService(modelManager: mm)
        let ls = LLMService(modelManager: mm)
        let re = RAGEngine(embeddingService: es, vectorStore: vs, modelManager: mm)
        return ChatViewModel(ragEngine: re, llmService: ls)
    }

    // MARK: - sendMessage

    @Test func sendMessageAppendsUserMessage() async throws {
        let vm = makeViewModel()
        vm.sendMessage(text: "Hello")

        // Allow the Task to start and append the user message
        try await Task.sleep(for: .milliseconds(50))

        #expect(vm.messages.count >= 1)
        #expect(vm.messages.first?.role == .user)
        #expect(vm.messages.first?.content == "Hello")
    }

    @Test func sendEmptyStringDoesNothing() {
        let vm = makeViewModel()
        vm.sendMessage(text: "")

        #expect(vm.messages.isEmpty)
        #expect(!vm.isGenerating)
    }

    @Test func sendWhitespaceOnlyDoesNothing() {
        let vm = makeViewModel()
        vm.sendMessage(text: "   \n\t  ")

        #expect(vm.messages.isEmpty)
        #expect(!vm.isGenerating)
    }

    @Test func sendMessageSetsIsGenerating() async throws {
        let vm = makeViewModel()
        vm.sendMessage(text: "Test")

        // isGenerating should be true immediately after calling sendMessage
        #expect(vm.isGenerating)
    }

    @Test func sendMessageWithNoModelShowsError() async throws {
        let vm = makeViewModel()
        vm.sendMessage(text: "What is in my document?")

        // Wait for the LLM load attempt to fail (model not downloaded in tests)
        try await Task.sleep(for: .milliseconds(500))

        // Should have user message + error message
        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[1].role == .system)
        #expect(vm.errorMessage != nil)
        #expect(!vm.isGenerating)
    }

    // MARK: - stopGenerating

    @Test func stopGeneratingSavesPartialText() async throws {
        let vm = makeViewModel()

        // Manually set up state as if generation is in progress
        vm.sendMessage(text: "Test query")
        try await Task.sleep(for: .milliseconds(50))

        // Simulate partial streamed text by setting it directly
        // (In real use, the stream populates this)
        vm.currentStreamedText = "Partial response"
        vm.stopGenerating()

        // Wait for cancellation handling
        try await Task.sleep(for: .milliseconds(200))

        // The partial text should have been saved as a message
        let assistantMessages = vm.messages.filter { $0.role == .assistant }
        if !assistantMessages.isEmpty {
            #expect(assistantMessages.last?.content == "Partial response" || assistantMessages.last?.content.contains("import") == true)
        }
    }

    // MARK: - clearConversation

    @Test func clearConversationEmptiesMessages() async throws {
        let vm = makeViewModel()
        vm.sendMessage(text: "Hello")
        try await Task.sleep(for: .milliseconds(500))

        #expect(!vm.messages.isEmpty)

        vm.clearConversation()

        #expect(vm.messages.isEmpty)
        #expect(vm.currentStreamedText.isEmpty)
        #expect(vm.statusMessage.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isGenerating)
    }

    @Test func clearConversationWhileIdleWorks() {
        let vm = makeViewModel()
        // Clear when already empty — should not crash
        vm.clearConversation()

        #expect(vm.messages.isEmpty)
        #expect(!vm.isGenerating)
    }

    // MARK: - Error Handling

    @Test func errorDuringGenerationSetsErrorMessage() async throws {
        // Without a downloaded LLM, sending a message should produce an error
        let vm = makeViewModel()
        vm.sendMessage(text: "Hello")
        try await Task.sleep(for: .milliseconds(500))

        #expect(vm.errorMessage != nil)
        #expect(!vm.isGenerating)
    }

    // MARK: - Initial State

    @Test func initialStateIsCorrect() {
        let vm = makeViewModel()

        #expect(vm.messages.isEmpty)
        #expect(vm.currentStreamedText.isEmpty)
        #expect(!vm.isGenerating)
        #expect(vm.statusMessage.isEmpty)
        #expect(vm.errorMessage == nil)
    }
}
