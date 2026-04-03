import Foundation

struct TextChunk: Identifiable, Codable, Sendable {
    let id: UUID
    let documentId: UUID
    let text: String
    var embedding: [Float]?
    let chunkIndex: Int

    init(
        id: UUID = UUID(),
        documentId: UUID,
        text: String,
        embedding: [Float]? = nil,
        chunkIndex: Int
    ) {
        self.id = id
        self.documentId = documentId
        self.text = text
        self.embedding = embedding
        self.chunkIndex = chunkIndex
    }
}
