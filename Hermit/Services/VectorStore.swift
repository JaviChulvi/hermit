import Foundation

@Observable
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
        loadAll()
    }

    // MARK: - CRUD

    func addChunks(_ newChunks: [TextChunk], forDocument documentId: UUID) {
        chunks.append(contentsOf: newChunks)
        save(documentId: documentId)
    }

    func chunksForDocument(_ documentId: UUID) -> [TextChunk] {
        chunks.filter { $0.documentId == documentId }
    }

    func deleteChunks(forDocument documentId: UUID) {
        chunks.removeAll { $0.documentId == documentId }
        let fileURL = storeDirectory.appendingPathComponent("\(documentId.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    func allEmbeddings() -> [(index: Int, embedding: [Float])] {
        chunks.enumerated().compactMap { index, chunk in
            guard let embedding = chunk.embedding else { return nil }
            return (index: index, embedding: embedding)
        }
    }

    // MARK: - Search

    func search(queryEmbedding: [Float], topK: Int = 3) -> [TextChunk] {
        searchWithScores(queryEmbedding: queryEmbedding, topK: topK).map(\.chunk)
    }

    func searchWithScores(queryEmbedding: [Float], topK: Int = 3) -> [(chunk: TextChunk, score: Float)] {
        let indexed = allEmbeddings()
        guard !indexed.isEmpty else { return [] }

        let candidates = indexed.map { $0.embedding }
        let results = findTopK(query: queryEmbedding, candidates: candidates, k: topK)

        return results.map { result in
            let originalIndex = indexed[result.index].index
            return (chunk: chunks[originalIndex], score: result.score)
        }
    }

    // MARK: - Persistence

    private func save(documentId: UUID) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storeDirectory.path) {
            try? fm.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        }

        let documentChunks = chunksForDocument(documentId)
        let fileURL = storeDirectory.appendingPathComponent("\(documentId.uuidString).json")
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(documentChunks) {
            try? data.write(to: fileURL)
        }
    }

    func loadAll() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeDirectory.path),
              let files = try? fm.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
        else { return }

        let decoder = JSONDecoder()
        var loaded: [TextChunk] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let decoded = try? decoder.decode([TextChunk].self, from: data) {
                loaded.append(contentsOf: decoded)
            }
        }
        chunks = loaded
    }
}
