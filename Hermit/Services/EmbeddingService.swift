import Foundation
import Metal
import MLX
import MLXEmbedders
import os

private let logger = Logger(subsystem: "com.hermit.app", category: "EmbeddingService")

final class EmbeddingService: Sendable {
    private let modelManager: ModelManager

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Generate an embedding for a single text string.
    /// Returns a 384-dimension Float array (all-MiniLM-L6-v2 output size).
    func embed(text: String) async throws -> [Float] {
        logger.info("embed(text:) — \(text.prefix(80))...")
        let results = try await embedBatch(texts: [text])
        logger.info("embed(text:) — got embedding of dimension \(results[0].count)")
        return results[0]
    }

    /// Generate embeddings for multiple text chunks with progress reporting.
    /// Calls `progress(completed, total)` after each chunk is embedded.
    /// Unloads the embedding model after the batch completes to free RAM.
    func embed(chunks: [String], progress: @Sendable @escaping (Int, Int) -> Void) async throws -> [[Float]] {
        logger.info("embed(chunks:) — \(chunks.count) chunks to embed")
        let results = try await embedBatch(texts: chunks, progress: progress)
        logger.info("embed(chunks:) — all embeddings generated, unloading model")
        await modelManager.unloadEmbedding()
        return results
    }

    // MARK: - Private

    /// Batch-embed texts using MLXEmbedders. Processes all texts in a single model session.
    private func embedBatch(
        texts: [String],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            logger.warning("embedBatch called with empty texts array")
            return []
        }

        logger.info("embedBatch — requesting model load...")
        try await modelManager.loadEmbeddingModel()

        guard let container = await modelManager.embeddingContainer else {
            logger.error("embedBatch — model container is nil after load!")
            throw EmbeddingServiceError.modelNotLoaded
        }

        logger.info("embedBatch — model container ready, starting inference for \(texts.count) texts")
        var allEmbeddings: [[Float]] = []

        for (index, text) in texts.enumerated() {
            let tokenCount = text.split(separator: " ").count
            logger.debug("Embedding chunk \(index + 1)/\(texts.count) — \(tokenCount) words, \(text.count) chars")

            do {
                let embedding: [Float] = try await container.perform { model, tokenizer, pooling in
                    let encoded = tokenizer.encode(text: text, addSpecialTokens: true)
                    logger.debug("Tokenized to \(encoded.count) tokens")

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

                    let result = pooled.squeezed().asArray(Float.self)
                    logger.debug("Embedding result dimension: \(result.count)")
                    return result
                }

                allEmbeddings.append(embedding)
                progress?(index + 1, texts.count)
                logger.info("Chunk \(index + 1)/\(texts.count) embedded OK (\(embedding.count) dims)")
            } catch {
                logger.error("Failed to embed chunk \(index + 1): \(error.localizedDescription)")
                logger.error("Error type: \(type(of: error))")
                logger.error("Full error: \(String(describing: error))")
                throw error
            }
        }

        if MTLCreateSystemDefaultDevice() != nil {
            let memSnapshot = Memory.snapshot()
            logger.info("embedBatch complete — MLX active: \(memSnapshot.activeMemory / 1024 / 1024) MB, cache: \(memSnapshot.cacheMemory / 1024 / 1024) MB")
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
