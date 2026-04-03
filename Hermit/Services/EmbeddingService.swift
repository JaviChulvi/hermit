import Foundation
import MLX
import MLXEmbedders

final class EmbeddingService: Sendable {
    private let modelManager: ModelManager

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Generate an embedding for a single text string.
    /// Returns a 384-dimension Float array (all-MiniLM-L6-v2 output size).
    func embed(text: String) async throws -> [Float] {
        let results = try await embedBatch(texts: [text])
        return results[0]
    }

    /// Generate embeddings for multiple text chunks with progress reporting.
    /// Calls `progress(completed, total)` after each chunk is embedded.
    /// Unloads the embedding model after the batch completes to free RAM.
    func embed(chunks: [String], progress: @Sendable @escaping (Int, Int) -> Void) async throws -> [[Float]] {
        let results = try await embedBatch(texts: chunks, progress: progress)
        await modelManager.unloadEmbedding()
        return results
    }

    // MARK: - Private

    /// Batch-embed texts using MLXEmbedders. Processes all texts in a single model session.
    private func embedBatch(
        texts: [String],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        try await modelManager.loadEmbeddingModel()

        guard let container = await modelManager.embeddingContainer else {
            throw EmbeddingServiceError.modelNotLoaded
        }

        var allEmbeddings: [[Float]] = []

        for (index, text) in texts.enumerated() {
            let embedding: [Float] = await container.perform { model, tokenizer, pooling in
                let encoded = tokenizer.encode(text: text, addSpecialTokens: true)
                let inputArray = MLXArray(encoded).expandedDimensions(axis: 0)
                let mask = MLXArray.ones(like: inputArray)
                let tokenTypes = MLXArray.zeros(like: inputArray)

                let modelOutput = model(
                    inputArray,
                    positionIds: nil,
                    tokenTypeIds: tokenTypes,
                    attentionMask: mask
                )

                let pooled = pooling(modelOutput, normalize: true, applyLayerNorm: true)
                pooled.eval()
                return pooled.squeezed().asArray(Float.self)
            }

            allEmbeddings.append(embedding)
            progress?(index + 1, texts.count)
        }

        return allEmbeddings
    }
}

enum EmbeddingServiceError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Embedding model is not loaded"
        }
    }
}
