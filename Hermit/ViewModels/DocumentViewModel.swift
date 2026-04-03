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
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = documents.appendingPathComponent("documents")
        return dir.appendingPathComponent("metadata.json")
    }

    init(ragEngine: RAGEngine, vectorStore: VectorStore) {
        self.ragEngine = ragEngine
        self.vectorStore = vectorStore
        loadDocuments()
    }

    // MARK: - Import

    func importDocument(url: URL) async {
        isProcessing = true
        processingStatus = "Starting..."
        errorMessage = nil

        // Start accessing the security-scoped resource
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let document = try await ragEngine.ingestDocument(url: url) { [weak self] status in
                self?.processingStatus = status
            }
            documents.append(document)
            saveDocuments()
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
        processingStatus = ""
    }

    // MARK: - Delete

    func deleteDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        vectorStore.deleteChunks(forDocument: id)
        saveDocuments()
    }

    func deleteAllDocuments() {
        documents.removeAll()
        vectorStore.deleteAllChunks()
        saveDocuments()
    }

    // MARK: - Persistence

    func loadDocuments() {
        let url = Self.metadataURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            documents = try JSONDecoder().decode([Document].self, from: data)
        } catch {
            documents = []
        }
    }

    private func saveDocuments() {
        let url = Self.metadataURL
        let dir = url.deletingLastPathComponent()

        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if let data = try? JSONEncoder().encode(documents) {
            try? data.write(to: url)
        }
    }
}
