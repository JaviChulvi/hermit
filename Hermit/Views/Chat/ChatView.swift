import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(DocumentViewModel.self) private var documentViewModel
    @Environment(ModelManager.self) private var modelManager
    @Environment(\.keyboardVisible) private var keyboardVisible
    @State private var messageText = ""
    @State private var showClearAlert = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Custom navigation header
            header

            // Content
            if viewModel.messages.isEmpty && !viewModel.isGenerating {
                emptyState
            } else {
                messageList
            }

            // Input bar
            inputBar
        }
        .background(Color("BackgroundPrimary").ignoresSafeArea())
        .alert("Clear Conversation", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                viewModel.clearConversation()
            }
        } message: {
            Text("This will remove all messages. Your documents will not be affected.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Chat")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Spacer()
            if !viewModel.messages.isEmpty {
                Button {
                    showClearAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            PrivacyBadge()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 52))
                .foregroundStyle(Color("AccentColor"))
            Text("Start a Conversation")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Chat with Hermit or import documents for Q&A")
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, onRetry: message.role == .system ? {
                            viewModel.retryLastMessage()
                        } : nil)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    // Live streaming bubble
                    if viewModel.isGenerating && !viewModel.currentStreamedText.isEmpty {
                        MessageBubble(message: ChatMessage(
                            role: .assistant,
                            content: viewModel.currentStreamedText
                        ))
                        .id("streaming-bubble")
                    }

                    // Model loading / status indicator
                    if viewModel.isGenerating && viewModel.currentStreamedText.isEmpty {
                        VStack(spacing: 6) {
                            if modelManager.modelState == .transitioning {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(Color("AccentColor"))
                                    Text("Loading AI model...")
                                        .font(.caption)
                                        .foregroundStyle(Color("TextSecondary"))
                                }
                            } else if !viewModel.statusMessage.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(Color("AccentColor"))
                                    Text(viewModel.statusMessage)
                                        .font(.caption)
                                        .foregroundStyle(Color("TextSecondary"))
                                }
                            }
                            StreamingIndicator()
                        }
                        .id("streaming")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: viewModel.currentStreamedText) {
                withAnimation {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: viewModel.isGenerating) {
                if viewModel.isGenerating {
                    withAnimation {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isGenerating {
            if !viewModel.currentStreamedText.isEmpty {
                proxy.scrollTo("streaming-bubble", anchor: .bottom)
            } else {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        } else if let lastId = viewModel.messages.last?.id {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask anything...", text: $messageText)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color("BackgroundSecondary"), in: RoundedRectangle(cornerRadius: 22))
                .focused($isTextFieldFocused)
                .onSubmit { send() }
                .disabled(viewModel.isGenerating)

            if viewModel.isGenerating {
                Button {
                    viewModel.stopGenerating()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.8), in: Circle())
                }
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 36, height: 36)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, keyboardVisible ? 0 : 72)
    }

    // MARK: - Actions

    private func send() {
        let text = messageText
        messageText = ""
        viewModel.sendMessage(text: text)
    }
}

#Preview("Empty State") {
    let mm = ModelManager()
    let vs = VectorStore()
    let es = EmbeddingService(modelManager: mm)
    let ls = LLMService(modelManager: mm)
    let re = RAGEngine(embeddingService: es, vectorStore: vs, modelManager: mm)

    ChatView()
        .environment(ChatViewModel(ragEngine: re, llmService: ls))
        .environment(DocumentViewModel(ragEngine: re, vectorStore: vs))
        .environment(mm)
        .preferredColorScheme(.dark)
}
