import Accelerate
import Foundation

@Observable
@MainActor
class VectorStore {
    private(set) var chunks: [TextChunk] = []
    private let storeDirectory: URL

    init(storeDirectory: URL? = nil) {
        if let storeDirectory {
            self.storeDirectory = storeDirectory
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.storeDirectory = documents.appendingPathComponent("vector_store")
        }
    }

    // MARK: - CRUD

    func addChunks(_ newChunks: [TextChunk], forDocument documentId: UUID) async throws {
        let prepared = Self.normalize(newChunks)
        let saved = chunksForDocument(documentId) + prepared
        let directory = storeDirectory
        try await Task.detached {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(saved)
            try data.write(to: directory.appendingPathComponent("\(documentId.uuidString).json"), options: .atomic)
        }.value
        chunks.append(contentsOf: prepared)
    }

    func chunksForDocument(_ documentId: UUID) -> [TextChunk] {
        chunks.filter { $0.documentId == documentId }
    }

    func deleteChunks(forDocument documentId: UUID) async throws {
        let fileURL = storeDirectory.appendingPathComponent("\(documentId.uuidString).json")
        try await Task.detached {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }.value
        chunks.removeAll { $0.documentId == documentId }
    }

    func deleteAllChunks() async throws {
        let directory = storeDirectory
        try await Task.detached {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }.value
        chunks.removeAll()
    }

    func storageSizeMB() async -> Int {
        let directory = storeDirectory
        return await Task.detached {
            guard let files = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var bytes = 0
            while let url = files.nextObject() as? URL {
                bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
            return bytes / (1024 * 1024)
        }.value
    }

    // MARK: - Search

    func search(queryEmbedding: [Float], topK: Int = 3) -> [TextChunk] {
        searchWithScores(queryEmbedding: queryEmbedding, topK: topK).map(\.chunk)
    }

    func searchWithScores(queryEmbedding: [Float], topK count: Int = 3) -> [(chunk: TextChunk, score: Float)] {
        guard let query = normalized(queryEmbedding) else { return [] }
        let scores = chunks.enumerated().lazy.compactMap { index, chunk -> (index: Int, score: Float)? in
            guard let embedding = chunk.embedding, embedding.count == query.count else { return nil }
            return (index, vDSP.dot(query, embedding))
        }
        return topK(scores, k: count).map { (chunks[$0.index], $0.score) }
    }

    // MARK: - Persistence

    func loadAll() async throws {
        let directory = storeDirectory
        chunks = try await Task.detached {
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            return try files.filter { $0.pathExtension == "json" }.flatMap {
                Self.normalize(try JSONDecoder().decode([TextChunk].self, from: Data(contentsOf: $0)))
            }
        }.value
    }

    private nonisolated static func normalize(_ chunks: [TextChunk]) -> [TextChunk] {
        chunks.map { chunk in
            var chunk = chunk
            chunk.embedding = chunk.embedding.flatMap(normalized)
            return chunk
        }
    }
}
