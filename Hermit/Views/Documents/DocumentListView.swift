import SwiftUI

struct DocumentListView: View {
    @State private var documents: [Document]
    @State private var showImporter = false

    init(documents: [Document] = []) {
        _documents = State(initialValue: documents)
    }

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(Color("AccentColor"))
                        Text("No Documents Yet")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Text("Tap + to import a document")
                            .font(.subheadline)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(documents) { document in
                            NavigationLink(value: document) {
                                DocumentRow(document: document)
                            }
                        }
                        .onDelete { indexSet in
                            documents.remove(atOffsets: indexSet)
                        }
                        .listRowBackground(Color("BackgroundSecondary"))
                    }
                    .scrollContentBackground(.hidden)
                    .navigationDestination(for: Document.self) { document in
                        DocumentDetailView(
                            document: document,
                            chunks: Self.sampleChunks(for: document)
                        )
                    }
                }
            }
            .background(Color("BackgroundPrimary"))
            .navigationTitle("Documents")
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color("BackgroundPrimary"), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color("AccentColor"))
                    }
                }
            }
        }
    }

    private static func sampleChunks(for document: Document) -> [TextChunk] {
        (0..<document.chunkCount).map { index in
            TextChunk(
                documentId: document.id,
                text: "Sample chunk \(index + 1) text content for preview purposes.",
                chunkIndex: index
            )
        }
    }
}

struct DocumentRow: View {
    let document: Document

    var body: some View {
        HStack(spacing: 12) {
            fileExtensionBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(document.dateAdded, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if document.chunkCount > 0 {
                        Text("\(document.chunkCount) chunks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if document.isProcessed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var fileExtensionBadge: some View {
        Text(document.fileExtension.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Previews

extension Document {
    static let previewSamples: [Document] = [
        Document(
            name: "Climate Change Report",
            fileExtension: "pdf",
            dateAdded: Date().addingTimeInterval(-86400 * 3),
            chunkCount: 12,
            isProcessed: true
        ),
        Document(
            name: "Meeting Notes Q1",
            fileExtension: "txt",
            dateAdded: Date().addingTimeInterval(-86400),
            chunkCount: 5,
            isProcessed: true
        ),
        Document(
            name: "Research Paper Draft",
            fileExtension: "pdf",
            dateAdded: Date(),
            chunkCount: 0,
            isProcessed: false
        ),
    ]
}

#Preview("Empty State") {
    DocumentListView()
}

#Preview("With Documents") {
    DocumentListView(documents: Document.previewSamples)
}
