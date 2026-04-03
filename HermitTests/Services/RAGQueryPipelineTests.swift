import Testing
import Foundation
@testable import Hermit

/// Unit tests for the RAG query pipeline: system prompt construction,
/// empty store handling, low-relevance detection, and context length limiting.
struct RAGQueryPipelineTests {

    // MARK: - Helpers

    private func makeChunksWithScores(_ items: [(text: String, score: Float)]) -> [(chunk: TextChunk, score: Float)] {
        let docId = UUID()
        return items.enumerated().map { index, item in
            let chunk = TextChunk(documentId: docId, text: item.text, embedding: [1, 0, 0], chunkIndex: index)
            return (chunk: chunk, score: item.score)
        }
    }

    // MARK: - System Prompt Structure

    @Test func systemPromptContainsInjectedChunkText() {
        let chunks = makeChunksWithScores([
            (text: "The capital of France is Paris.", score: 0.85),
            (text: "France has 67 million people.", score: 0.72),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "What is the capital of France?")

        #expect(prompt.contains("The capital of France is Paris."))
        #expect(prompt.contains("France has 67 million people."))
    }

    @Test func systemPromptHasContextSection() {
        let chunks = makeChunksWithScores([
            (text: "Some context text.", score: 0.5),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        #expect(prompt.contains("CONTEXT:"))
        #expect(prompt.contains("---"))
    }

    @Test func systemPromptHasRulesSection() {
        let chunks = makeChunksWithScores([
            (text: "Some context text.", score: 0.5),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        #expect(prompt.contains("RULES:"))
        #expect(prompt.contains("Answer ONLY with information from the context above."))
        #expect(prompt.contains("I don't find that information in the provided documents."))
        #expect(prompt.contains("Answer in the same language as the user."))
    }

    @Test func systemPromptSeparatesChunksWithDashes() {
        let chunks = makeChunksWithScores([
            (text: "Chunk one.", score: 0.9),
            (text: "Chunk two.", score: 0.8),
            (text: "Chunk three.", score: 0.7),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        // Chunks should be separated by "---" within the context
        #expect(prompt.contains("Chunk one.\n---\nChunk two."))
        #expect(prompt.contains("Chunk two.\n---\nChunk three."))
    }

    // MARK: - Low Relevance Warning

    @Test func lowRelevanceChunksAddWarning() {
        let chunks = makeChunksWithScores([
            (text: "Unrelated text.", score: 0.1),
            (text: "Also unrelated.", score: 0.05),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        #expect(prompt.contains("WARNING"))
        #expect(prompt.contains("may not be relevant"))
    }

    @Test func highRelevanceChunksHaveNoWarning() {
        let chunks = makeChunksWithScores([
            (text: "Relevant text.", score: 0.85),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        #expect(!prompt.contains("WARNING"))
    }

    @Test func mixedRelevanceNoWarningIfAnyAboveThreshold() {
        let chunks = makeChunksWithScores([
            (text: "Very relevant.", score: 0.9),
            (text: "Not relevant.", score: 0.1),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        // One chunk is above threshold, so no warning
        #expect(!prompt.contains("WARNING"))
    }

    // MARK: - Context Length Limiting

    @Test func veryLargeChunksAreTruncated() {
        // Create chunks that would far exceed the token budget
        let largeText = String(repeating: "word ", count: 5000) // ~25000 chars ≈ 6250 tokens
        let chunks = makeChunksWithScores([
            (text: largeText, score: 0.9),
            (text: "Second chunk that should not appear in full.", score: 0.8),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        // Prompt should be significantly smaller than the raw chunk text
        let estimatedTokens = RAGEngine.estimateTokenCount(prompt)
        #expect(estimatedTokens < RAGEngine.maxPromptTokens + 100) // allow small overhead from template
    }

    @Test func smallChunksAreNotTruncated() {
        let chunks = makeChunksWithScores([
            (text: "Short chunk one.", score: 0.9),
            (text: "Short chunk two.", score: 0.8),
            (text: "Short chunk three.", score: 0.7),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        // All chunks should appear in full
        #expect(prompt.contains("Short chunk one."))
        #expect(prompt.contains("Short chunk two."))
        #expect(prompt.contains("Short chunk three."))
    }

    @Test func contextLimitReducesChunkCount() {
        // Create 3 chunks where each is ~1500 tokens (6000 chars). Only 1-2 should fit.
        let mediumText1 = "First: " + String(repeating: "a ", count: 3000)
        let mediumText2 = "Second: " + String(repeating: "b ", count: 3000)
        let mediumText3 = "Third: " + String(repeating: "c ", count: 3000)

        let chunks = makeChunksWithScores([
            (text: mediumText1, score: 0.9),
            (text: mediumText2, score: 0.8),
            (text: mediumText3, score: 0.7),
        ])

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        // First chunk should always be present (at least partially)
        #expect(prompt.contains("First:"))
        // Third chunk should NOT appear in full given the budget
        #expect(!prompt.contains("Third: " + String(repeating: "c ", count: 3000)))
    }

    // MARK: - Token Estimation

    @Test func estimateTokenCountIsReasonable() {
        // "hello world" = 11 chars → ~3 tokens
        let count = RAGEngine.estimateTokenCount("hello world")
        #expect(count == 3)

        // Empty string → 0 tokens
        #expect(RAGEngine.estimateTokenCount("") == 0)

        // 400 chars → 100 tokens
        let text400 = String(repeating: "a", count: 400)
        #expect(RAGEngine.estimateTokenCount(text400) == 100)
    }

    // MARK: - Empty Chunks

    @Test func emptyChunksProducesMinimalPrompt() {
        let chunks: [(chunk: TextChunk, score: Float)] = []

        let prompt = RAGEngine.buildSystemPrompt(retrievedChunks: chunks, userQuery: "question")

        // Should still have the template structure
        #expect(prompt.contains("CONTEXT:"))
        #expect(prompt.contains("RULES:"))
    }
}
