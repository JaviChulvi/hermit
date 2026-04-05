import Foundation
import os

private let logger = Logger(subsystem: "com.hermit.app", category: "RAGEngine")

@Observable
@MainActor
class RAGEngine {
    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore
    private let modelManager: ModelManager

    /// Whether documents have been imported and are available for RAG queries.
    var hasDocuments: Bool { !vectorStore.chunks.isEmpty }

    /// Minimum cosine similarity for a chunk to be considered relevant.
    static let relevanceThreshold: Float = 0.2

    init(embeddingService: EmbeddingService, vectorStore: VectorStore, modelManager: ModelManager) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.modelManager = modelManager
    }

    // MARK: - Ingest Pipeline

    /// Full ingest pipeline: extract text → chunk → embed → store.
    /// Returns a `Document` with metadata about the ingested file.
    func ingestDocument(url: URL, progress: @MainActor @escaping (String) -> Void) async throws -> Document {
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        let documentId = UUID()

        logger.info("=== INGEST START === file: \(fileName).\(fileExtension), id: \(documentId)")
        logger.info("Source URL: \(url.path)")

        // 1. Extract text
        progress("Extracting text...")
        logger.info("Step 1: Extracting text...")
        let text: String
        do {
            text = try DocumentProcessor.extractText(from: url)
            logger.info("Text extracted: \(text.count) characters, \(text.split(separator: " ").count) words")
        } catch {
            logger.error("Text extraction failed: \(error.localizedDescription)")
            throw error
        }

        // 2. Chunk text
        progress("Splitting into chunks...")
        logger.info("Step 2: Chunking text...")
        let chunkStrings = ChunkingStrategy.chunk(text: text)
        logger.info("Created \(chunkStrings.count) chunks")
        for (i, chunk) in chunkStrings.enumerated() {
            logger.debug("  Chunk \(i): \(chunk.split(separator: " ").count) words, \(chunk.count) chars")
        }

        // 3. Generate embeddings
        progress("Generating embeddings...")
        logger.info("Step 3: Generating embeddings for \(chunkStrings.count) chunks...")
        let embeddings: [[Float]]
        do {
            embeddings = try await embeddingService.embed(chunks: chunkStrings) { @Sendable completed, total in
                Task { @MainActor in
                    progress("Embedding chunk \(completed)/\(total)...")
                }
            }
            logger.info("All \(embeddings.count) embeddings generated, dimension: \(embeddings.first?.count ?? 0)")
        } catch {
            logger.error("Embedding generation failed: \(error.localizedDescription)")
            logger.error("Error type: \(type(of: error)), full: \(String(describing: error))")
            throw error
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
        logger.info("Step 4: Saving \(textChunks.count) chunks to VectorStore...")
        vectorStore.addChunks(textChunks, forDocument: documentId)
        logger.info("Saved. Total chunks in store: \(self.vectorStore.chunks.count)")

        // 6. Return Document metadata
        let document = Document(
            id: documentId,
            name: fileName,
            fileExtension: fileExtension,
            chunkCount: textChunks.count,
            isProcessed: true
        )

        logger.info("=== INGEST COMPLETE === \(fileName): \(textChunks.count) chunks embedded and stored")
        return document
    }

    // MARK: - Retrieval

    /// Retrieve relevant document context for a query. Returns nil if no chunks are relevant.
    func retrieveContext(for query: String, topK: Int = 3) async throws -> String? {
        let results = try await retrieveContextWithScores(for: query, topK: topK)
        let relevant = results.filter { $0.score >= Self.relevanceThreshold }
        guard !relevant.isEmpty else { return nil }
        return relevant.map(\.chunk.text).joined(separator: "\n---\n")
    }

    /// Retrieve chunks with their similarity scores.
    private func retrieveContextWithScores(for query: String, topK: Int = 3) async throws -> [(chunk: TextChunk, score: Float)] {
        // 1. Load embedding model and embed the query
        let queryEmbedding = try await embeddingService.embed(text: query)

        // 2. Unload embedding model to free RAM
        modelManager.unloadEmbedding()

        // 3. Search VectorStore with scores
        return vectorStore.searchWithScores(queryEmbedding: queryEmbedding, topK: topK)
    }

}
