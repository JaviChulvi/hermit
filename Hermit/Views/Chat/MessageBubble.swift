import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    var onRetry: (() -> Void)?

    var body: some View {
        if message.role == .system {
            errorBubble
        } else {
            standardBubble
        }
    }

    private var standardBubble: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 6) {
                    // Image thumbnail if present
                    if let imageData = message.imageData,
                        let uiImage = UIImage(data: imageData)
                    {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Text content
                    if !message.content.isEmpty {
                        if message.role == .assistant {
                            Text(LocalizedStringKey(message.content))
                        } else {
                            Text(message.content)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .foregroundStyle(bubbleForeground)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Color("TextSecondary"))
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user { Spacer() }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    private var errorBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    Text(message.content)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Text("Retry")
                            .font(.caption.bold())
                            .foregroundStyle(Color("AccentColor"))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    private var bubbleBackground: Color {
        message.role == .user ? Color("UserBubble") : Color("BackgroundSecondary")
    }

    private var bubbleForeground: Color {
        message.role == .user ? .white : .white
    }
}

#Preview("User Message") {
    MessageBubble(message: ChatMessage(role: .user, content: "What does this document say about climate change?"))
}

#Preview("Assistant Message") {
    MessageBubble(message: ChatMessage(role: .assistant, content: "The document discusses several key impacts of climate change, including rising sea levels and increased frequency of extreme weather events."))
}
