import Accelerate

func normalized(_ vector: [Float]) -> [Float]? {
    let norm = sqrt(vDSP.sumOfSquares(vector))
    guard norm.isFinite, norm > 0 else { return nil }
    return vDSP.divide(vector, norm)
}

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    let denominator = sqrt(vDSP.sumOfSquares(a)) * sqrt(vDSP.sumOfSquares(b))
    guard denominator.isFinite, denominator > 0 else { return 0 }
    return vDSP.dot(a, b) / denominator
}

/// Only retain k entries. With the app's k=3 this avoids sorting the entire corpus.
func topK<S: Sequence>(_ scores: S, k: Int) -> [(index: Int, score: Float)]
where S.Element == (index: Int, score: Float) {
    guard k > 0 else { return [] }
    var best: [(index: Int, score: Float)] = []
    for result in scores where result.score.isFinite {
        let position = best.firstIndex { result.score > $0.score } ?? best.count
        if position < k {
            best.insert(result, at: position)
            if best.count > k { best.removeLast() }
        }
    }
    return best
}

func findTopK(query: [Float], candidates: [[Float]], k: Int) -> [(index: Int, score: Float)] {
    topK(candidates.enumerated().lazy.map {
        (index: $0.offset, score: cosineSimilarity(query, $0.element))
    }, k: k)
}
