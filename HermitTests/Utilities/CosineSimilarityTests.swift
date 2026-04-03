import Foundation
import Testing
@testable import Hermit

@Suite("CosineSimilarity Tests")
struct CosineSimilarityTests {

    @Test("Identical vectors have similarity 1.0")
    func identicalVectors() {
        let v: [Float] = [1.0, 2.0, 3.0]
        let result = cosineSimilarity(v, v)
        #expect(abs(result - 1.0) < 1e-5)
    }

    @Test("Orthogonal vectors have similarity 0.0")
    func orthogonalVectors() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [0.0, 1.0, 0.0]
        let result = cosineSimilarity(a, b)
        #expect(abs(result) < 1e-5)
    }

    @Test("Opposite vectors have similarity -1.0")
    func oppositeVectors() {
        let a: [Float] = [1.0, 0.0]
        let b: [Float] = [-1.0, 0.0]
        let result = cosineSimilarity(a, b)
        #expect(abs(result - (-1.0)) < 1e-5)
    }

    @Test("Known vectors match pre-computed similarity")
    func knownVectors() {
        let a: [Float] = [1.0, 2.0, 3.0]
        let b: [Float] = [4.0, 5.0, 6.0]
        // dot = 32, normA = 14, normB = 77
        // expected = 32 / sqrt(14 * 77) = 32 / sqrt(1078) ≈ 0.97463
        let expected: Float = 32.0 / sqrt(14.0 * 77.0)
        let result = cosineSimilarity(a, b)
        #expect(abs(result - expected) < 1e-5)
    }

    @Test("Zero vector returns 0.0 without crashing")
    func zeroVector() {
        let zero: [Float] = [0.0, 0.0, 0.0]
        let other: [Float] = [1.0, 2.0, 3.0]
        #expect(cosineSimilarity(zero, other) == 0.0)
        #expect(cosineSimilarity(other, zero) == 0.0)
        #expect(cosineSimilarity(zero, zero) == 0.0)
    }

    @Test("findTopK returns top 2 of 5 candidates")
    func findTopKBasic() {
        let query: [Float] = [1.0, 0.0, 0.0]
        let candidates: [[Float]] = [
            [0.0, 1.0, 0.0],  // orthogonal → 0
            [1.0, 0.0, 0.0],  // identical → 1
            [0.5, 0.5, 0.0],  // partial → ~0.707
            [-1.0, 0.0, 0.0], // opposite → -1
            [0.9, 0.1, 0.0],  // close → ~0.994
        ]
        let results = findTopK(query: query, candidates: candidates, k: 2)
        #expect(results.count == 2)
        #expect(results[0].index == 1) // identical vector
        #expect(results[1].index == 4) // close vector
    }

    @Test("findTopK with k greater than candidates returns all")
    func findTopKExceedsCandidates() {
        let query: [Float] = [1.0, 0.0]
        let candidates: [[Float]] = [
            [1.0, 0.0],
            [0.0, 1.0],
        ]
        let results = findTopK(query: query, candidates: candidates, k: 10)
        #expect(results.count == 2)
    }
}
