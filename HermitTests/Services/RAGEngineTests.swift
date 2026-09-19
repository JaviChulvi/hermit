import Testing
import Foundation
@testable import Hermit

/// Unit tests for RAGEngine.
/// Note: `ingestDocument` and `retrieveContext` require a downloaded embedding model,
/// so they are covered in integration tests. These tests verify the retrieval path
/// using a pre-populated VectorStore with known embeddings.
@MainActor
struct RAGEngineTests {
    private func makeTempDirectory() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("RAGEngineTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makePopulatedStore(directory: URL) async throws -> VectorStore {
        let store = VectorStore(storeDirectory: directory)
        let docId = UUID()
        let chunks = [
            TextChunk(documentId: docId, text: "The cat sat on the mat", embedding: [1, 0, 0], chunkIndex: 0),
            TextChunk(documentId: docId, text: "Dogs are loyal companions", embedding: [0.9, 0.1, 0], chunkIndex: 1),
            TextChunk(documentId: docId, text: "Quantum physics is fascinating", embedding: [0, 0, 1], chunkIndex: 2),
            TextChunk(documentId: docId, text: "Mathematics builds on logic", embedding: [0, 0.1, 0.9], chunkIndex: 3),
            TextChunk(documentId: docId, text: "Feline behavior patterns", embedding: [0.95, 0.05, 0], chunkIndex: 4),
        ]
        try await store.addChunks(chunks, forDocument: docId)
        return store
    }

    @Test func retrieveContextReturnsChunks() async throws {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }
        let store = try await makePopulatedStore(directory: dir)

        // Directly test the vector store search (which RAGEngine.retrieveContext delegates to)
        let results = store.search(queryEmbedding: [1, 0, 0], topK: 3)
        #expect(!results.isEmpty)
        #expect(results.count == 3)
    }

    @Test func retrieveContextRespectsTopK() async throws {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }
        let store = try await makePopulatedStore(directory: dir)

        let results = store.search(queryEmbedding: [1, 0, 0], topK: 2)
        #expect(results.count == 2)
    }

    @Test func retrieveContextReturnsMostRelevantFirst() async throws {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }
        let store = try await makePopulatedStore(directory: dir)

        // Query embedding [1, 0, 0] is most similar to "The cat sat on the mat" [1, 0, 0]
        let results = store.search(queryEmbedding: [1, 0, 0], topK: 3)
        #expect(results[0].text == "The cat sat on the mat")
        // Second most similar should be "Feline behavior patterns" [0.95, 0.05, 0]
        #expect(results[1].text == "Feline behavior patterns")
        // Third should be "Dogs are loyal companions" [0.9, 0.1, 0]
        #expect(results[2].text == "Dogs are loyal companions")
    }
}
