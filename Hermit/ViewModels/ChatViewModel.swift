import CoreImage
import Foundation
import UIKit

@Observable
@MainActor
class ChatViewModel {
    private(set) var messages: [ChatMessage] = []
    var currentStreamedText: String = ""
    private(set) var isGenerating: Bool = false
    var statusMessage: String = ""
    var errorMessage: String?
    private(set) var lastFailedQuery: String?

    private let ragEngine: RAGEngine
    private let llmService: LLMService
    private var generationTask: Task<Void, Never>?

    var hasDocuments: Bool {
        ragEngine.hasDocuments
    }

    init(ragEngine: RAGEngine, llmService: LLMService) {
        self.ragEngine = ragEngine
        self.llmService = llmService
    }

    // MARK: - Send Message

    func sendMessage(text: String, image: UIImage? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let imageData = image?.jpegData(compressionQuality: 0.8)
        let ciImage = image.flatMap { CIImage(image: $0) }
        let userMessage = ChatMessage(role: .user, content: trimmed, imageData: imageData)
        messages.append(userMessage)
        lastFailedQuery = nil

        isGenerating = true
        currentStreamedText = ""
        statusMessage = ""
        errorMessage = nil

        generationTask = Task {
            do {
                let history = Array(messages.dropLast())

                // 1. Retrieve RAG context if documents exist
                var ragContext: String? = nil
                if hasDocuments {
                    // Release chat session so the LLM container can be fully freed
                    // before embedding model loads (they can't coexist in memory)
                    llmService.resetSession()
                    statusMessage = "Searching documents..."
                    ragContext = try await ragEngine.retrieveContext(for: trimmed)
                }

                // 2. Load LLM
                if !llmService.isModelLoaded {
                    statusMessage = "Loading model..."
                    try await llmService.loadModel()
                }
                statusMessage = ""

                // 3. Generate response with history + optional image + optional RAG context
                let messageText = trimmed.isEmpty ? "Describe this image." : trimmed
                let stream = try await llmService.chat(
                    message: messageText,
                    image: ciImage,
                    history: history,
                    ragContext: ragContext
                )

                for try await token in stream {
                    currentStreamedText += token
                }

                let assistantMessage = ChatMessage(role: .assistant, content: currentStreamedText)
                messages.append(assistantMessage)
                currentStreamedText = ""
                statusMessage = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                savePartialResponse()
            } catch {
                savePartialResponse()
                errorMessage = error.localizedDescription
                lastFailedQuery = trimmed

                UINotificationFeedbackGenerator().notificationOccurred(.error)
                let errorMsg = ChatMessage(role: .system, content: error.localizedDescription)
                messages.append(errorMsg)
            }

            isGenerating = false
        }
    }

    func retryLastMessage() {
        guard let query = lastFailedQuery else { return }

        if let last = messages.last, last.role == .system {
            messages.removeLast()
        }
        if let last = messages.last, last.role == .user {
            messages.removeLast()
        }

        lastFailedQuery = nil
        sendMessage(text: query)
    }

    // MARK: - Cancellation

    func stopGenerating() {
        generationTask?.cancel()
        generationTask = nil
    }

    // MARK: - Clear Conversation

    func clearConversation() {
        messages.removeAll()
        currentStreamedText = ""
        statusMessage = ""
        errorMessage = nil
        stopGenerating()
        llmService.resetSession()
    }

    // MARK: - Private

    private func savePartialResponse() {
        if !currentStreamedText.isEmpty {
            let partialMessage = ChatMessage(role: .assistant, content: currentStreamedText)
            messages.append(partialMessage)
            currentStreamedText = ""
        }
        statusMessage = ""
    }
}
