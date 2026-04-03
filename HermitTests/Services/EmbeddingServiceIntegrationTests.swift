import Testing
import Foundation
@testable import Hermit

/// Integration tests for EmbeddingService.
/// These tests require the embedding model (all-MiniLM-L6-v2) to be downloaded on disk.
/// They pass as no-ops when the model is not available.
@MainActor
struct EmbeddingServiceIntegrationTests {

    private func makeServiceIfModelAvailable() -> EmbeddingService? {
        let manager = ModelManager()
        guard manager.embeddingModelDownloaded else { return nil }
        return EmbeddingService(modelManager: manager)
    }

    @Test func embedSingleText_returns384Floats() async throws {
        guard let service = makeServiceIfModelAvailable() else { return }

        let embedding = try await service.embed(text: "Hello, world!")

        #expect(embedding.count == 384)
        #expect(embedding.allSatisfy { $0.isFinite })
    }

    @Test func embedSimilarSentences_highCosineSimilarity() async throws {
        guard let service = makeServiceIfModelAvailable() else { return }

        let embedding1 = try await service.embed(text: "The cat sat on the mat")
        let embedding2 = try await service.embed(text: "A cat was sitting on a mat")

        let similarity = cosineSimilarity(embedding1, embedding2)
        #expect(similarity > 0.7, "Similar sentences should have cosine similarity > 0.7, got \(similarity)")
    }

    @Test func embedUnrelatedSentences_lowCosineSimilarity() async throws {
        guard let service = makeServiceIfModelAvailable() else { return }

        let embedding1 = try await service.embed(text: "The weather is sunny today")
        let embedding2 = try await service.embed(text: "Quantum mechanics describes subatomic particles")

        let similarity = cosineSimilarity(embedding1, embedding2)
        #expect(similarity < 0.5, "Unrelated sentences should have cosine similarity < 0.5, got \(similarity)")
    }

    @Test func embedBatchChunks_returnsCorrectCount() async throws {
        guard let service = makeServiceIfModelAvailable() else { return }

        let chunks = [
            "First chunk of text about animals",
            "Second chunk of text about technology",
            "Third chunk of text about cooking"
        ]

        let progressUpdates = ProgressTracker()
        let embeddings = try await service.embed(chunks: chunks) { completed, total in
            progressUpdates.record(completed: completed, total: total)
        }

        #expect(embeddings.count == 3)
        for embedding in embeddings {
            #expect(embedding.count == 384)
        }

        let updates = progressUpdates.updates
        #expect(updates.count == 3)
        #expect(updates[0].completed == 1 && updates[0].total == 3)
        #expect(updates[1].completed == 2 && updates[1].total == 3)
        #expect(updates[2].completed == 3 && updates[2].total == 3)
    }
}

/// Thread-safe progress tracker for testing the progress callback.
private final class ProgressTracker: @unchecked Sendable {
    struct Update {
        let completed: Int
        let total: Int
    }

    private let lock = NSLock()
    private var _updates: [Update] = []

    var updates: [Update] {
        lock.lock()
        defer { lock.unlock() }
        return _updates
    }

    func record(completed: Int, total: Int) {
        lock.lock()
        defer { lock.unlock() }
        _updates.append(Update(completed: completed, total: total))
    }
}
