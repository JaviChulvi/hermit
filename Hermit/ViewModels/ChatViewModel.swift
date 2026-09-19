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
    private var lastFailedMessage: ChatMessage?
    var searchDocuments = false

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
        guard !isGenerating, !trimmed.isEmpty || image != nil else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let imageData = image?.jpegData(compressionQuality: 0.8)
        let userMessage = ChatMessage(role: .user, content: trimmed, imageData: imageData)
        messages.append(userMessage)
        lastFailedMessage = nil

        isGenerating = true
        currentStreamedText = ""
        statusMessage = ""
        errorMessage = nil

        generationTask = Task {
            do {
                let history = Array(messages.dropLast())

                // 1. Retrieve RAG context if documents exist
                var ragContext: String? = nil
                if searchDocuments && hasDocuments && !trimmed.isEmpty {
                    statusMessage = "Searching documents..."
                    ragContext = try await ragEngine.retrieveContext(for: trimmed)
                        ?? "No relevant document excerpts were found."
                }

                try Task.checkCancellation()
                statusMessage = "Preparing response..."
                let assistantMessage = try await llmService.respond(
                    to: userMessage, history: history, ragContext: ragContext
                ) { [weak self] text in
                    self?.statusMessage = ""
                    self?.currentStreamedText = text
                }
                messages.append(assistantMessage)
                currentStreamedText = ""
                statusMessage = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                savePartialResponse()
            } catch {
                savePartialResponse()
                errorMessage = error.localizedDescription
                lastFailedMessage = userMessage

                UINotificationFeedbackGenerator().notificationOccurred(.error)
                let errorMsg = ChatMessage(role: .system, content: error.localizedDescription)
                messages.append(errorMsg)
            }

            isGenerating = false
        }
    }

    func retryLastMessage() {
        guard !isGenerating, let message = lastFailedMessage else { return }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages.removeSubrange(index...)
        }
        let image = message.imageData.flatMap { UIImage(data: $0) }
        sendMessage(text: message.content, image: image)
    }

    // MARK: - Cancellation

    func stopGenerating() {
        generationTask?.cancel()
    }

    // MARK: - Clear Conversation

    func clearConversation() async {
        stopGenerating()
        await generationTask?.value
        generationTask = nil
        lastFailedMessage = nil
        messages.removeAll()
        currentStreamedText = ""
        statusMessage = ""
        errorMessage = nil
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
