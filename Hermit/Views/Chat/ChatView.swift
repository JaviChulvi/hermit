import SwiftUI

struct ChatView: View {
    @State private var messageText = ""

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()

                ContentUnavailableView(
                    "No Documents Yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Import a document to start chatting")
                )

                Spacer()
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
            .disabled(true)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview {
    ChatView()
}
