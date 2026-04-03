import Testing
import Foundation
@testable import Hermit

struct VectorStoreTests {
    private func makeTempDirectory() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VectorStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func addChunksIncreasesCount() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }
        let store = VectorStore(storeDirectory: dir)

        let docId = UUID()
        let chunks = [
            TextChunk(documentId: docId, text: "Hello world", embedding: [1, 0, 0], chunkIndex: 0),
            TextChunk(documentId: docId, text: "Goodbye world", embedding: [0, 1, 0], chunkIndex: 1)
        ]
        store.addChunks(chunks, forDocument: docId)

        #expect(store.chunks.count == 2)
    }

    @Test func chunksForDocumentFiltersCorrectly() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }
        let store = VectorStore(storeDirectory: dir)

        let doc1 = UUID()
        let doc2 = UUID()
        store.addChunks([
            TextChunk(documentId: doc1, text: "Doc 1 chunk", embedding: [1, 0], chunkIndex: 0)
        ], forDocument: doc1)
        store.addChunks([
            TextChunk(documentId: doc2, text: "Doc 2 chunk", embedding: [0, 1], chunkIndex: 0)
        ], forDocument: doc2)

        let result = store.chunksForDocument(doc1)
        #expect(result.count == 1)
        #expect(result[0].text == "Doc 1 chunk")
    }

    @Test func deleteChunksRemovesCorrectDocument() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }
        let store = VectorStore(storeDirectory: dir)

        let doc1 = UUID()
        let doc2 = UUID()
        store.addChunks([
            TextChunk(documentId: doc1, text: "Keep this", embedding: [1, 0], chunkIndex: 0)
        ], forDocument: doc1)
        store.addChunks([
            TextChunk(documentId: doc2, text: "Delete this", embedding: [0, 1], chunkIndex: 0)
        ], forDocument: doc2)

        store.deleteChunks(forDocument: doc2)

        #expect(store.chunks.count == 1)
        #expect(store.chunks[0].text == "Keep this")
    }

    @Test func persistenceRoundTrip() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let docId = UUID()
        let chunks = [
            TextChunk(documentId: docId, text: "Persisted chunk", embedding: [0.5, 0.5, 0.5], chunkIndex: 0)
        ]

        // Write with one store instance
        let store1 = VectorStore(storeDirectory: dir)
        store1.addChunks(chunks, forDocument: docId)

        // Read with a new store instance
        let store2 = VectorStore(storeDirectory: dir)
        #expect(store2.chunks.count == 1)
        #expect(store2.chunks[0].text == "Persisted chunk")
        #expect(store2.chunks[0].embedding == [0.5, 0.5, 0.5])
    }

    @Test func searchReturnsCorrectTopK() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }
        let store = VectorStore(storeDirectory: dir)

        let docId = UUID()
        let chunks = [
            TextChunk(documentId: docId, text: "About cats", embedding: [1, 0, 0], chunkIndex: 0),
            TextChunk(documentId: docId, text: "About dogs", embedding: [0.9, 0.1, 0], chunkIndex: 1),
            TextChunk(documentId: docId, text: "About math", embedding: [0, 0, 1], chunkIndex: 2),
            TextChunk(documentId: docId, text: "About physics", embedding: [0, 0.1, 0.9], chunkIndex: 3),
        ]
        store.addChunks(chunks, forDocument: docId)

        // Query close to [1, 0, 0] should return "About cats" and "About dogs" as top 2
        let results = store.search(queryEmbedding: [1, 0, 0], topK: 2)
        #expect(results.count == 2)
        #expect(results[0].text == "About cats")
        #expect(results[1].text == "About dogs")
    }

    @Test func searchEmptyStoreReturnsEmpty() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }
        let store = VectorStore(storeDirectory: dir)

        let results = store.search(queryEmbedding: [1, 0, 0], topK: 3)
        #expect(results.isEmpty)
    }
}
