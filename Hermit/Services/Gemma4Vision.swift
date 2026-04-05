//
//  Gemma4Vision.swift
//  Hermit
//
//  Vision encoder for Gemma 4 VLM. Ported from mlx-swift-lm PR #180.
//  Processes images into a fixed-length sequence of vision tokens.
//

import Foundation
import MLX
import MLXLMCommon
import MLXNN

// MARK: - Configuration

public struct Gemma4VisionConfiguration: Codable, Sendable {
    let hiddenSize: Int
    let numHiddenLayers: Int
    let numAttentionHeads: Int
    let numKeyValueHeads: Int
    let headDim: Int
    let intermediateSize: Int
    let patchSize: Int
    let defaultOutputLength: Int
    let poolingKernelSize: Int
    let positionEmbeddingSize: Int
    let ropeTheta: Float
    let rmsNormEps: Float
    let useClippedLinears: Bool

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case headDim = "head_dim"
        case intermediateSize = "intermediate_size"
        case patchSize = "patch_size"
        case defaultOutputLength = "default_output_length"
        case poolingKernelSize = "pooling_kernel_size"
        case positionEmbeddingSize = "position_embedding_size"
        case ropeTheta = "rope_theta"
        case rmsNormEps = "rms_norm_eps"
        case useClippedLinears = "use_clipped_linears"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenSize = try container.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 768
        numHiddenLayers = try container.decodeIfPresent(Int.self, forKey: .numHiddenLayers) ?? 16
        numAttentionHeads = try container.decodeIfPresent(Int.self, forKey: .numAttentionHeads) ?? 12
        numKeyValueHeads = try container.decodeIfPresent(Int.self, forKey: .numKeyValueHeads) ?? 12
        headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) ?? 64
        intermediateSize = try container.decodeIfPresent(Int.self, forKey: .intermediateSize) ?? 3072
        patchSize = try container.decodeIfPresent(Int.self, forKey: .patchSize) ?? 16
        defaultOutputLength = try container.decodeIfPresent(
            Int.self, forKey: .defaultOutputLength) ?? 280
        poolingKernelSize = try container.decodeIfPresent(Int.self, forKey: .poolingKernelSize) ?? 3
        positionEmbeddingSize = try container.decodeIfPresent(
            Int.self, forKey: .positionEmbeddingSize) ?? 10240
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 100.0
        rmsNormEps = try container.decodeIfPresent(Float.self, forKey: .rmsNormEps) ?? 1e-6
        useClippedLinears = try container.decodeIfPresent(
            Bool.self, forKey: .useClippedLinears) ?? true
    }
}

// MARK: - Clippable Linear

/// Linear with optional input/output clipping for training stability.
/// Weights live under `.linear.weight` in the model checkpoint.
class Gemma4ClippableLinear: Module, UnaryLayer {
    @ModuleInfo(key: "linear") var linear: Linear
    // Clip params are loaded from weights but ignored at inference (perf)

    init(inFeatures: Int, outFeatures: Int, bias: Bool = false) {
        self._linear.wrappedValue = Linear(inFeatures, outFeatures, bias: bias)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        linear(x)
    }
}

// MARK: - Vision RMSNorm variants

/// RMSNorm with learnable scale (for q_norm, k_norm)
class Gemma4VisionRMSNorm: Module, UnaryLayer {
    let eps: Float
    @ModuleInfo var weight: MLXArray

    init(dimensions: Int, eps: Float = 1e-6) {
        self.eps = eps
        self._weight.wrappedValue = MLXArray.ones([dimensions])
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.rmsNorm(x, weight: weight, eps: eps)
    }
}

/// RMSNorm without learnable scale (for v_norm)
class Gemma4VisionRMSNormNoScale: Module, UnaryLayer {
    let eps: Float

    init(eps: Float = 1e-6) {
        self.eps = eps
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.rmsNorm(x, weight: MLXArray.mlxNone, eps: eps)
    }
}

// MARK: - Multi-Dimensional RoPE

/// Rotate-half helper for RoPE
private func gemma4RotateHalf(_ x: MLXArray) -> MLXArray {
    let half = x.dim(-1) / 2
    let x1 = x[.ellipsis, ..<half]
    let x2 = x[.ellipsis, half...]
    return concatenated([-x2, x1], axis: -1)
}

/// Apply Multi-Dimensional RoPE with 2D positions [x, y].
/// Splits head_dim into channels per dimension and applies RoPE separately.
private func gemma4ApplyMultiDimensionalRoPE(
    _ inputs: MLXArray, positions: MLXArray, baseFrequency: Float
) -> MLXArray {
    let headDim = inputs.shape[inputs.ndim - 1]
    let numDimensions = positions.shape[positions.ndim - 1]  // 2 for [x, y]
    let channelsPerDimension = 2 * (headDim / (2 * numDimensions))
    let halfPerDimension = channelsPerDimension / 2

    var parts: [MLXArray] = []
    for d in 0..<numDimensions {
        let start = d * channelsPerDimension
        let end = start + channelsPerDimension
        let part = inputs[.ellipsis, start..<end]

        let freqExponents =
            (2.0 / Float(channelsPerDimension)) * MLXArray(0..<halfPerDimension).asType(.float32)
        let timescale = MLX.pow(MLXArray(baseFrequency), freqExponents)
        let dimPositions = positions[.ellipsis, d..<(d + 1)].asType(.float32)
        let sinusoid = dimPositions / timescale

        var cosValue = cos(sinusoid)
        var sinValue = sin(sinusoid)
        cosValue = concatenated([cosValue, cosValue], axis: -1).asType(inputs.dtype)
        sinValue = concatenated([sinValue, sinValue], axis: -1).asType(inputs.dtype)
        cosValue = expandedDimensions(cosValue, axis: 2)
        sinValue = expandedDimensions(sinValue, axis: 2)

        parts.append(part * cosValue + gemma4RotateHalf(part) * sinValue)
    }

    return concatenated(parts, axis: -1)
}

// MARK: - Patch Embedder

/// Flattens image into patches and projects with learned linear + 2D position embeddings.
class Gemma4VisionPatchEmbedder: Module {
    @ModuleInfo(key: "input_proj") var inputProj: Linear
    @ModuleInfo(key: "position_embedding_table") var positionEmbeddingTable: MLXArray

    let patchSize: Int

    init(_ config: Gemma4VisionConfiguration) {
        self.patchSize = config.patchSize
        let patchDim = 3 * config.patchSize * config.patchSize  // 768 for patch_size=16

        self._inputProj.wrappedValue = Linear(patchDim, config.hiddenSize, bias: false)
        self._positionEmbeddingTable.wrappedValue = MLXArray.zeros(
            [2, config.positionEmbeddingSize, config.hiddenSize])

        super.init()
    }

    /// Patchify, project, and add 2D positional embeddings.
    /// - Parameters:
    ///   - pixelValues: [B, 3, H, W] in NCHW format, normalized to [0, 1]
    ///   - patchPositions: [B, numPatches, 2] with [x, y] coordinates
    /// - Returns: [B, numPatches, hiddenSize]
    func callAsFunction(_ pixelValues: MLXArray, patchPositions: MLXArray) -> MLXArray {
        let batch = pixelValues.dim(0)
        let height = pixelValues.dim(2)
        let width = pixelValues.dim(3)
        let patchesH = height / patchSize
        let patchesW = width / patchSize

        // Crop to exact patch grid (discard remainder pixels)
        let cropH = patchesH * patchSize
        let cropW = patchesW * patchSize
        let cropped = pixelValues[0..., 0..., ..<cropH, ..<cropW]

        // Patchify: [B, 3, cropH, cropW] → [B, patchesH, patchesW, patchSize, patchSize, 3]
        var patches = cropped.reshaped(
            batch, 3, patchesH, patchSize, patchesW, patchSize)
        patches = patches.transposed(0, 2, 4, 3, 5, 1)
        // Flatten patch pixels: [B, numPatches, patchSize*patchSize*3]
        patches = patches.reshaped(batch, patchesH * patchesW, -1)

        // Normalize to [-1, 1]
        patches = 2 * (patches - 0.5)

        // Linear projection
        var hiddenStates = inputProj(patches.asType(inputProj.weight.dtype))

        // Add factored 2D position embeddings
        let seqLen = hiddenStates.dim(1)
        let realPositions = patchPositions[0..., ..<seqLen, 0...]

        // X (horizontal) and Y (vertical) indices
        let xIndices = realPositions[0..., 0..., 0].flattened().asType(.int32)
        let yIndices = realPositions[0..., 0..., 1].flattened().asType(.int32)

        let xEmbeddings = take(positionEmbeddingTable[0], xIndices, axis: 0)
            .reshaped(batch, seqLen, -1)
        let yEmbeddings = take(positionEmbeddingTable[1], yIndices, axis: 0)
            .reshaped(batch, seqLen, -1)

        hiddenStates = hiddenStates + xEmbeddings + yEmbeddings

        return hiddenStates
    }
}

// MARK: - Vision Attention

class Gemma4VisionAttention: Module {
    let numHeads: Int
    let numKVHeads: Int
    let headDim: Int
    let ropeBaseFrequency: Float

    @ModuleInfo(key: "q_proj") var qProj: Gemma4ClippableLinear
    @ModuleInfo(key: "k_proj") var kProj: Gemma4ClippableLinear
    @ModuleInfo(key: "v_proj") var vProj: Gemma4ClippableLinear
    @ModuleInfo(key: "o_proj") var oProj: Gemma4ClippableLinear

    @ModuleInfo(key: "q_norm") var qNorm: Gemma4VisionRMSNorm
    @ModuleInfo(key: "k_norm") var kNorm: Gemma4VisionRMSNorm
    @ModuleInfo(key: "_v_norm") var vNorm: Gemma4VisionRMSNormNoScale

    init(_ config: Gemma4VisionConfiguration) {
        self.numHeads = config.numAttentionHeads
        self.numKVHeads = config.numKeyValueHeads
        self.headDim = config.headDim
        self.ropeBaseFrequency = config.ropeTheta

        let dim = config.hiddenSize
        self._qProj.wrappedValue = Gemma4ClippableLinear(inFeatures: dim, outFeatures: dim)
        self._kProj.wrappedValue = Gemma4ClippableLinear(inFeatures: dim, outFeatures: dim)
        self._vProj.wrappedValue = Gemma4ClippableLinear(inFeatures: dim, outFeatures: dim)
        self._oProj.wrappedValue = Gemma4ClippableLinear(inFeatures: dim, outFeatures: dim)

        self._qNorm.wrappedValue = Gemma4VisionRMSNorm(
            dimensions: config.headDim, eps: config.rmsNormEps)
        self._kNorm.wrappedValue = Gemma4VisionRMSNorm(
            dimensions: config.headDim, eps: config.rmsNormEps)
        self._vNorm.wrappedValue = Gemma4VisionRMSNormNoScale(eps: config.rmsNormEps)

        super.init()
    }

    func callAsFunction(
        _ x: MLXArray, positions: MLXArray, mask: MLXArray? = nil
    ) -> MLXArray {
        let (B, L, _) = (x.dim(0), x.dim(1), x.dim(2))

        var queries = qProj(x).reshaped(B, L, numHeads, headDim)
        var keys = kProj(x).reshaped(B, L, numKVHeads, headDim)
        var values = vProj(x).reshaped(B, L, numKVHeads, headDim)

        // Per-head normalization
        queries = qNorm(queries)
        keys = kNorm(keys)
        values = vNorm(values)

        // Multi-dimensional RoPE with 2D positions
        queries = gemma4ApplyMultiDimensionalRoPE(
            queries, positions: positions, baseFrequency: ropeBaseFrequency)
        keys = gemma4ApplyMultiDimensionalRoPE(
            keys, positions: positions, baseFrequency: ropeBaseFrequency)

        // Multi-head attention
        queries = queries.transposed(0, 2, 1, 3)
        keys = keys.transposed(0, 2, 1, 3)
        values = values.transposed(0, 2, 1, 3)

        let maskMode: MLXFast.ScaledDotProductAttentionMaskMode =
            if let mask { .array(mask) } else { .none }

        let output = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values,
            scale: 1.0, mask: maskMode
        )
        .transposed(0, 2, 1, 3)
        .reshaped(B, L, -1)

        return oProj(output)
    }
}

// MARK: - Vision MLP (SWIGLU gated)

class Gemma4VisionMLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Gemma4ClippableLinear
    @ModuleInfo(key: "up_proj") var upProj: Gemma4ClippableLinear
    @ModuleInfo(key: "down_proj") var downProj: Gemma4ClippableLinear

    init(_ config: Gemma4VisionConfiguration) {
        self._gateProj.wrappedValue = Gemma4ClippableLinear(
            inFeatures: config.hiddenSize, outFeatures: config.intermediateSize)
        self._upProj.wrappedValue = Gemma4ClippableLinear(
            inFeatures: config.hiddenSize, outFeatures: config.intermediateSize)
        self._downProj.wrappedValue = Gemma4ClippableLinear(
            inFeatures: config.intermediateSize, outFeatures: config.hiddenSize)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(geluApproximate(gateProj(x)) * upProj(x))
    }
}

// MARK: - Vision Transformer Block

class Gemma4VisionTransformerBlock: Module {
    @ModuleInfo(key: "self_attn") var selfAttn: Gemma4VisionAttention
    @ModuleInfo var mlp: Gemma4VisionMLP
    @ModuleInfo(key: "input_layernorm") var inputLayernorm: Gemma4RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayernorm: Gemma4RMSNorm
    @ModuleInfo(key: "pre_feedforward_layernorm") var preFeedforwardLayernorm: Gemma4RMSNorm
    @ModuleInfo(key: "post_feedforward_layernorm") var postFeedforwardLayernorm: Gemma4RMSNorm

    init(_ config: Gemma4VisionConfiguration) {
        self._selfAttn.wrappedValue = Gemma4VisionAttention(config)
        self._mlp.wrappedValue = Gemma4VisionMLP(config)
        self._inputLayernorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postAttentionLayernorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._preFeedforwardLayernorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postFeedforwardLayernorm.wrappedValue = Gemma4RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)
        super.init()
    }

    func callAsFunction(_ x: MLXArray, positions: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        var residual = x
        var h = inputLayernorm(x)
        h = selfAttn(h, positions: positions, mask: mask)
        h = postAttentionLayernorm(h)
        h = residual + h

        residual = h
        h = preFeedforwardLayernorm(h)
        h = mlp(h)
        h = postFeedforwardLayernorm(h)
        h = residual + h

        return h
    }
}

// MARK: - Vision Encoder

class Gemma4VisionEncoder: Module {
    @ModuleInfo var layers: [Gemma4VisionTransformerBlock]

    init(_ config: Gemma4VisionConfiguration) {
        self._layers.wrappedValue = (0..<config.numHiddenLayers).map { _ in
            Gemma4VisionTransformerBlock(config)
        }
        super.init()
    }

    func callAsFunction(_ x: MLXArray, positions: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        var h = x
        for layer in layers {
            h = layer(h, positions: positions, mask: mask)
        }
        return h
    }
}

// MARK: - Vision Pooler

/// Reduces variable-length patch sequences to a fixed output length
/// using spatial binning. No learnable parameters.
struct Gemma4VisionPooler {
    let defaultOutputLength: Int
    let poolingKernelSize: Int
    let rootHiddenSize: Float

    init(_ config: Gemma4VisionConfiguration) {
        self.defaultOutputLength = config.defaultOutputLength
        self.poolingKernelSize = config.poolingKernelSize
        self.rootHiddenSize = sqrt(Float(config.hiddenSize))
    }

    func callAsFunction(
        _ hiddenStates: MLXArray,
        patchPositions: MLXArray,
        validCount: Int,
        outputLength: Int? = nil
    ) -> MLXArray {
        let length = outputLength ?? defaultOutputLength
        let scale = MLXArray(rootHiddenSize, dtype: hiddenStates.dtype)

        if validCount <= length {
            return hiddenStates[0..., ..<validCount, 0...] * scale
        }

        let actualPositions = patchPositions[0, ..<validCount]
        let maxX = Int(actualPositions[0..., 0].max().item(Int32.self)) + 1

        let kernel = max(Int(sqrt(Double(validCount / max(length, 1)))), 1)
        let divisor = Float(max(kernel * kernel, 1))

        // Bin patches into kernel grid
        let kernelIndices = MLX.floor(actualPositions.asType(.float32) / Float(kernel))
            .asType(.int32)
        let gridW = max(maxX / max(kernel, 1), 1)
        let flatKernel = kernelIndices[0..., 0] + MLXArray(Int32(gridW)) * kernelIndices[0..., 1]

        // One-hot soft pooling
        let clamped = clip(flatKernel, min: 0, max: length - 1)
        // Manual one-hot: compare each index against all class indices
        let classIndices = MLXArray(0..<Int32(length)).asType(clamped.dtype)
        let expanded = expandedDimensions(clamped, axis: -1)  // [L, 1]
        let weights = MLX.equal(expanded, classIndices).asType(.float32) / divisor  // [L, length]

        // Pool: einsum "lL,bld->bLd"
        let validStates = hiddenStates[0..., ..<validCount, 0...]
        let output = einsum("lL,bld->bLd", weights, validStates).asType(hiddenStates.dtype)
        return output * scale
    }
}

// MARK: - Vision Model (full pipeline)

/// Full vision tower: patchify → positional encoding → pad → transformer → pool.
class Gemma4VisionModel: Module {
    @ModuleInfo(key: "patch_embedder") var patchEmbedder: Gemma4VisionPatchEmbedder
    @ModuleInfo var encoder: Gemma4VisionEncoder

    let config: Gemma4VisionConfiguration
    let pooler: Gemma4VisionPooler
    let maxPatches: Int

    init(_ config: Gemma4VisionConfiguration) {
        self.config = config
        self._patchEmbedder.wrappedValue = Gemma4VisionPatchEmbedder(config)
        self._encoder.wrappedValue = Gemma4VisionEncoder(config)
        self.pooler = Gemma4VisionPooler(config)
        self.maxPatches = config.defaultOutputLength * config.poolingKernelSize
            * config.poolingKernelSize
        super.init()
    }

    /// Compute patch positions for a given image size.
    /// Returns (positions: [B, maxPatches, 2], realCount: Int)
    private func computePatchPositions(batch: Int, height: Int, width: Int) -> (MLXArray, Int) {
        let patchesH = height / config.patchSize
        let patchesW = width / config.patchSize
        let realCount = patchesH * patchesW

        // Build [x, y] positions for real patches
        var positions = [[Int32]](repeating: [-1, -1], count: maxPatches)
        for row in 0..<patchesH {
            for col in 0..<patchesW {
                let idx = row * patchesW + col
                positions[idx] = [Int32(col), Int32(row)]  // [x, y]
            }
        }

        // Expand for batch
        let flat = positions.flatMap { $0 }
        var posArray = MLXArray(flat, [1, maxPatches, 2])
        if batch > 1 {
            posArray = repeated(posArray, count: batch, axis: 0)
        }

        return (posArray, realCount)
    }

    /// Process an image through the vision tower.
    /// - Parameter pixelValues: [B, 3, H, W] in NCHW format, values in [0, 1]
    /// - Returns: [B, outputLength, hiddenSize]
    func callAsFunction(_ pixelValues: MLXArray) -> MLXArray {
        let pixels =
            pixelValues.ndim == 3 ? expandedDimensions(pixelValues, axis: 0) : pixelValues

        let batch = pixels.dim(0)
        let height = pixels.dim(2)
        let width = pixels.dim(3)

        let (patchPositions, realCount) = computePatchPositions(
            batch: batch, height: height, width: width)

        // Embed patches with positional encoding (real patches only, no padding)
        let realPositions = patchPositions[0..., ..<realCount, 0...]
        var hiddenStates = patchEmbedder(pixels, patchPositions: realPositions)

        // Encoder processes only real patches — no padding, no attention mask.
        // This keeps memory manageable on mobile (900 patches vs 2520 padded).
        hiddenStates = encoder(hiddenStates, positions: realPositions, mask: nil)

        // Pool to fixed output length (280 tokens)
        hiddenStates = pooler(
            hiddenStates, patchPositions: patchPositions, validCount: realCount)

        return hiddenStates
    }
}
