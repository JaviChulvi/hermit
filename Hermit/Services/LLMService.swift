import Foundation
import MLXLMCommon

final class LLMService: Sendable {
    private let modelManager: ModelManager

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    // MARK: - Model Lifecycle

    /// Load the LLM via ModelManager (handles mutual exclusion with embedding model).
    func loadModel() async throws {
        try await modelManager.loadLLM()
    }

    /// Unload the LLM and free GPU memory.
    func unloadModel() async {
        await modelManager.unloadLLM()
    }

    // MARK: - Generation

    /// Generate a streaming response using the loaded LLM.
    /// - Parameters:
    ///   - systemPrompt: System instructions (e.g., RAG context).
    ///   - userMessage: The user's message.
    /// - Returns: An `AsyncThrowingStream` that yields tokens as they are generated.
    func generate(systemPrompt: String, userMessage: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let container = await modelManager.llmContainer else {
            throw LLMServiceError.modelNotLoaded
        }

        let generateParameters = GenerateParameters(
            maxTokens: 1024,
            temperature: 0.7,
            repetitionPenalty: 1.1,
            repetitionContextSize: 64
        )

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: generateParameters
        )

        return session.streamResponse(to: userMessage)
    }

    // MARK: - Session Management

    /// Create a new ChatSession bound to the currently loaded model.
    /// Useful for multi-turn conversations where you manage the session externally.
    func makeSession(systemPrompt: String? = nil) async throws -> ChatSession {
        guard let container = await modelManager.llmContainer else {
            throw LLMServiceError.modelNotLoaded
        }

        let generateParameters = GenerateParameters(
            maxTokens: 1024,
            temperature: 0.7,
            repetitionPenalty: 1.1,
            repetitionContextSize: 64
        )

        return ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: generateParameters
        )
    }
}

enum LLMServiceError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "LLM is not loaded"
        }
    }
}
