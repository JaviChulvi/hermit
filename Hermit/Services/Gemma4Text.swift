//
//  Gemma4Text.swift
//  Hermit
//
//  Port of https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/models/gemma4_text.py
//  Registers "gemma4" / "gemma4_text" model types for mlx-swift-lm's LLMTypeRegistry.
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

// MARK: - Configuration

/// Rope parameters per attention type (full_attention / sliding_attention)
struct RopeAttentionParams: Codable {
    let ropeTheta: Float?
    let ropeType: String?
    let partialRotaryFactor: Float?

    enum CodingKeys: String, CodingKey {
        case ropeTheta = "rope_theta"
        case ropeType = "rope_type"
        case partialRotaryFactor = "partial_rotary_factor"
    }
}

public struct Gemma4TextConfiguration: Codable, Sendable {
    let modelType: String
    let hiddenSize: Int
    let numHiddenLayers: Int
    let intermediateSize: Int
    let numAttentionHeads: Int
    let headDim: Int
    let globalHeadDim: Int
    let rmsNormEps: Float
    let vocabSize: Int
    let vocabSizePerLayerInput: Int
    let numKeyValueHeads: Int
    let numKvSharedLayers: Int
    let hiddenSizePerLayerInput: Int
    let slidingWindow: Int
    let slidingWindowPattern: Int
    let maxPositionEmbeddings: Int
    let finalLogitSoftcapping: Float
    let useDoubleWideMlp: Bool
    let tieWordEmbeddings: Bool
    let layerTypes: [String]?

    // Extracted from rope_parameters
    let fullAttentionRopeTheta: Float
    let fullAttentionPartialRotaryFactor: Float
    let slidingAttentionRopeTheta: Float

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case intermediateSize = "intermediate_size"
        case numAttentionHeads = "num_attention_heads"
        case headDim = "head_dim"
        case globalHeadDim = "global_head_dim"
        case rmsNormEps = "rms_norm_eps"
        case vocabSize = "vocab_size"
        case vocabSizePerLayerInput = "vocab_size_per_layer_input"
        case numKeyValueHeads = "num_key_value_heads"
        case numKvSharedLayers = "num_kv_shared_layers"
        case hiddenSizePerLayerInput = "hidden_size_per_layer_input"
        case slidingWindow = "sliding_window"
        case slidingWindowPattern = "sliding_window_pattern"
        case maxPositionEmbeddings = "max_position_embeddings"
        case finalLogitSoftcapping = "final_logit_softcapping"
        case useDoubleWideMlp = "use_double_wide_mlp"
        case tieWordEmbeddings = "tie_word_embeddings"
        case layerTypes = "layer_types"
        case ropeParameters = "rope_parameters"
    }

    enum VLMCodingKeys: String, CodingKey {
        case textConfig = "text_config"
    }

    public init(from decoder: Decoder) throws {
        let nestedContainer = try decoder.container(keyedBy: VLMCodingKeys.self)
        let container =
            if nestedContainer.contains(.textConfig) {
                try nestedContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .textConfig)
            } else {
                try decoder.container(keyedBy: CodingKeys.self)
            }

        modelType = try container.decode(String.self, forKey: .modelType)
        hiddenSize = try container.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 1536
        numHiddenLayers = try container.decodeIfPresent(Int.self, forKey: .numHiddenLayers) ?? 35
        intermediateSize = try container.decodeIfPresent(Int.self, forKey: .intermediateSize) ?? 6144
        numAttentionHeads = try container.decodeIfPresent(Int.self, forKey: .numAttentionHeads) ?? 8
        headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) ?? 256
        globalHeadDim = try container.decodeIfPresent(Int.self, forKey: .globalHeadDim) ?? 512
        rmsNormEps = try container.decodeIfPresent(Float.self, forKey: .rmsNormEps) ?? 1e-6
        vocabSize = try container.decodeIfPresent(Int.self, forKey: .vocabSize) ?? 262144
        vocabSizePerLayerInput =
            try container.decodeIfPresent(Int.self, forKey: .vocabSizePerLayerInput) ?? 262144
        numKeyValueHeads = try container.decodeIfPresent(Int.self, forKey: .numKeyValueHeads) ?? 1
        numKvSharedLayers = try container.decodeIfPresent(Int.self, forKey: .numKvSharedLayers) ?? 20
        hiddenSizePerLayerInput =
            try container.decodeIfPresent(Int.self, forKey: .hiddenSizePerLayerInput) ?? 256
        slidingWindow = try container.decodeIfPresent(Int.self, forKey: .slidingWindow) ?? 512
        slidingWindowPattern =
            try container.decodeIfPresent(Int.self, forKey: .slidingWindowPattern) ?? 5
        maxPositionEmbeddings =
            try container.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings) ?? 131072
        finalLogitSoftcapping =
            try container.decodeIfPresent(Float.self, forKey: .finalLogitSoftcapping) ?? 30.0
        useDoubleWideMlp =
            try container.decodeIfPresent(Bool.self, forKey: .useDoubleWideMlp) ?? true
        tieWordEmbeddings =
            try container.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) ?? true
        layerTypes = try container.decodeIfPresent([String].self, forKey: .layerTypes)

        // Parse rope_parameters
        let ropeParams = try container.decodeIfPresent(
            [String: RopeAttentionParams].self, forKey: .ropeParameters)
        fullAttentionRopeTheta = ropeParams?["full_attention"]?.ropeTheta ?? 1_000_000.0
        fullAttentionPartialRotaryFactor =
            ropeParams?["full_attention"]?.partialRotaryFactor ?? 0.25
        slidingAttentionRopeTheta = ropeParams?["sliding_attention"]?.ropeTheta ?? 10_000.0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelType, forKey: .modelType)
        try container.encode(hiddenSize, forKey: .hiddenSize)
        try container.encode(numHiddenLayers, forKey: .numHiddenLayers)
        try container.encode(intermediateSize, forKey: .intermediateSize)
        try container.encode(numAttentionHeads, forKey: .numAttentionHeads)
        try container.encode(headDim, forKey: .headDim)
        try container.encode(globalHeadDim, forKey: .globalHeadDim)
        try container.encode(rmsNormEps, forKey: .rmsNormEps)
        try container.encode(vocabSize, forKey: .vocabSize)
        try container.encode(numKeyValueHeads, forKey: .numKeyValueHeads)
        try container.encode(numKvSharedLayers, forKey: .numKvSharedLayers)
    }

    /// Resolved layer types (generates default pattern if not specified in config)
    var resolvedLayerTypes: [String] {
        if let layerTypes { return layerTypes }
        let pattern =
            Array(repeating: "sliding_attention", count: slidingWindowPattern - 1)
            + ["full_attention"]
        return Array(
            (Array(repeating: pattern, count: (numHiddenLayers / pattern.count) + 1)
                .flatMap { $0 })
                .prefix(numHiddenLayers))
    }
}

// MARK: - Helper Modules

/// RMSNorm with direct weight (NOT `1 + weight` like Gemma 2/3).
/// Gemma 4 stores norm weights as the actual scale, not offset from 1.
class Gemma4RMSNorm: Module, UnaryLayer {
    let weight: MLXArray
    let eps: Float

    init(dimensions: Int, eps: Float = 1e-6) {
        self.weight = MLXArray.ones([dimensions])
        self.eps = eps
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.rmsNorm(x, weight: weight, eps: eps)
    }
}

/// RMSNorm without learnable scale (used for v_norm)
class RMSNormNoScale: Module {
    let eps: Float

    init(eps: Float = 1e-6) {
        self.eps = eps
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.rmsNorm(x, weight: MLXArray.mlxNone, eps: eps)
    }
}

/// Proportional RoPE: applies rotation only to a fraction of dimensions.
/// Port of PR #180's ProportionalRoPE — splits input, applies RoPE to
/// rotated portion only, then reassembles.
class ProportionalRoPE: Module, OffsetLayer {
    let dims: Int
    let traditional: Bool
    let rotatedDims: Int
    let _freqs: MLXArray?

    init(dims: Int, traditional: Bool = false, base: Float = 10_000,
         partialRotaryFactor: Float = 1.0, factor: Float = 1.0) {
        self.dims = dims
        self.traditional = traditional

        let ropeAngles = Int(partialRotaryFactor * Float(dims) / 2.0)
        self.rotatedDims = 2 * ropeAngles

        if rotatedDims > 0 {
            // Exponents divided by FULL dims (not rotated dims)
            let exponents = MLXArray(stride(from: 0, to: rotatedDims, by: 2))
                .asType(.float32) / Float(dims)
            self._freqs = factor * MLX.pow(base, exponents)
        } else {
            self._freqs = nil
        }

        super.init()
    }

    func callAsFunction(_ x: MLXArray, offset: Int = 0) -> MLXArray {
        guard rotatedDims > 0, let _freqs else { return x }

        let half = dims / 2
        let rotatedHalf = rotatedDims / 2

        // Split into left/right halves (non-traditional RoPE layout)
        let headParts = split(x, indices: [half], axis: -1)
        let left = headParts[0]
        let right = headParts[1]

        // Extract rotated portions from each half
        let leftParts = split(left, indices: [rotatedHalf], axis: -1)
        let rightParts = split(right, indices: [rotatedHalf], axis: -1)

        // Combine rotated portions, apply RoPE, split back
        var rotated = concatenated([leftParts[0], rightParts[0]], axis: -1)
        rotated = MLXFast.RoPE(
            rotated,
            dimensions: rotatedDims,
            traditional: traditional,
            base: nil,
            scale: 1.0,
            offset: offset,
            freqs: _freqs
        )
        let rotatedParts = split(rotated, indices: [rotatedHalf], axis: -1)

        // Reassemble: rotated portions + unrotated portions
        let newLeft = concatenated([rotatedParts[0], leftParts[1]], axis: -1)
        let newRight = concatenated([rotatedParts[1], rightParts[1]], axis: -1)
        return concatenated([newLeft, newRight], axis: -1)
    }
}

/// Linear layer with output scaling (used for per_layer_model_projection)
class ScaledLinear: Module {
    let weight: MLXArray
    let scalar: Float

    init(inFeatures: Int, outFeatures: Int, scalar: Float) {
        self.weight = MLXArray.zeros([outFeatures, inFeatures])
        self.scalar = scalar
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        return matmul(x, weight.T) * scalar
    }
}

// MARK: - Attention

class Gemma4Attention: Module {
    let layerIdx: Int
    let layerType: String
    let isSliding: Bool
    let headDim: Int
    let nHeads: Int
    let nKVHeads: Int
    let scale: Float
    let isKvSharedLayer: Bool

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear

    @ModuleInfo(key: "q_norm") var qNorm: Gemma4RMSNorm
    @ModuleInfo(key: "k_norm") var kNorm: Gemma4RMSNorm
    @ModuleInfo(key: "v_norm") var vNorm: RMSNormNoScale

    @ModuleInfo var rope: OffsetLayer

    init(_ config: Gemma4TextConfiguration, layerIdx: Int) {
        let layerTypes = config.resolvedLayerTypes
        self.layerIdx = layerIdx
        self.layerType = layerTypes[layerIdx]
        self.isSliding = layerType == "sliding_attention"

        // Full attention uses global_head_dim, sliding uses head_dim
        self.headDim = isSliding ? config.headDim : config.globalHeadDim

        let dim = config.hiddenSize
        self.nHeads = config.numAttentionHeads
        self.nKVHeads = config.numKeyValueHeads
        self.scale = 1.0

        self._qProj.wrappedValue = Linear(dim, nHeads * headDim, bias: false)
        self._kProj.wrappedValue = Linear(dim, nKVHeads * headDim, bias: false)
        self._vProj.wrappedValue = Linear(dim, nKVHeads * headDim, bias: false)
        self._oProj.wrappedValue = Linear(nHeads * headDim, dim, bias: false)

        self._qNorm.wrappedValue = Gemma4RMSNorm(dimensions: headDim, eps: config.rmsNormEps)
        self._kNorm.wrappedValue = Gemma4RMSNorm(dimensions: headDim, eps: config.rmsNormEps)
        self._vNorm.wrappedValue = RMSNormNoScale(eps: config.rmsNormEps)

        let firstKvSharedLayerIdx = config.numHiddenLayers - config.numKvSharedLayers
        self.isKvSharedLayer = layerIdx >= firstKvSharedLayerIdx

        // RoPE: ProportionalRoPE for full attention, standard RoPE for sliding
        if isSliding {
            self._rope.wrappedValue = RoPE(
                dimensions: config.headDim,
                traditional: false,
                base: config.slidingAttentionRopeTheta
            )
        } else {
            self._rope.wrappedValue = ProportionalRoPE(
                dims: config.globalHeadDim,
                traditional: false,
                base: config.fullAttentionRopeTheta,
                partialRotaryFactor: config.fullAttentionPartialRotaryFactor
            )
        }

        super.init()
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode? = nil,
        cache: KVCache? = nil
    ) -> MLXArray {
        let (B, L, _) = (x.dim(0), x.dim(1), x.dim(2))

        var queries = qProj(x)
        queries = queries.reshaped(B, L, -1, headDim)
        queries = qNorm(queries)

        let offset = cache?.offset ?? 0

        var keys: MLXArray
        var values: MLXArray

        if isKvSharedLayer, let cache {
            // Shared layer: read cached K/V from the source layer's cache
            let state = cache.state
            if state.count >= 2 {
                keys = state[0]
                values = state[1]
            } else {
                // Fallback: compute if cache is empty (shouldn't happen normally)
                keys = kProj(x).reshaped(B, L, -1, headDim)
                keys = kNorm(keys)
                keys = keys.transposed(0, 2, 1, 3)
                keys = rope(keys, offset: offset)

                values = vProj(x).reshaped(B, L, -1, headDim)
                values = vNorm(values)
                values = values.transposed(0, 2, 1, 3)

                (keys, values) = cache.update(keys: keys, values: values)
            }
        } else {
            // Source layer: compute K/V and update cache
            keys = kProj(x).reshaped(B, L, -1, headDim)
            keys = kNorm(keys)
            keys = keys.transposed(0, 2, 1, 3)
            keys = rope(keys, offset: offset)

            values = vProj(x).reshaped(B, L, -1, headDim)
            values = vNorm(values)
            values = values.transposed(0, 2, 1, 3)

            if let cache {
                (keys, values) = cache.update(keys: keys, values: values)
            }
        }

        queries = queries.transposed(0, 2, 1, 3)
        queries = rope(queries, offset: offset)

        // Adjust mask if needed (sliding window cache may change key length)
        var adjustedMask = mask
        if case .array(let maskArray) = mask {
            let keysSeqLen = keys.dim(2)
            if maskArray.shape.last! != keysSeqLen {
                adjustedMask = .array(maskArray[.ellipsis, (maskArray.shape.last! - keysSeqLen)...])
            }
        }

        let output = MLXFast.scaledDotProductAttention(
            queries: queries,
            keys: keys,
            values: values,
            scale: scale,
            mask: adjustedMask ?? .none
        )
        .transposed(0, 2, 1, 3)
        .reshaped(B, L, -1)

        return oProj(output)
    }
}

// MARK: - MLP

class Gemma4MLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear

    init(config: Gemma4TextConfiguration, layerIdx: Int) {
        let firstKvSharedLayerIdx = config.numHiddenLayers - config.numKvSharedLayers
        let isKvSharedLayer = layerIdx >= firstKvSharedLayerIdx && firstKvSharedLayerIdx > 0
        let useDoubleWide = config.useDoubleWideMlp && isKvSharedLayer
        let iSize = config.intermediateSize * (useDoubleWide ? 2 : 1)

        self._gateProj.wrappedValue = Linear(config.hiddenSize, iSize, bias: false)
        self._downProj.wrappedValue = Linear(iSize, config.hiddenSize, bias: false)
        self._upProj.wrappedValue = Linear(config.hiddenSize, iSize, bias: false)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        return downProj(geluApproximate(gateProj(x)) * upProj(x))
    }
}

// MARK: - Decoder Layer

class Gemma4DecoderLayer: Module {
    let layerType: String
    let hiddenSizePerLayerInput: Int

    @ModuleInfo(key: "self_attn") var selfAttn: Gemma4Attention
    @ModuleInfo var mlp: Gemma4MLP
    @ModuleInfo(key: "input_layernorm") var inputLayernorm: Gemma4RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayernorm: Gemma4RMSNorm
    @ModuleInfo(key: "pre_feedforward_layernorm") var preFeedforwardLayernorm: Gemma4RMSNorm
    @ModuleInfo(key: "post_feedforward_layernorm") var postFeedforwardLayernorm: Gemma4RMSNorm

    // Per-layer input gating
    @ModuleInfo(key: "per_layer_input_gate") var perLayerInputGate: Linear
    @ModuleInfo(key: "per_layer_projection") var perLayerProjection: Linear
    @ModuleInfo(key: "post_per_layer_input_norm") var postPerLayerInputNorm: Gemma4RMSNorm

    // Layer scalar
    @ModuleInfo(key: "layer_scalar") var layerScalar: MLXArray

    init(_ config: Gemma4TextConfiguration, layerIdx: Int) {
        let layerTypes = config.resolvedLayerTypes
        self.layerType = layerTypes[layerIdx]
        self.hiddenSizePerLayerInput = config.hiddenSizePerLayerInput

        self._selfAttn.wrappedValue = Gemma4Attention(config, layerIdx: layerIdx)
        self._mlp.wrappedValue = Gemma4MLP(config: config, layerIdx: layerIdx)

        self._inputLayernorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postAttentionLayernorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._preFeedforwardLayernorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postFeedforwardLayernorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)

        // Per-layer input gating
        self._perLayerInputGate.wrappedValue = Linear(
            config.hiddenSize, config.hiddenSizePerLayerInput, bias: false)
        self._perLayerProjection.wrappedValue = Linear(
            config.hiddenSizePerLayerInput, config.hiddenSize, bias: false)
        self._postPerLayerInputNorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)

        self._layerScalar.wrappedValue = MLXArray.ones([1])

        super.init()
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode? = nil,
        cache: KVCache? = nil,
        perLayerInput: MLXArray? = nil
    ) -> MLXArray {
        // Self-attention
        var residual = x
        var h = inputLayernorm(x)
        h = selfAttn(h, mask: mask, cache: cache)
        h = postAttentionLayernorm(h)
        h = residual + h

        // Feed-forward
        residual = h
        h = preFeedforwardLayernorm(h)
        h = mlp(h)
        h = postFeedforwardLayernorm(h)
        h = residual + h

        // Per-layer input gating
        if let perLayerInput {
            residual = h
            var gate = perLayerInputGate(h)
            gate = geluApproximate(gate)
            gate = gate * perLayerInput
            gate = perLayerProjection(gate)
            gate = postPerLayerInputNorm(gate)
            h = residual + gate
        }

        // Layer scalar
        h = h * layerScalar

        return h
    }
}

// MARK: - Inner Model

class Gemma4InnerModel: Module {
    let config: Gemma4TextConfiguration
    let layerTypes: [String]
    let firstKvSharedLayerIdx: Int
    let layerIdxToCacheIdx: [Int]
    let firstSlidingIdx: Int
    let firstFullIdx: Int

    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo var layers: [Gemma4DecoderLayer]
    @ModuleInfo var norm: Gemma4RMSNorm

    // Per-layer input embeddings
    @ModuleInfo(key: "embed_tokens_per_layer") var embedTokensPerLayer: Embedding
    @ModuleInfo(key: "per_layer_model_projection") var perLayerModelProjection: ScaledLinear
    @ModuleInfo(key: "per_layer_projection_norm") var perLayerProjectionNorm: Gemma4RMSNorm

    init(_ config: Gemma4TextConfiguration) {
        self.config = config
        self.layerTypes = config.resolvedLayerTypes
        self.firstKvSharedLayerIdx = config.numHiddenLayers - config.numKvSharedLayers

        // Build layer-to-cache index mapping (same as Gemma 3n)
        let concreteLayerTypes = Array(layerTypes[..<firstKvSharedLayerIdx])
        let sharedFullIdx = concreteLayerTypes.lastIndex(of: "full_attention") ?? 0
        let sharedSlidingIdx = concreteLayerTypes.lastIndex(of: "sliding_attention") ?? 0

        var mapping: [Int] = []
        for (i, lt) in layerTypes.enumerated() {
            if i < firstKvSharedLayerIdx {
                mapping.append(i)
            } else if lt == "full_attention" {
                mapping.append(sharedFullIdx)
            } else {
                mapping.append(sharedSlidingIdx)
            }
        }
        self.layerIdxToCacheIdx = mapping

        self.firstSlidingIdx = layerTypes.firstIndex(of: "sliding_attention") ?? 0
        self.firstFullIdx = layerTypes.firstIndex(of: "full_attention") ?? 0

        // Modules
        self._embedTokens.wrappedValue = Embedding(
            embeddingCount: config.vocabSize, dimensions: config.hiddenSize)

        self._layers.wrappedValue = (0..<config.numHiddenLayers).map {
            Gemma4DecoderLayer(config, layerIdx: $0)
        }

        self._norm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)

        // Per-layer input embeddings
        self._embedTokensPerLayer.wrappedValue = Embedding(
            embeddingCount: config.vocabSizePerLayerInput,
            dimensions: config.numHiddenLayers * config.hiddenSizePerLayerInput)

        self._perLayerModelProjection.wrappedValue = ScaledLinear(
            inFeatures: config.hiddenSize,
            outFeatures: config.numHiddenLayers * config.hiddenSizePerLayerInput,
            scalar: pow(Float(config.hiddenSize), -0.5))

        self._perLayerProjectionNorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSizePerLayerInput, eps: config.rmsNormEps)

        super.init()
    }

    func callAsFunction(
        _ inputs: MLXArray,
        cache: [KVCache?]? = nil,
        inputEmbedding: MLXArray? = nil,
        precomputedPerLayerInputs: MLXArray? = nil,
        maskOverride: MLXFast.ScaledDotProductAttentionMaskMode? = nil
    ) -> MLXArray {
        // Use precomputed embeddings (VLM path) or compute from token IDs
        var h: MLXArray
        if let inputEmbedding {
            h = inputEmbedding
        } else {
            h = embedTokens(inputs)
            let embedScale = sqrt(Float(config.hiddenSize))
            h = h * MLXArray(embedScale, dtype: h.dtype)
        }

        // Get per-layer inputs (use precomputed if provided by VLM)
        let perLayerInputs = precomputedPerLayerInputs ?? getPerLayerInputs(inputs)
        let projectedInputs = projectPerLayerInputs(h, perLayerInputs: perLayerInputs)
        // Pad cache to match layer count
        let maxCacheIdx = layerIdxToCacheIdx.max() ?? 0
        let requiredCacheSize = max(firstKvSharedLayerIdx, maxCacheIdx + 1)
        let cacheArray = cache ?? Array(repeating: nil as KVCache?, count: requiredCacheSize)

        // Create attention masks (use override for VLM prefill, or compute from cache)
        let fullMask: MLXFast.ScaledDotProductAttentionMaskMode
        let slidingWindowMask: MLXFast.ScaledDotProductAttentionMaskMode
        if let maskOverride {
            fullMask = maskOverride
            slidingWindowMask = maskOverride
        } else {
            fullMask = createAttentionMask(h: h, cache: cacheArray[firstFullIdx])
            slidingWindowMask = createAttentionMask(
                h: h, cache: cacheArray[firstSlidingIdx], windowSize: config.slidingWindow)
        }

        // Forward through layers
        for (i, layer) in layers.enumerated() {
            let isGlobal = layerTypes[i] == "full_attention"
            let mask = isGlobal ? fullMask : slidingWindowMask

            let cacheIdx = layerIdxToCacheIdx[i]
            let layerCache = cacheIdx < cacheArray.count ? cacheArray[cacheIdx] : nil

            // Extract per-layer input for this layer: [B, L, hiddenSizePerLayerInput]
            let perLayerInput = projectedInputs[0..., 0..., i, 0...]

            h = layer(h, mask: mask, cache: layerCache, perLayerInput: perLayerInput)
        }

        return norm(h)
    }

    func getPerLayerInputs(_ inputIds: MLXArray) -> MLXArray {
        var result = embedTokensPerLayer(inputIds)
        let perLayerScale = sqrt(Float(config.hiddenSizePerLayerInput))
        result = result * MLXArray(perLayerScale, dtype: result.dtype)
        // Reshape: [B, L, numHiddenLayers * hiddenSizePerLayerInput] -> [B, L, numHiddenLayers, hiddenSizePerLayerInput]
        let shape = Array(inputIds.shape) + [config.numHiddenLayers, config.hiddenSizePerLayerInput]
        result = result.reshaped(shape)
        return result
    }

    func projectPerLayerInputs(
        _ inputEmbeds: MLXArray, perLayerInputs: MLXArray
    ) -> MLXArray {
        var projection = perLayerModelProjection(inputEmbeds)
        // Reshape: [B, L, N*D] -> [B, L, N, D]
        let shape =
            Array(inputEmbeds.shape.dropLast())
            + [config.numHiddenLayers, config.hiddenSizePerLayerInput]
        projection = projection.reshaped(shape)
        projection = perLayerProjectionNorm(projection)

        // Combine: (projection + perLayerInputs) * (2^-0.5)
        let combined = projection + perLayerInputs
        let inputScale = pow(2.0, -0.5)
        return combined * MLXArray(inputScale, dtype: combined.dtype)
    }
}

// MARK: - Top-Level Model

public class Gemma4TextModel: Module, LanguageModel {

    @ModuleInfo var model: Gemma4InnerModel

    let config: Gemma4TextConfiguration
    var vocabularySize: Int { config.vocabSize }

    init(_ config: Gemma4TextConfiguration) {
        self.config = config
        self.model = Gemma4InnerModel(config)
        super.init()
    }

    public func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        let cacheArray: [KVCache?]? = cache?.map { $0 as KVCache? }
        var out = model(inputs, cache: cacheArray)

        // Tied word embeddings: use embed_tokens weight as lm_head
        out = model.embedTokens.asLinear(out)

        // Logit softcapping
        out = tanh(out / config.finalLogitSoftcapping) * config.finalLogitSoftcapping

        return out
    }

    /// Forward with precomputed embeddings and per-layer inputs (used by VLM).
    func forwardWithEmbeddings(
        embeddings: MLXArray,
        perLayerInputs: MLXArray?,
        cache: [KVCache]?
    ) -> MLXArray {
        let cacheArray: [KVCache?]? = cache?.map { $0 as KVCache? }
        // Pass dummy token IDs (not used when embedding + perLayerInputs are provided)
        let dummyTokens = MLXArray.zeros([embeddings.dim(0), embeddings.dim(1)], type: Int32.self)
        var out = model(
            dummyTokens, cache: cacheArray,
            inputEmbedding: embeddings,
            precomputedPerLayerInputs: perLayerInputs,
            maskOverride: .causal)

        out = model.embedTokens.asLinear(out)
        out = tanh(out / config.finalLogitSoftcapping) * config.finalLogitSoftcapping
        // Force-evaluate all cache contents so autoregressive steps
        // don't trigger deferred prefill ops that cause shape errors
        if let cache {
            eval(cache)
        }

        return out
    }


    public func newCache(parameters: GenerateParameters?) -> [KVCache] {
        let layerTypes = config.resolvedLayerTypes
        let firstKvShared = config.numHiddenLayers - config.numKvSharedLayers
        var caches: [KVCache] = []

        for i in 0..<firstKvShared {
            if layerTypes[i] == "full_attention" {
                let cache = KVCacheSimple()
                cache.step = 1024
                caches.append(cache)
            } else {
                caches.append(RotatingKVCache(maxSize: config.slidingWindow, keep: 0))
            }
        }

        return caches
    }

    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var processed = weights

        // VLM models converted using mlx_vlm will have weights under language_model key
        // Extract only the language_model subtree (drops audio_tower, vision_tower, etc.)
        let unflattened = ModuleParameters.unflattened(weights)
        if let lm = unflattened["language_model"] {
            processed = Dictionary(uniqueKeysWithValues: lm.flattened())
        }

        // Filter out rotary embedding keys and clipped linear metadata
        processed = processed.filter { key, _ in
            !key.contains("self_attn.rotary_emb")
                && !key.contains("input_max")
                && !key.contains("input_min")
                && !key.contains("output_max")
                && !key.contains("output_min")
        }

        // Tied word embeddings: drop lm_head weights, copy from embed_tokens if needed
        if config.tieWordEmbeddings {
            processed = processed.filter { key, _ in !key.hasPrefix("lm_head.") }
        }

        // Truncate vocab if needed
        let expectedVocab = config.vocabSize
        for key in ["model.embed_tokens.weight", "model.embed_tokens.scales",
                     "model.embed_tokens.biases",
                     "model.embed_tokens_per_layer.weight", "model.embed_tokens_per_layer.scales",
                     "model.embed_tokens_per_layer.biases"] {
            if let tensor = processed[key], tensor.dim(0) > expectedVocab {
                processed[key] = tensor[0..<expectedVocab]
            }
        }

        return processed
    }

    /// Prepare handles prompt processing
    public func prepare(
        _ input: LMInput, cache: [KVCache], windowSize: Int? = nil
    ) throws -> PrepareResult {
        let prefillStepSize = windowSize ?? 512
        var y = input.text

        while y.tokens.size > prefillStepSize {
            let chunk = y[.newAxis, ..<prefillStepSize]
            _ = self(chunk, cache: cache.isEmpty ? nil : cache, state: nil)
            eval(cache)
            y = y[prefillStepSize...]
        }

        return .tokens(y)
    }
}

// MARK: - Registration

/// Registers Gemma 4 model types with the LLM type registry.
/// Creates the VLM model (which wraps the text model + vision tower).
/// Must be called before attempting to load a Gemma 4 model.
func registerGemma4ModelType() async {
    let creator: @Sendable (Data) throws -> any LanguageModel = { data in
        let config = try JSONDecoder.json5().decode(Gemma4VLMConfiguration.self, from: data)
        return Gemma4VLMModel(config)
    }

    await LLMTypeRegistry.shared.registerModelType("gemma4", creator: creator)
    await LLMTypeRegistry.shared.registerModelType("gemma4_text", creator: creator)
}
