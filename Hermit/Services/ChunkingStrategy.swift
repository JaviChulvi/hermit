import Foundation

struct ChunkingStrategy {

    /// Splits text into overlapping chunks of approximately `targetWords` words,
    /// adjusting boundaries to the nearest sentence end when possible.
    static func chunk(text: String, targetWords: Int = 300, overlapWords: Int = 50) -> [String] {
        let words = text.split(omittingEmptySubsequences: true) { $0.isWhitespace || $0.isNewline }
            .map(String.init)

        guard !words.isEmpty else { return [] }

        // If the text fits in a single chunk, return it as-is
        if words.count <= targetWords {
            return [words.joined(separator: " ")]
        }

        var chunks: [String] = []
        var start = 0

        while start < words.count {
            var end = min(start + targetWords, words.count)

            // Adjust end to the nearest sentence boundary
            if end < words.count {
                end = adjustToSentenceBoundary(words: words, roughEnd: end, targetWords: targetWords)
            }

            let chunkWords = Array(words[start..<end])
            let chunkText = chunkWords.joined(separator: " ")

            if !chunkText.isEmpty {
                chunks.append(chunkText)
            }

            // Advance start, applying overlap
            let advance = end - start - overlapWords
            if advance <= 0 {
                // Prevent infinite loop: always move forward by at least 1 word
                start = end
            } else {
                start += advance
            }
        }

        return chunks
    }

    // MARK: - Private

    /// Searches for the nearest sentence-ending punctuation (`.`, `!`, `?`) around
    /// `roughEnd`, within a 20% tolerance window. Returns the adjusted word index
    /// (exclusive end), or falls back to `roughEnd` if no boundary is found.
    private static func adjustToSentenceBoundary(words: [String], roughEnd: Int, targetWords: Int) -> Int {
        let tolerance = max(1, targetWords / 5) // 20% of target
        let searchStart = max(0, roughEnd - tolerance)
        let searchEnd = min(words.count, roughEnd + tolerance)

        // Look for the closest sentence boundary to roughEnd, preferring earlier ones
        var bestIndex = roughEnd
        var bestDistance = Int.max

        for i in searchStart..<searchEnd {
            let word = words[i]
            if wordEndsSentence(word) {
                let distance = abs(i + 1 - roughEnd)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = i + 1 // +1 because end index is exclusive
                }
            }
        }

        return bestIndex
    }

    /// Returns true if the word ends with sentence-terminating punctuation.
    private static func wordEndsSentence(_ word: String) -> Bool {
        guard let lastChar = word.last else { return false }
        return lastChar == "." || lastChar == "!" || lastChar == "?"
    }
}
