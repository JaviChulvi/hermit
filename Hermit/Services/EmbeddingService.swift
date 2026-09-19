import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon
import MLXLMTokenizers

/// Serialized tokenizer padding/truncation must not hide text from our token budget.
/// Keep the downloaded model untouched; the upstream loader reads a temporary copy.
struct EmbeddingTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let data = try Data(contentsOf: directory.appendingPathComponent("tokenizer.json"))
        guard var configuration = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        configuration.removeValue(forKey: "truncation")
        configuration.removeValue(forKey: "padding")
        try JSONSerialization.data(withJSONObject: configuration)
            .write(to: temporary.appendingPathComponent("tokenizer.json"))
        try FileManager.default.copyItem(
            at: directory.appendingPathComponent("tokenizer_config.json"),
            to: temporary.appendingPathComponent("tokenizer_config.json"))
        return try await TokenizersLoader().load(from: temporary)
    }
}

final class EmbeddingService: Sendable {
    private let modelManager: ModelManager
    // Keep the single-item baseline until the on-device batch comparison is recorded.
    let batchSize: Int

    init(modelManager: ModelManager, batchSize: Int = 1) {
        self.modelManager = modelManager
        self.batchSize = max(1, batchSize)
    }

    func embed(text: String) async throws -> [Float] {
        try await modelManager.withEmbeddingModel { container in
            try await container.perform { context in
                return try Self.embed([text], context: context)[0]
            }
        }
    }

    /// Chunk and embed in one model lifetime. The upstream container owns GPU isolation.
    func embedDocument(
        text: String, progress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> (texts: [String], embeddings: [[Float]]) {
        let batchSize = batchSize
        return try await modelManager.withEmbeddingModel { container in
            try await container.perform { context in
                let limit = min(256, context.model.maxPositionEmbeddings ?? 256)
                let chunks = try ChunkingStrategy.chunk(text: text, maxTokens: limit) {
                    context.tokenizer.encode(text: $0, addSpecialTokens: true).count
                }
                var embeddings: [[Float]] = []
                for start in stride(from: 0, to: chunks.count, by: batchSize) {
                    try Task.checkCancellation()
                    let end = min(start + batchSize, chunks.count)
                    embeddings += try Self.embed(Array(chunks[start..<end]), context: context)
                    progress(end, chunks.count)
                }
                return (chunks, embeddings)
            }
        }
    }

    func embed(chunks: [String], progress: @Sendable @escaping (Int, Int) -> Void) async throws -> [[Float]] {
        guard !chunks.isEmpty else { return [] }
        let batchSize = batchSize
        return try await modelManager.withEmbeddingModel { container in
            try await container.perform { context in
                var embeddings: [[Float]] = []
                for start in stride(from: 0, to: chunks.count, by: batchSize) {
                    try Task.checkCancellation()
                    let end = min(start + batchSize, chunks.count)
                    embeddings += try Self.embed(Array(chunks[start..<end]), context: context)
                    progress(end, chunks.count)
                }
                return embeddings
            }
        }
    }

    private static func embed(_ texts: [String], context: EmbedderModelContext) throws -> [[Float]] {
        let encoded = texts.map { context.tokenizer.encode(text: $0, addSpecialTokens: true) }
        let limit = min(256, context.model.maxPositionEmbeddings ?? 256)
        guard encoded.allSatisfy({ $0.count <= limit }) else { throw EmbeddingServiceError.queryTooLong }
        let width = encoded.map(\.count).max() ?? 0
        let tokens = MLXArray(encoded.flatMap { $0 + Array(repeating: 0, count: width - $0.count) })
            .reshaped(texts.count, width)
        let mask = MLXArray(encoded.flatMap {
            Array(repeating: Int32(1), count: $0.count) + Array(repeating: Int32(0), count: width - $0.count)
        }).reshaped(texts.count, width)
        let output = context.model(
            tokens, positionIds: nil, tokenTypeIds: MLXArray.zeros(like: tokens), attentionMask: mask)
        // The MLX checkpoint omits MiniLM's 1_Pooling/config.json. Its model card
        // specifies masked mean pooling and L2 normalization, without layer norm.
        let pooled = Pooling(strategy: .mean)(output, mask: mask, normalize: true)
        pooled.eval()
        return (0..<texts.count).map { pooled[$0].asArray(Float.self) }
    }
}

enum EmbeddingServiceError: LocalizedError {
    case queryTooLong
    var errorDescription: String? {
        "The document search text exceeds the embedding model's token limit. Please shorten your question."
    }
}
