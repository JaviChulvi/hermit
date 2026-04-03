import Testing
import Foundation
@testable import Hermit

@Suite("Data Model Tests")
struct DataModelTests {

    // MARK: - ChatMessage

    @Test("ChatMessage encodes and decodes correctly")
    func chatMessageRoundTrip() throws {
        let message = ChatMessage(role: .user, content: "Hello, world!", timestamp: Date(timeIntervalSince1970: 1_000_000))

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        #expect(decoded.id == message.id)
        #expect(decoded.role == message.role)
        #expect(decoded.content == message.content)
        #expect(decoded.timestamp == message.timestamp)
    }

    // MARK: - Document

    @Test("Document encodes and decodes correctly")
    func documentRoundTrip() throws {
        let doc = Document(
            name: "research",
            fileExtension: "pdf",
            dateAdded: Date(timeIntervalSince1970: 1_000_000),
            chunkCount: 12,
            isProcessed: true
        )

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(Document.self, from: data)

        #expect(decoded.id == doc.id)
        #expect(decoded.name == doc.name)
        #expect(decoded.fileExtension == doc.fileExtension)
        #expect(decoded.dateAdded == doc.dateAdded)
        #expect(decoded.chunkCount == doc.chunkCount)
        #expect(decoded.isProcessed == doc.isProcessed)
    }

    // MARK: - TextChunk

    @Test("TextChunk encodes and decodes with nil embedding")
    func textChunkNilEmbeddingRoundTrip() throws {
        let chunk = TextChunk(
            documentId: UUID(),
            text: "Some text content",
            embedding: nil,
            chunkIndex: 0
        )

        let data = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(TextChunk.self, from: data)

        #expect(decoded.id == chunk.id)
        #expect(decoded.documentId == chunk.documentId)
        #expect(decoded.text == chunk.text)
        #expect(decoded.embedding == nil)
        #expect(decoded.chunkIndex == chunk.chunkIndex)
    }

    @Test("TextChunk encodes and decodes with populated embedding")
    func textChunkWithEmbeddingRoundTrip() throws {
        let embedding: [Float] = [0.1, 0.2, 0.3, -0.5, 0.99]
        let chunk = TextChunk(
            documentId: UUID(),
            text: "Another chunk",
            embedding: embedding,
            chunkIndex: 3
        )

        let data = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(TextChunk.self, from: data)

        #expect(decoded.id == chunk.id)
        #expect(decoded.embedding == embedding)
        #expect(decoded.chunkIndex == chunk.chunkIndex)
    }

    // MARK: - ModelInfo

    @Test("ModelInfo static constants have correct HuggingFace IDs")
    func modelInfoConstants() {
        #expect(ModelInfo.embeddingModel.id == "mlx-community/all-MiniLM-L6-v2-bf16")
        #expect(ModelInfo.llmModel.id == "mlx-community/gemma-4-e2b-it-4bit")
        #expect(ModelInfo.embeddingModel.name == "MiniLM-L6-v2")
        #expect(ModelInfo.llmModel.name == "Gemma 4 E2B")
    }
}
