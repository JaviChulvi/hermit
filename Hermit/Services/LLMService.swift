import Foundation
import MLXLMCommon

@MainActor
final class LLMService {
    private let modelManager: ModelManager

    private static let defaultSystemPrompt = """
        You are Hermit, a helpful AI assistant running entirely on-device. \
        You are knowledgeable, concise, and friendly. \
        Answer the user's questions to the best of your ability. \
        If you don't know something, say so honestly. \
        Answer in the same language as the user.
        """

    private static let generateParams = GenerateParameters(
        maxTokens: 1024,
        temperature: 0.7,
        repetitionPenalty: 1.1,
        repetitionContextSize: 64
    )

    var isModelLoaded: Bool {
        modelManager.modelState == .llmLoaded && modelManager.llmContainer != nil
    }

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    // MARK: - Model Lifecycle

    func loadModel() async throws {
        try await modelManager.loadLLM()
    }

    func unloadModel() {
        modelManager.unloadLLM()
    }

    // MARK: - Chat

    /// Send a message with conversation history and optional RAG context.
    /// Creates a fresh session each time (LLM is reloaded between messages
    /// due to embedding swap), with history embedded in the user message.
    func chat(
        message: String,
        history: [ChatMessage],
        ragContext: String? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let container = modelManager.llmContainer else {
            throw LLMServiceError.modelNotLoaded
        }

        let systemPrompt = Self.buildSystemPrompt(ragContext: ragContext)

        // Build the full user message with conversation history included.
        // We embed history directly in the message because the LLM is reloaded
        // between messages (embedding swap), so ChatSession can't persist.
        let fullMessage = Self.buildMessage(current: message, history: history)

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: Self.generateParams
        )

        return session.streamResponse(to: fullMessage)
    }

    /// Reset is a no-op now (no persistent session), but kept for API compatibility.
    func resetSession() {}

    // MARK: - Private

    private static func buildMessage(current: String, history: [ChatMessage]) -> String {
        guard !history.isEmpty else { return current }

        var parts: [String] = ["[Conversation so far]"]
        for msg in history {
            switch msg.role {
            case .user: parts.append("User: \(msg.content)")
            case .assistant: parts.append("Hermit: \(msg.content)")
            case .system: break
            }
        }
        parts.append("")
        parts.append("[Current message]")
        parts.append("User: \(current)")
        return parts.joined(separator: "\n")
    }

    private static func buildSystemPrompt(ragContext: String?) -> String {
        guard let context = ragContext else {
            return defaultSystemPrompt
        }

        return """
            You are Hermit, a helpful AI assistant running entirely on-device. \
            You are knowledgeable, concise, and friendly.

            The user has imported documents. Here are relevant excerpts:
            ---
            \(context)
            ---

            RULES:
            - If the question relates to the documents, use the context above.
            - If the question is general (coding, conversation, etc.), answer freely with your own knowledge.
            - Be concise and helpful.
            - Answer in the same language as the user.
            """
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
