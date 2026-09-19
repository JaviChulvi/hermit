import Foundation

@Observable
@MainActor
class DocumentViewModel {
    private(set) var documents: [Document] = []
    var isProcessing = false
    var processingStatus = ""
    var errorMessage: String?

    private let ragEngine: RAGEngine
    private let vectorStore: VectorStore
    private static var metadataURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("documents/metadata.json")
    }

    init(ragEngine: RAGEngine, vectorStore: VectorStore) {
        self.ragEngine = ragEngine
        self.vectorStore = vectorStore
    }

    func importDocument(url: URL) async {
        guard !isProcessing else { return }
        isProcessing = true
        errorMessage = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
            isProcessing = false
            processingStatus = ""
        }
        do {
            let document = try await ragEngine.ingestDocument(url: url) { [weak self] in
                self?.processingStatus = $0
            }
            let updated = documents + [document]
            do {
                try await Self.save(updated)
                documents = updated
            } catch {
                try await vectorStore.deleteChunks(forDocument: document.id)
                throw error
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteDocument(id: UUID) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await vectorStore.deleteChunks(forDocument: id)
            let updated = documents.filter { $0.id != id }
            try await Self.save(updated)
            documents = updated
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteAllDocuments() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await vectorStore.deleteAllChunks()
            try await Self.save([])
            documents = []
        } catch { errorMessage = error.localizedDescription }
    }

    func loadDocuments() async throws {
        let url = Self.metadataURL
        documents = try await Task.detached {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            return try JSONDecoder().decode([Document].self, from: Data(contentsOf: url))
        }.value
    }

    private static func save(_ documents: [Document]) async throws {
        let url = metadataURL
        try await Task.detached {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(documents).write(to: url, options: .atomic)
        }.value
    }
}
