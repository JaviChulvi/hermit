import SwiftUI

struct ChatView: View {
    @State private var messageText = ""
    @State private var messages: [ChatMessage]
    @State private var isGenerating = false

    init(messages: [ChatMessage] = []) {
        _messages = State(initialValue: messages)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Documents Yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Import a document to start chatting")
                    )
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
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
            }
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
            .navigationTitle("Chat")
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask about your documents...", text: $messageText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .disabled(true)

            Button {
                // No action yet
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17))
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview("Empty State") {
    ChatView()
}

#Preview("With Messages") {
    let sampleMessages: [ChatMessage] = [
        ChatMessage(role: .user, content: "What are the main points of the document?"),
        ChatMessage(role: .assistant, content: "The document covers three main topics:\n\n1. Climate change impacts on coastal cities\n2. Proposed mitigation strategies\n3. Economic projections for the next decade"),
        ChatMessage(role: .user, content: "Tell me more about the mitigation strategies."),
        ChatMessage(role: .assistant, content: "The document outlines several key mitigation strategies including renewable energy adoption, carbon capture technology, and urban planning reforms designed to reduce emissions by 40% before 2040.")
    ]

    ChatView(messages: sampleMessages)
}
