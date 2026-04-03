import SwiftUI
import UniformTypeIdentifiers

struct DocumentListView: View {
    @Environment(DocumentViewModel.self) private var viewModel
    @Environment(VectorStore.self) private var vectorStore
    @State private var showImporter = false
    @State private var selectedDocument: Document?
    @State private var documentToDelete: Document?

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            VStack(spacing: 0) {
                // Custom navigation header
                header

                // Content
                if selectedDocument != nil {
                    detailView
                } else if viewModel.documents.isEmpty {
                    emptyState
                } else {
                    documentList
                }
            }

            // Processing overlay
            if viewModel.isProcessing {
                processingOverlay
            }
        }
        .background(Color("BackgroundPrimary").ignoresSafeArea())
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .pdf]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    await viewModel.importDocument(url: url)
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .alert("Delete Document", isPresented: .init(
            get: { documentToDelete != nil },
            set: { if !$0 { documentToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                documentToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let doc = documentToDelete {
                    viewModel.deleteDocument(id: doc.id)
                    documentToDelete = nil
                }
            }
        } message: {
            if let doc = documentToDelete {
                Text("Are you sure you want to delete \"\(doc.name)\"? This will remove all its chunks and embeddings.")
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if selectedDocument != nil {
                Button {
                    withAnimation { selectedDocument = nil }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                        .foregroundStyle(Color("AccentColor"))
                }
            }

            Text(selectedDocument?.name ?? "Documents")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            if selectedDocument == nil {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color("AccentColor"))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(Color("AccentColor"))
            Text("No Documents Yet")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Tap + to import a document")
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Document List

    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.documents) { document in
                    Button {
                        withAnimation { selectedDocument = document }
                    } label: {
                        DocumentRow(document: document)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            documentToDelete = document
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let doc = selectedDocument {
            DocumentDetailView(
                document: doc,
                chunks: vectorStore.chunksForDocument(doc.id)
            )
        }
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color("AccentColor"))
                    .scaleEffect(1.3)

                Text(viewModel.processingStatus)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(Color("BackgroundSecondary"), in: RoundedRectangle(cornerRadius: 16))
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
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(document.dateAdded, style: .date)
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))

                    if document.chunkCount > 0 {
                        Text("\(document.chunkCount) chunks")
                            .font(.caption)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }
            }

            Spacer()

            if document.isProcessed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color("TextSecondary"))
        }
        .padding(14)
        .background(Color("BackgroundSecondary"), in: RoundedRectangle(cornerRadius: 12))
    }

    private var fileExtensionBadge: some View {
        Text(document.fileExtension.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color("AccentColor").opacity(0.15))
            .foregroundStyle(Color("AccentColor"))
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

@MainActor
private func makePreviewEnvironment() -> (ModelManager, VectorStore, RAGEngine, DocumentViewModel) {
    let mm = ModelManager()
    let vs = VectorStore()
    let es = EmbeddingService(modelManager: mm)
    let re = RAGEngine(embeddingService: es, vectorStore: vs, modelManager: mm)
    let dvm = DocumentViewModel(ragEngine: re, vectorStore: vs)
    return (mm, vs, re, dvm)
}

#Preview("Empty State") {
    let (mm, vs, re, dvm) = makePreviewEnvironment()
    DocumentListView()
        .environment(mm)
        .environment(vs)
        .environment(re)
        .environment(dvm)
        .preferredColorScheme(.dark)
}
