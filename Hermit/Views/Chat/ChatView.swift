import PhotosUI
import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(DocumentViewModel.self) private var documentViewModel
    @Environment(ModelManager.self) private var modelManager
    @Environment(\.keyboardVisible) private var keyboardVisible
    @State private var messageText = ""
    @State private var showClearAlert = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var showCamera = false
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                pendingImage = image
            }
            .ignoresSafeArea()
        }
        .alert("Clear Conversation", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task { await viewModel.clearConversation() }
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
            if viewModel.hasDocuments {
                Button {
                    viewModel.searchDocuments.toggle()
                } label: {
                    Label(viewModel.searchDocuments ? "Documents" : "General", systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(viewModel.searchDocuments ? Color("AccentColor") : Color("TextSecondary"))
                }
                .disabled(viewModel.isGenerating)
                .accessibilityHint("Choose whether to search your imported documents")
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
                scrollToBottom(proxy: proxy)
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
        VStack(spacing: 8) {
            // Image preview strip
            if let pendingImage {
                HStack {
                    Image(uiImage: pendingImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                self.pendingImage = nil
                                selectedPhoto = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, Color("BackgroundSecondary"))
                            }
                            .offset(x: 6, y: -6)
                        }
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 8) {
                // Camera button
                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 18))
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 36, height: 36)
                }
                .disabled(viewModel.isGenerating)

                // Photo picker button
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 36, height: 36)
                }
                .disabled(viewModel.isGenerating)

                TextField("Ask anything...", text: $messageText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color("BackgroundSecondary"), in: RoundedRectangle(cornerRadius: 22))
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
                    .disabled(hasNoInput)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, keyboardVisible ? 0 : 72)
        .onChange(of: selectedPhoto) { _, item in
            Task {
                if let item,
                    let data = try? await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                {
                    pendingImage = image
                }
            }
        }
    }

    private var hasNoInput: Bool {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingImage == nil
    }

    // MARK: - Actions

    private func send() {
        let text = messageText
        let image = pendingImage
        messageText = ""
        pendingImage = nil
        selectedPhoto = nil
        viewModel.sendMessage(text: text, image: image)
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImageCaptured: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImageCaptured = onImageCaptured
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

#Preview("Empty State") {
    let mm = ModelManager()
    let vs = VectorStore()
    let es = EmbeddingService(modelManager: mm)
    let ls = LLMService(modelManager: mm)
    let re = RAGEngine(embeddingService: es, vectorStore: vs)

    ChatView()
        .environment(ChatViewModel(ragEngine: re, llmService: ls))
        .environment(DocumentViewModel(ragEngine: re, vectorStore: vs))
        .environment(mm)
        .preferredColorScheme(.dark)
}
