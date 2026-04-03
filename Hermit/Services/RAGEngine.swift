import Foundation

@Observable
@MainActor
class RAGEngine {
    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore
    private let modelManager: ModelManager

    init(embeddingService: EmbeddingService, vectorStore: VectorStore, modelManager: ModelManager) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.modelManager = modelManager
    }

    /// Full ingest pipeline: extract text → chunk → embed → store.
    /// Returns a `Document` with metadata about the ingested file.
    func ingestDocument(url: URL, progress: @MainActor @escaping (String) -> Void) async throws -> Document {
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        let documentId = UUID()

        // 1. Extract text
        progress("Extracting text...")
        let text = try DocumentProcessor.extractText(from: url)

        // 2. Chunk text
        progress("Splitting into chunks...")
        let chunkStrings = ChunkingStrategy.chunk(text: text)

        // 3. Generate embeddings
        progress("Generating embeddings...")
        let embeddings = try await embeddingService.embed(chunks: chunkStrings) { @Sendable completed, total in
            Task { @MainActor in
                progress("Embedding chunk \(completed)/\(total)...")
            }
        }

        // 4. Create TextChunk objects with embeddings
        let textChunks = chunkStrings.enumerated().map { index, text in
            TextChunk(
                documentId: documentId,
                text: text,
                embedding: embeddings[index],
                chunkIndex: index
            )
        }

        // 5. Save to VectorStore
        progress("Saving...")
        vectorStore.addChunks(textChunks, forDocument: documentId)

        // 6. Return Document metadata
        let document = Document(
            id: documentId,
            name: fileName,
            fileExtension: fileExtension,
            chunkCount: textChunks.count,
            isProcessed: true
        )

        return document
    }

    /// Retrieve the most relevant chunks for a query string.
    func retrieveContext(for query: String, topK: Int = 3) async throws -> [TextChunk] {
        // 1. Load embedding model and embed the query
        let queryEmbedding = try await embeddingService.embed(text: query)

        // 2. Unload embedding model to free RAM
        modelManager.unloadEmbedding()

        // 3. Search VectorStore
        return vectorStore.search(queryEmbedding: queryEmbedding, topK: topK)
    }
}
