import Foundation

@Observable
@MainActor
class RAGEngine {
    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore
    private let modelManager: ModelManager
    private let llmService: LLMService

    /// Minimum cosine similarity for a chunk to be considered relevant.
    static let relevanceThreshold: Float = 0.2

    /// Approximate max token budget for system prompt + user message.
    static let maxPromptTokens = 3000

    /// Rough estimate: 1 token ≈ 4 characters in English text.
    private static let charsPerToken = 4

    init(embeddingService: EmbeddingService, vectorStore: VectorStore, modelManager: ModelManager, llmService: LLMService) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.modelManager = modelManager
        self.llmService = llmService
    }

    // MARK: - Query Pipeline

    /// Full RAG query: embed query → retrieve context → build prompt → generate response.
    func query(prompt: String, onStatus: @escaping (String) -> Void) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    // 0. Check if any documents have been imported
                    if vectorStore.chunks.isEmpty {
                        continuation.yield("Please import a document first.")
                        continuation.finish()
                        return
                    }

                    // 1. Retrieve relevant context
                    onStatus("Searching documents...")
                    let retrievedWithScores = try await retrieveContextWithScores(for: prompt, topK: 3)

                    // 2. Build system prompt with context
                    let systemPrompt = RAGEngine.buildSystemPrompt(retrievedChunks: retrievedWithScores, userQuery: prompt)

                    // 3. Load LLM and generate
                    onStatus("Generating response...")
                    try await llmService.loadModel()
                    let stream = try await llmService.generate(systemPrompt: systemPrompt, userMessage: prompt)

                    // 4. Forward token stream
                    for try await token in stream {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Ingest Pipeline

    /// Full ingest pipeline: extract text → chunk → embed → store.
    /// Returns a `Document` with metadata about the ingested file.
    func ingestDocument(url: URL, progress: @MainActor @escaping (String) -> Void) async throws -> Document {
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        let documentId = UUID()

        // 1. Extract text
        progress("Extracting text...")
        let text = try DocumentProcessor.extractText(from: url)

        // 2. Chunk text
        progress("Splitting into chunks...")
        let chunkStrings = ChunkingStrategy.chunk(text: text)

        // 3. Generate embeddings
        progress("Generating embeddings...")
        let embeddings = try await embeddingService.embed(chunks: chunkStrings) { @Sendable completed, total in
            Task { @MainActor in
                progress("Embedding chunk \(completed)/\(total)...")
            }
        }

        // 4. Create TextChunk objects with embeddings
        let textChunks = chunkStrings.enumerated().map { index, text in
            TextChunk(
                documentId: documentId,
                text: text,
                embedding: embeddings[index],
                chunkIndex: index
            )
        }

        // 5. Save to VectorStore
        progress("Saving...")
        vectorStore.addChunks(textChunks, forDocument: documentId)

        // 6. Return Document metadata
        let document = Document(
            id: documentId,
            name: fileName,
            fileExtension: fileExtension,
            chunkCount: textChunks.count,
            isProcessed: true
        )

        return document
    }

    // MARK: - Retrieval

    /// Retrieve the most relevant chunks for a query string.
    func retrieveContext(for query: String, topK: Int = 3) async throws -> [TextChunk] {
        try await retrieveContextWithScores(for: query, topK: topK).map(\.chunk)
    }

    /// Retrieve chunks with their similarity scores.
    private func retrieveContextWithScores(for query: String, topK: Int = 3) async throws -> [(chunk: TextChunk, score: Float)] {
        // 1. Load embedding model and embed the query
        let queryEmbedding = try await embeddingService.embed(text: query)

        // 2. Unload embedding model to free RAM
        modelManager.unloadEmbedding()

        // 3. Search VectorStore with scores
        return vectorStore.searchWithScores(queryEmbedding: queryEmbedding, topK: topK)
    }

    // MARK: - Prompt Construction

    /// Build a system prompt with retrieved context injected.
    /// Trims chunks to stay within the token budget.
    static func buildSystemPrompt(retrievedChunks: [(chunk: TextChunk, score: Float)], userQuery: String) -> String {
        let lowRelevance = retrievedChunks.allSatisfy { $0.score < relevanceThreshold }

        // Estimate token budget for context: total budget minus template overhead and user query
        let templateOverhead = systemPromptTemplate(context: "", lowRelevance: false).count / charsPerToken
        let userQueryTokens = userQuery.count / charsPerToken
        let contextBudgetTokens = maxPromptTokens - templateOverhead - userQueryTokens
        let contextBudgetChars = contextBudgetTokens * charsPerToken

        // Build context string, trimming chunks if they exceed the budget
        var contextParts: [String] = []
        var usedChars = 0

        for result in retrievedChunks {
            let chunkText = result.chunk.text
            let separatorLen = contextParts.isEmpty ? 0 : 4 // "\n---\n"
            let needed = chunkText.count + separatorLen

            if usedChars + needed > contextBudgetChars {
                // Try to fit a truncated version of this chunk
                let remaining = contextBudgetChars - usedChars - separatorLen
                if remaining > 100 {
                    contextParts.append(String(chunkText.prefix(remaining)) + "...")
                }
                break
            }

            contextParts.append(chunkText)
            usedChars += needed
        }

        if contextParts.isEmpty, let first = retrievedChunks.first {
            // Always include at least a portion of the best chunk
            let maxChars = contextBudgetChars > 100 ? contextBudgetChars : 500
            contextParts.append(String(first.chunk.text.prefix(maxChars)))
        }

        let contextString = contextParts.joined(separator: "\n---\n")
        return systemPromptTemplate(context: contextString, lowRelevance: lowRelevance)
    }

    /// The system prompt template with context and rules.
    private static func systemPromptTemplate(context: String, lowRelevance: Bool) -> String {
        var prompt = """
        You are a helpful assistant that answers questions based EXCLUSIVELY on the provided context.
        Do not make up information.

        CONTEXT:
        ---
        \(context)
        ---

        RULES:
        - Answer ONLY with information from the context above.
        - If the answer is not in the context, say: "I don't find that information in the provided documents."
        - Quote the relevant part of the context when possible.
        - Answer in the same language as the user.
        """

        if lowRelevance {
            prompt += "\n- WARNING: The retrieved context may not be relevant to the user's question. If unsure, say so."
        }

        return prompt
    }

    /// Estimate the number of tokens in a string (rough: 1 token ≈ 4 chars).
    static func estimateTokenCount(_ text: String) -> Int {
        (text.count + charsPerToken - 1) / charsPerToken
    }
}
