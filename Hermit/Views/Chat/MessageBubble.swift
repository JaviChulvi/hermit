import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .foregroundStyle(bubbleForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user { Spacer() }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    private var bubbleBackground: Color {
        message.role == .user ? Color("UserBubble") : Color("BackgroundSecondary")
    }

    private var bubbleForeground: Color {
        message.role == .user ? .white : .primary
    }
}

#Preview("User Message") {
    MessageBubble(message: ChatMessage(role: .user, content: "What does this document say about climate change?"))
}

#Preview("Assistant Message") {
    MessageBubble(message: ChatMessage(role: .assistant, content: "The document discusses several key impacts of climate change, including rising sea levels and increased frequency of extreme weather events."))
}
