import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill") {
                ChatView()
            }

            Tab("Documents", systemImage: "doc.text.fill") {
                DocumentListView()
            }

            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tint(.accentColor)
    }
}

#Preview {
    ContentView()
}
