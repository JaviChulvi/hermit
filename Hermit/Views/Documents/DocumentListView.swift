import SwiftUI

struct DocumentListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Documents Yet",
                systemImage: "doc.text",
                description: Text("Tap + to import a document")
            )
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // No action yet
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

#Preview {
    DocumentListView()
}
