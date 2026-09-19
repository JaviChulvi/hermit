import Testing
@testable import Hermit

struct ChunkingStrategyTests {
    // Deliberately different from word count, including two special tokens.
    private func tokens(_ text: String) -> Int { text.split(separator: " ").count * 3 + 2 }

    @Test func emptyText() throws {
        #expect(try ChunkingStrategy.chunk(text: "", tokenCount: tokens).isEmpty)
    }

    @Test func budgetIncludesSpecialTokensAndRetainsEveryWord() throws {
        let words = (0..<100).map { "word\($0)" }
        let chunks = try ChunkingStrategy.chunk(
            text: words.joined(separator: " "), maxTokens: 20, overlapTokens: 0, tokenCount: tokens)
        #expect(chunks.allSatisfy { tokens($0) <= 20 })
        #expect(chunks.flatMap { $0.split(separator: " ").map(String.init) } == words)
    }

    @Test func overlapIsBoundedAndLastChunkIsNotDuplicated() throws {
        let chunks = try ChunkingStrategy.chunk(
            text: "one two three four five six seven eight nine ten", maxTokens: 20,
            overlapTokens: 8, tokenCount: tokens)
        #expect(chunks == ["one two three four five six", "five six seven eight nine ten"])
    }

    @Test func excessiveOverlapStillMakesProgress() throws {
        let chunks = try ChunkingStrategy.chunk(
            text: "uno dos tres cuatro", maxTokens: 8, overlapTokens: 100, tokenCount: tokens)
        #expect(chunks == ["uno dos", "dos tres", "tres cuatro"])
    }

    @Test func impossibleWordDoesNotSilentlyTruncate() {
        #expect(throws: ChunkingError.self) {
            try ChunkingStrategy.chunk(text: "unbroken", maxTokens: 3, tokenCount: tokens)
        }
    }
}
