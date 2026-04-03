import Testing
import Foundation
@testable import Hermit

struct ChunkingStrategyTests {

    @Test func emptyStringReturnsEmptyArray() {
        let chunks = ChunkingStrategy.chunk(text: "")
        #expect(chunks.isEmpty)
    }

    @Test func shortTextReturnsSingleChunk() {
        let words = (1...100).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = ChunkingStrategy.chunk(text: text, targetWords: 300, overlapWords: 50)

        #expect(chunks.count == 1)
        #expect(chunks[0] == text)
    }

    @Test func exactTargetWordsReturnsSingleChunk() {
        let words = (1...300).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = ChunkingStrategy.chunk(text: text, targetWords: 300, overlapWords: 50)

        #expect(chunks.count == 1)
    }

    @Test func sixHundredWordsNoOverlapReturnsTwoChunks() {
        let words = (1...600).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = ChunkingStrategy.chunk(text: text, targetWords: 300, overlapWords: 0)

        #expect(chunks.count == 2)

        // Each chunk should be approximately 300 words
        for chunk in chunks {
            let count = chunk.split(separator: " ").count
            #expect(count >= 250 && count <= 350)
        }
    }

    @Test func sixHundredWordsWithOverlapHasOverlap() {
        let words = (1...600).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = ChunkingStrategy.chunk(text: text, targetWords: 300, overlapWords: 50)

        #expect(chunks.count >= 2)

        // Verify overlap: last words of chunk 0 should appear at start of chunk 1
        let chunk0Words = chunks[0].split(separator: " ")
        let chunk1Words = chunks[1].split(separator: " ")
        let lastWordsOfChunk0 = chunk0Words.suffix(50)
        let firstWordsOfChunk1 = chunk1Words.prefix(50)

        #expect(Array(lastWordsOfChunk0) == Array(firstWordsOfChunk1))
    }

    @Test func veryLongTextReturnsCorrectNumberOfChunks() {
        let words = (1...2000).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = ChunkingStrategy.chunk(text: text, targetWords: 300, overlapWords: 50)

        // 2000 words / (300 - 50) = 8 chunks, so expect at least 7
        #expect(chunks.count >= 7)

        // Every chunk should have content
        for chunk in chunks {
            #expect(!chunk.isEmpty)
        }
    }

    @Test func chunkSizesAreWithinReasonableRange() {
        let words = (1...2000).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = ChunkingStrategy.chunk(text: text, targetWords: 300, overlapWords: 50)

        // All chunks except possibly the last should be within 250-350 words
        for (i, chunk) in chunks.enumerated() {
            let count = chunk.split(separator: " ").count
            if i < chunks.count - 1 {
                #expect(count >= 250 && count <= 350, "Chunk \(i) has \(count) words, expected 250-350")
            } else {
                // Last chunk can be smaller
                #expect(count > 0, "Last chunk should not be empty")
            }
        }
    }

    @Test func sentenceBoundaryAdjustment() {
        // Build text where a sentence ends near the target boundary
        var words: [String] = []
        for i in 1...295 {
            words.append("word\(i)")
        }
        words.append("end.")  // Word 296 ends a sentence
        for i in 297...600 {
            words.append("word\(i)")
        }
        let text = words.joined(separator: " ")

        let chunks = ChunkingStrategy.chunk(text: text, targetWords: 300, overlapWords: 50)

        // First chunk should end at the sentence boundary (word 296 = "end.")
        #expect(chunks[0].hasSuffix("end."))
    }
}
