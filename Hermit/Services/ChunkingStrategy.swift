import Foundation

struct ChunkingStrategy {
    /// Keep original words and punctuation while measuring with the model's tokenizer.
    /// `tokenCount` includes special tokens, so every emitted chunk fits the model.
    static func chunk(
        text: String, maxTokens: Int = 256, overlapTokens: Int = 32,
        tokenCount: (String) -> Int
    ) throws -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var chunks: [String] = []
        var start = 0
        while start < words.count {
            var low = start + 1
            var high = min(words.count, start + maxTokens)
            var end = start
            while low <= high {
                let middle = (low + high) / 2
                if tokenCount(words[start..<middle].joined(separator: " ")) <= maxTokens {
                    end = middle
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            guard end > start else { throw ChunkingError.wordExceedsLimit }
            chunks.append(words[start..<end].joined(separator: " "))
            if end == words.count { break }

            // Retain only a bounded suffix, and always advance at least one word.
            var next = end
            while next > start + 1,
                tokenCount(words[(next - 1)..<end].joined(separator: " ")) <= overlapTokens
            {
                next -= 1
            }
            start = next
        }
        return chunks
    }
}

enum ChunkingError: LocalizedError {
    case wordExceedsLimit
    var errorDescription: String? {
        "This document contains an unbroken passage longer than the embedding model's token limit. Add spaces or line breaks and import it again."
    }
}
