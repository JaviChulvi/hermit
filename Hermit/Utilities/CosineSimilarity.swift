import Accelerate

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0.0 }

    let dot = vDSP.dot(a, b)
    let normA = vDSP.sumOfSquares(a)
    let normB = vDSP.sumOfSquares(b)

    let denominator = sqrt(normA) * sqrt(normB)
    guard denominator > 0 else { return 0.0 }

    return dot / denominator
}

func findTopK(query: [Float], candidates: [[Float]], k: Int) -> [(index: Int, score: Float)] {
    let scores = candidates.enumerated().map { (index, candidate) in
        (index: index, score: cosineSimilarity(query, candidate))
    }
    let sorted = scores.sorted { $0.score > $1.score }
    return Array(sorted.prefix(k))
}
