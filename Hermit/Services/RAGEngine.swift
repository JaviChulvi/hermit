import Foundation
import os

private let logger = Logger(subsystem: "com.hermit.app", category: "RAGEngine")

@Observable
@MainActor
class RAGEngine {
    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore

    /// Whether documents have been imported and are available for RAG queries.
    var hasDocuments: Bool { !vectorStore.chunks.isEmpty }

    /// Minimum cosine similarity for a chunk to be considered relevant.
    static let relevanceThreshold: Float = 0.2

    init(embeddingService: EmbeddingService, vectorStore: VectorStore) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
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
            text = try await Task.detached { try DocumentProcessor.extractText(from: url) }.value
            logger.info("Text extracted: \(text.count) characters, \(text.split(separator: " ").count) words")
        } catch {
            logger.error("Text extraction failed: \(error.localizedDescription)")
            throw error
        }

        // Tokenize and embed while MiniLM is loaded once.
        progress("Chunking and embedding...")
        let (chunkStrings, embeddings) = try await embeddingService.embedDocument(text: text) { completed, total in
            Task { @MainActor in progress("Embedding chunk \(completed)/\(total)...") }
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
        try await vectorStore.addChunks(textChunks, forDocument: documentId)
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

        // 3. Search VectorStore with scores
        return vectorStore.searchWithScores(queryEmbedding: queryEmbedding, topK: topK)
    }

}
