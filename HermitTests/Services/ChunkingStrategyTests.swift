import Testing
import Foundation
@testable import Hermit

struct ChunkingStrategyTests {
    @Test func tokenizerCountsCompleteUnpaddedInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let serialized = #"""
        {"version":"1.0",
         "truncation":{"direction":"Right","max_length":8,"strategy":"LongestFirst","stride":0},
         "padding":{"strategy":{"Fixed":8},"direction":"Right","pad_to_multiple_of":null,"pad_id":0,"pad_type_id":0,"pad_token":"[PAD]"},
         "added_tokens":[],"normalizer":null,"pre_tokenizer":{"type":"Whitespace"},
         "post_processor":{"type":"BertProcessing","sep":["[SEP]",3],"cls":["[CLS]",2]},
         "decoder":{"type":"WordPiece","prefix":"##","cleanup":true},
         "model":{"type":"WordPiece","unk_token":"[UNK]","continuing_subword_prefix":"##","max_input_chars_per_word":100,"vocab":{"[PAD]":0,"[UNK]":1,"[CLS]":2,"[SEP]":3,"hello":4}}}
        """#
        try Data(serialized.utf8).write(to: directory.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("tokenizer_config.json"))
        let tokenizer = try await EmbeddingTokenizerLoader().load(from: directory)
        let text = Array(repeating: "hello", count: 20).joined(separator: " ")
        #expect(tokenizer.encode(text: "hello", addSpecialTokens: true).count == 3)
        #expect(tokenizer.encode(text: text, addSpecialTokens: true).count == 22)
        let chunks = try ChunkingStrategy.chunk(text: text, maxTokens: 10, overlapTokens: 0) {
            tokenizer.encode(text: $0, addSpecialTokens: true).count
        }
        #expect(chunks.count == 3)
        #expect(chunks.joined(separator: " ") == text)
        #expect(try String(contentsOf: directory.appendingPathComponent("tokenizer.json"), encoding: .utf8) == serialized)
    }

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
