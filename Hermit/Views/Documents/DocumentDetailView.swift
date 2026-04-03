import SwiftUI

struct DocumentDetailView: View {
    let document: Document
    let chunks: [TextChunk]

    var body: some View {
        List {
            Section {
                LabeledContent("File Type", value: document.fileExtension.uppercased())
                LabeledContent("Date Added") {
                    Text(document.dateAdded, style: .date)
                }
                LabeledContent("Status") {
                    Label(
                        document.isProcessed ? "Processed" : "Pending",
                        systemImage: document.isProcessed ? "checkmark.circle.fill" : "clock"
                    )
                    .foregroundStyle(document.isProcessed ? .green : .orange)
                }
            } header: {
                Text("Info")
                    .foregroundStyle(Color("TextSecondary"))
            }
            .listRowBackground(Color("BackgroundSecondary"))

            Section {
                if chunks.isEmpty {
                    Text("No chunks yet — document has not been processed.")
                        .foregroundStyle(Color("TextSecondary"))
                } else {
                    ForEach(chunks) { chunk in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chunk \(chunk.chunkIndex + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(Color("TextSecondary"))
                            Text(String(chunk.text.prefix(100)))
                                .font(.body)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Chunks (\(chunks.count))")
                    .foregroundStyle(Color("TextSecondary"))
            }
            .listRowBackground(Color("BackgroundSecondary"))
        }
        .scrollContentBackground(.hidden)
        .background(Color("BackgroundPrimary"))
        .navigationTitle(document.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let doc = Document.previewSamples[0]
    let chunks = (0..<3).map { i in
        TextChunk(
            documentId: doc.id,
            text: "This is the content of chunk \(i + 1). It contains a preview of the text that was extracted from the document during the chunking process.",
            chunkIndex: i
        )
    }

    NavigationStack {
        DocumentDetailView(document: doc, chunks: chunks)
    }
}
