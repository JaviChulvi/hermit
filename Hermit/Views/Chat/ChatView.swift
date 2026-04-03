import SwiftUI

struct ChatView: View {
    @State private var messageText = ""
    @State private var messages: [ChatMessage]
    @State private var isGenerating = false

    init(messages: [ChatMessage] = []) {
        _messages = State(initialValue: messages)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom navigation header
            header

            // Content
            if messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            // Input bar
            inputBar
        }
        .background(Color("BackgroundPrimary").ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Chat")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Spacer()
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
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(Color("AccentColor"))
            Text("No Documents Yet")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Import a document to start chatting")
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if isGenerating {
                        StreamingIndicator()
                            .id("streaming")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) {
                withAnimation {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: isGenerating) {
                if isGenerating {
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask about your documents...", text: $messageText)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color("BackgroundSecondary"), in: RoundedRectangle(cornerRadius: 22))
                .disabled(true)

            Button {
                // No action yet
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 36, height: 36)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview("Empty State") {
    ChatView()
        .preferredColorScheme(.dark)
}

#Preview("With Messages") {
    let sampleMessages: [ChatMessage] = [
        ChatMessage(role: .user, content: "What are the main points of the document?"),
        ChatMessage(role: .assistant, content: "The document covers three main topics:\n\n1. Climate change impacts on coastal cities\n2. Proposed mitigation strategies\n3. Economic projections for the next decade"),
        ChatMessage(role: .user, content: "Tell me more about the mitigation strategies."),
        ChatMessage(role: .assistant, content: "The document outlines several key mitigation strategies including renewable energy adoption, carbon capture technology, and urban planning reforms designed to reduce emissions by 40% before 2040.")
    ]

    ChatView(messages: sampleMessages)
        .preferredColorScheme(.dark)
}
