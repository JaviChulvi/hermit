import SwiftUI

struct DocumentDetailView: View {
    let document: Document
    let chunks: [TextChunk]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Info section
                VStack(alignment: .leading, spacing: 8) {
                    Text("INFO")
                        .font(.caption.bold())
                        .foregroundStyle(Color("TextSecondary"))
                        .padding(.leading, 4)

                    VStack(spacing: 1) {
                        infoRow(title: "File Type", value: document.fileExtension.uppercased())
                        infoRow(title: "Date Added", value: document.dateAdded.formatted(date: .abbreviated, time: .omitted))

                        HStack {
                            Text("Status")
                                .foregroundStyle(.white)
                            Spacer()
                            Label(
                                document.isProcessed ? "Processed" : "Pending",
                                systemImage: document.isProcessed ? "checkmark.circle.fill" : "clock"
                            )
                            .foregroundStyle(document.isProcessed ? .green : .orange)
                            .font(.body)
                        }
                        .padding(14)
                        .background(Color("BackgroundSecondary"))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Chunks section
                VStack(alignment: .leading, spacing: 8) {
                    Text("CHUNKS (\(chunks.count))")
                        .font(.caption.bold())
                        .foregroundStyle(Color("TextSecondary"))
                        .padding(.leading, 4)

                    if chunks.isEmpty {
                        Text("No chunks yet — document has not been processed.")
                            .foregroundStyle(Color("TextSecondary"))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color("BackgroundSecondary"))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(spacing: 1) {
                            ForEach(chunks) { chunk in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Chunk \(chunk.chunkIndex + 1)")
                                            .font(.caption.bold())
                                            .foregroundStyle(Color("TextSecondary"))

                                        Spacer()

                                        if chunk.embedding != nil {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    Text(String(chunk.text.prefix(100)))
                                        .font(.body)
                                        .foregroundStyle(.white)
                                        .lineLimit(3)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color("BackgroundSecondary"))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .background(Color("BackgroundPrimary").ignoresSafeArea())
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .foregroundStyle(Color("TextSecondary"))
        }
        .padding(14)
        .background(Color("BackgroundSecondary"))
    }
}

#Preview {
    let doc = Document(name: "Climate Change Report", fileExtension: "pdf", chunkCount: 3, isProcessed: true)
    let chunks = (0..<3).map { i in
        TextChunk(
            documentId: doc.id,
            text: "This is the content of chunk \(i + 1). It contains a preview of the text that was extracted from the document during the chunking process.",
            embedding: [Float](repeating: 0.1, count: 384),
            chunkIndex: i
        )
    }

    DocumentDetailView(document: doc, chunks: chunks)
        .preferredColorScheme(.dark)
}
