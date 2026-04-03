import Foundation

@Observable
@MainActor
class ChatViewModel {
    private(set) var messages: [ChatMessage] = []
    var currentStreamedText: String = ""
    private(set) var isGenerating: Bool = false
    var statusMessage: String = ""
    var errorMessage: String?

    private let ragEngine: RAGEngine
    private var generationTask: Task<Void, Never>?

    init(ragEngine: RAGEngine) {
        self.ragEngine = ragEngine
    }

    // MARK: - Send Message

    func sendMessage(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Append user message
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        // Start generation
        isGenerating = true
        currentStreamedText = ""
        statusMessage = ""
        errorMessage = nil

        generationTask = Task {
            do {
                let stream = ragEngine.query(prompt: trimmed) { [weak self] status in
                    self?.statusMessage = status
                }

                for try await token in stream {
                    currentStreamedText += token
                }

                // Stream completed — create assistant message
                let assistantMessage = ChatMessage(role: .assistant, content: currentStreamedText)
                messages.append(assistantMessage)
                currentStreamedText = ""
                statusMessage = ""
            } catch is CancellationError {
                // Save partial text if any was streamed
                savePartialResponse()
            } catch {
                // Save partial text on error too
                savePartialResponse()
                errorMessage = error.localizedDescription
            }

            isGenerating = false
        }
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
