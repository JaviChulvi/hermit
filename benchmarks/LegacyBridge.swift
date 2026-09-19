import MLXLMCommon

// The old model predates the upstream prepare(state:) protocol. Forward to its
// original implementation unchanged; it has no cross-prefill state input.
extension Gemma4TextModel {
    public func prepare(_ input: LMInput, cache: [KVCache], state: LMOutput.State?, windowSize: Int?) throws -> PrepareResult {
        try prepare(input, cache: cache, windowSize: windowSize)
    }
}
extension Gemma4VLMModel {
    public func prepare(_ input: LMInput, cache: [KVCache], state: LMOutput.State?, windowSize: Int?) throws -> PrepareResult {
        try prepare(input, cache: cache, windowSize: windowSize)
    }
}
