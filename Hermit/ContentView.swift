import SwiftUI

enum AppTab: Int, CaseIterable {
    case chat, documents, settings

    var title: String {
        switch self {
        case .chat: "Chat"
        case .documents: "Documents"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right.fill"
        case .documents: "doc.text.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .chat

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
            Group {
                switch selectedTab {
                case .chat:
                    ChatView()
                case .documents:
                    DocumentListView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            customTabBar
        }
        .background(Color("BackgroundPrimary").ignoresSafeArea())
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        Text(tab.title)
                            .font(.caption2)
                    }
                    .foregroundStyle(selectedTab == tab ? Color("AccentColor") : Color("TextSecondary"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        .background(
            Color("BackgroundSecondary")
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}

#Preview {
    let mm = ModelManager()
    let vs = VectorStore()
    let es = EmbeddingService(modelManager: mm)
    let ls = LLMService(modelManager: mm)
    let re = RAGEngine(embeddingService: es, vectorStore: vs, modelManager: mm, llmService: ls)
    let dvm = DocumentViewModel(ragEngine: re, vectorStore: vs)
    let cvm = ChatViewModel(ragEngine: re)

    ContentView()
        .environment(mm)
        .environment(vs)
        .environment(re)
        .environment(dvm)
        .environment(cvm)
        .preferredColorScheme(.dark)
}
