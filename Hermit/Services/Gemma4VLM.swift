//
//  Gemma4VLM.swift
//  Hermit
//
//  Top-level Gemma 4 Vision-Language Model (VLM) that wraps the text decoder
//  (Gemma4TextModel) and the vision encoder (Gemma4VisionModel).
//  Also includes the image-aware UserInputProcessor and MessageGenerator.
//

import CoreImage
import CoreGraphics
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

// MARK: - VLM Configuration

struct Gemma4VLMConfiguration: Codable, Sendable {
    let textConfig: Gemma4TextConfiguration
    let visionConfig: Gemma4VisionConfiguration
    let modelType: String
    let imageTokenId: Int
    let boiTokenId: Int
    let eoiTokenId: Int
    let visionSoftTokensPerImage: Int

    enum CodingKeys: String, CodingKey {
        case textConfig = "text_config"
        case visionConfig = "vision_config"
        case modelType = "model_type"
        case imageTokenId = "image_token_id"
        case boiTokenId = "boi_token_id"
        case eoiTokenId = "eoi_token_id"
        case visionSoftTokensPerImage = "vision_soft_tokens_per_image"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textConfig = try container.decode(Gemma4TextConfiguration.self, forKey: .textConfig)
        visionConfig = try container.decode(Gemma4VisionConfiguration.self, forKey: .visionConfig)
        modelType = try container.decode(String.self, forKey: .modelType)
        imageTokenId = try container.decodeIfPresent(Int.self, forKey: .imageTokenId) ?? 258880
        boiTokenId = try container.decodeIfPresent(Int.self, forKey: .boiTokenId) ?? 255999
        eoiTokenId = try container.decodeIfPresent(Int.self, forKey: .eoiTokenId) ?? 258882
        visionSoftTokensPerImage = try container.decodeIfPresent(
            Int.self, forKey: .visionSoftTokensPerImage) ?? 280
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelType, forKey: .modelType)
        try container.encode(imageTokenId, forKey: .imageTokenId)
        try container.encode(boiTokenId, forKey: .boiTokenId)
        try container.encode(eoiTokenId, forKey: .eoiTokenId)
    }
}

// MARK: - Embed Vision (projection layer)

/// Projects vision features (768-dim) into text embedding space (1536-dim)
/// with post-projection RMSNorm (no learnable scale).
class EmbedVision: Module {
    @ModuleInfo(key: "embedding_projection") var embeddingProjection: Linear
    @ModuleInfo(key: "embedding_post_projection_norm") var postNorm: Gemma4VisionRMSNormNoScale

    init(visionHiddenSize: Int, textHiddenSize: Int, eps: Float = 1e-6) {
        self._embeddingProjection.wrappedValue = Linear(
            visionHiddenSize, textHiddenSize, bias: false)
        self._postNorm.wrappedValue = Gemma4VisionRMSNormNoScale(eps: eps)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        postNorm(embeddingProjection(x))
    }
}

// MARK: - VLM Model

public class Gemma4VLMModel: Module, LanguageModel {
    @ModuleInfo(key: "vision_tower") var visionTower: Gemma4VisionModel
    @ModuleInfo(key: "language_model") var languageModel: Gemma4TextModel
    @ModuleInfo(key: "embed_vision") var embedVision: EmbedVision

    let config: Gemma4VLMConfiguration

    public var vocabularySize: Int { config.textConfig.vocabSize }

    init(_ config: Gemma4VLMConfiguration) {
        self.config = config
        self._visionTower.wrappedValue = Gemma4VisionModel(config.visionConfig)
        self._languageModel.wrappedValue = Gemma4TextModel(config.textConfig)
        self._embedVision.wrappedValue = EmbedVision(
            visionHiddenSize: config.visionConfig.hiddenSize,
            textHiddenSize: config.textConfig.hiddenSize
        )
        super.init()
    }

    // MARK: - LanguageModel conformance

    public func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        languageModel(inputs, cache: cache)
    }

    public func newCache(parameters: GenerateParameters?) -> [KVCache] {
        languageModel.newCache(parameters: parameters)
    }

    public func prepare(
        _ input: LMInput, cache: [KVCache], windowSize: Int? = nil
    ) throws -> PrepareResult {
        guard let imagePixels = input.image?.pixels else {
            // Text-only: delegate to language model
            return try languageModel.prepare(input, cache: cache, windowSize: windowSize)
        }

        // Ensure tokens have batch dimension [1, seqLen] for model operations
        let tokens =
            input.text.tokens.ndim == 1
            ? input.text.tokens.expandedDimensions(axis: 0) : input.text.tokens

        // 1. Get text embeddings and scale
        var inputEmbeds = languageModel.model.embedTokens(tokens)
        inputEmbeds =
            (inputEmbeds
                * MLXArray(
                    pow(Float(config.textConfig.hiddenSize), 0.5), dtype: .float32))
            .asType(inputEmbeds.dtype)
        eval(inputEmbeds)

        // 2. Compute per-layer inputs — zero out image tokens so they don't
        //    go through the per-layer embedding table
        var perLayerInputs: MLXArray? = nil
        if config.textConfig.hiddenSizePerLayerInput > 0 {
            let imageMask2 = tokens .== MLXArray(Int32(config.imageTokenId))
            let textMask = logicalNot(imageMask2)
            let perLayerTokens = MLX.where(textMask, tokens, MLXArray.zeros(like: tokens))
            perLayerInputs = languageModel.model.getPerLayerInputs(perLayerTokens)
            eval(perLayerInputs!)
        }

        // 3. Run vision tower → [B, 280, visionHidden]
        var imageFeatures = visionTower(imagePixels)
        eval(imageFeatures)

        // 4. Project to text embedding space + post-norm
        imageFeatures = embedVision(imageFeatures)
        eval(imageFeatures)
        imageFeatures = imageFeatures.asType(inputEmbeds.dtype)

        // 5. Replace image token positions with vision features (masked scatter)
        let imageMask = tokens .== MLXArray(Int32(config.imageTokenId))
        var imageMaskExpanded = expandedDimensions(imageMask, axis: -1)
        imageMaskExpanded = broadcast(imageMaskExpanded, to: inputEmbeds.shape)

        inputEmbeds = maskedScatter(
            finalEmbedding: inputEmbeds,
            imageMaskExpanded: imageMaskExpanded,
            scaledImageFeatures: imageFeatures
        )
        eval(inputEmbeds)

        // 6. Forward through language model with merged embeddings + per-layer inputs.
        //    Process all but the last token to fill the cache, then return
        //    the last token as .tokens so the TokenIterator handles the
        //    final step via the standard callAsFunction path.
        let seqLen = inputEmbeds.dim(1)
        if seqLen > 1 {
            let prefillEmbeds = inputEmbeds[0..., ..<(seqLen - 1), 0...]
            let prefillPerLayer = perLayerInputs?[0..., ..<(seqLen - 1), 0..., 0...]
            _ = languageModel.forwardWithEmbeddings(
                embeddings: prefillEmbeds,
                perLayerInputs: prefillPerLayer,
                cache: cache.isEmpty ? nil : cache)
            eval(cache)
        }

        // Return last token (1D) for the TokenIterator to process normally
        let lastToken = tokens[0, (seqLen - 1)...]
        return .tokens(.init(tokens: lastToken))
    }

    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var processed = weights

        // Filter audio tower (not needed for vision)
        processed = processed.filter { key, _ in
            !key.contains("audio_tower") && !key.contains("embed_audio")
        }

        // Filter clipping parameters — training-only, not in our module structure
        processed = processed.filter { key, _ in
            !key.contains("input_min") && !key.contains("input_max")
                && !key.contains("output_min") && !key.contains("output_max")
        }

        // Filter rotary embedding precomputed freqs
        processed = processed.filter { key, _ in
            !key.contains("self_attn.rotary_emb")
        }

        // Language model: tied word embeddings
        if config.textConfig.tieWordEmbeddings {
            processed = processed.filter { key, _ in
                !key.hasPrefix("language_model.lm_head.")
            }
        }

        // Truncate oversized vocab embeddings
        let expectedVocab = config.textConfig.vocabSize
        for key in [
            "language_model.model.embed_tokens.weight",
            "language_model.model.embed_tokens.scales",
            "language_model.model.embed_tokens.biases",
            "language_model.model.embed_tokens_per_layer.weight",
            "language_model.model.embed_tokens_per_layer.scales",
            "language_model.model.embed_tokens_per_layer.biases",
        ] {
            if let tensor = processed[key], tensor.dim(0) > expectedVocab {
                processed[key] = tensor[0..<expectedVocab]
            }
        }

        return processed
    }
}

// MARK: - Masked Scatter

/// Inserts image features into text embeddings at image token positions.
private func maskedScatter(
    finalEmbedding: MLXArray,
    imageMaskExpanded: MLXArray,
    scaledImageFeatures: MLXArray
) -> MLXArray {
    let finalEmbeddingShape = finalEmbedding.shape
    let scaledFeaturesFlat = scaledImageFeatures.flattened()
    let finalEmbeddingFlat = finalEmbedding.flattened()
    let maskFlat = imageMaskExpanded.flattened()

    let maskValues = maskFlat.asArray(Bool.self)
    let positionIndices = maskValues.enumerated().compactMap { index, value in
        value ? UInt32(index) : nil
    }

    guard !positionIndices.isEmpty else {
        return finalEmbedding
    }

    let positions = MLXArray(positionIndices)
    guard scaledFeaturesFlat.shape[0] == positions.shape[0] else {
        // Mismatch: return text-only embeddings (graceful fallback)
        return finalEmbedding
    }

    finalEmbeddingFlat[positions] = scaledFeaturesFlat
    return finalEmbeddingFlat.reshaped(finalEmbeddingShape)
}

// MARK: - Message Generator

/// Generates structured content messages for Gemma 4's chat template.
/// Images come before text so the chat template emits `<start_of_image>` before the user text.
struct Gemma4MessageGenerator: MessageGenerator {
    func generate(message: Chat.Message) -> Message {
        if message.images.isEmpty && message.videos.isEmpty {
            return [
                "role": message.role.rawValue,
                "content": message.content,
            ]
        }

        // Structured content: images first, then text
        var content: [[String: any Sendable]] = []
        for _ in message.images {
            content.append(["type": "image"])
        }
        if !message.content.isEmpty {
            content.append(["type": "text", "text": message.content])
        }

        return [
            "role": message.role.rawValue,
            "content": content,
        ]
    }
}

// MARK: - Processor Configuration

struct Gemma4ProcessorConfiguration: Codable, Sendable {
    let imageSize: Int
    let patchSize: Int
    let imageSeqLength: Int
    let imageMean: [Float]
    let imageStd: [Float]

    enum CodingKeys: String, CodingKey {
        case size
        case patchSize = "patch_size"
        case imageSeqLength = "image_seq_length"
        case imageMean = "image_mean"
        case imageStd = "image_std"
    }

    struct ImageSize: Codable {
        let height: Int
        let width: Int
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // size can be an int or a {height, width} dict
        if let sizeInt = try? container.decode(Int.self, forKey: .size) {
            imageSize = sizeInt
        } else if let sizeDict = try? container.decode(ImageSize.self, forKey: .size) {
            imageSize = sizeDict.height
        } else {
            imageSize = 490
        }

        patchSize = try container.decodeIfPresent(Int.self, forKey: .patchSize) ?? 16
        imageSeqLength = try container.decodeIfPresent(Int.self, forKey: .imageSeqLength) ?? 280
        imageMean = try container.decodeIfPresent([Float].self, forKey: .imageMean) ?? [0, 0, 0]
        imageStd = try container.decodeIfPresent([Float].self, forKey: .imageStd) ?? [1, 1, 1]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageSize, forKey: .size)
    }

    init(imageSize: Int = 490, patchSize: Int = 16) {
        self.imageSize = imageSize
        self.patchSize = patchSize
        self.imageSeqLength = 280
        self.imageMean = [0, 0, 0]
        self.imageStd = [1, 1, 1]
    }
}

// MARK: - Image-Aware Processor

struct Gemma4Processor: UserInputProcessor {
    let config: Gemma4ProcessorConfiguration
    let vlmConfig: Gemma4VLMConfiguration
    let tokenizer: any Tokenizer

    init(
        _ processorConfig: Gemma4ProcessorConfiguration,
        vlmConfig: Gemma4VLMConfiguration,
        tokenizer: any Tokenizer
    ) {
        self.config = processorConfig
        self.vlmConfig = vlmConfig
        self.tokenizer = tokenizer
    }

    func prepare(input: UserInput) async throws -> LMInput {
        let messages = Gemma4MessageGenerator().generate(from: input)

        var promptTokens = try tokenizer.applyChatTemplate(
            messages: messages, tools: input.tools,
            additionalContext: input.additionalContext)

        var processedImage: LMInput.ProcessedImage? = nil

        if !input.images.isEmpty {
            // Preprocess images
            let ciImages = try input.images.map { try $0.asCIImage() }
            let pixelArrays = ciImages.map { preprocessImage($0) }
            let pixelsConcatenated = concatenated(pixelArrays)

            processedImage = LMInput.ProcessedImage(
                pixels: pixelsConcatenated,
                frames: ciImages.map { _ in THW(1, config.imageSize, config.imageSize) }
            )

            // Expand image tokens: find <start_of_image> equivalent and expand
            // The chat template emits a single image placeholder token.
            // We expand it to: boi_token + image_token × N + eoi_token
            let numImageTokens = vlmConfig.visionSoftTokensPerImage
            var expandedTokens: [Int] = []

            for token in promptTokens {
                if token == vlmConfig.boiTokenId {
                    // boi_token found — expand to full image token sequence
                    expandedTokens.append(vlmConfig.boiTokenId)
                    expandedTokens.append(
                        contentsOf: Array(
                            repeating: vlmConfig.imageTokenId, count: numImageTokens))
                    expandedTokens.append(vlmConfig.eoiTokenId)
                } else if token == vlmConfig.imageTokenId {
                    // Single image token found (some templates emit this directly)
                    // Expand to: boi + image_tokens + eoi
                    expandedTokens.append(vlmConfig.boiTokenId)
                    expandedTokens.append(
                        contentsOf: Array(
                            repeating: vlmConfig.imageTokenId, count: numImageTokens))
                    expandedTokens.append(vlmConfig.eoiTokenId)
                } else {
                    expandedTokens.append(token)
                }
            }

            promptTokens = expandedTokens
        }

        // Return 1D tokens (no batch dim) — matches LLMUserInputProcessor convention.
        // The TokenIterator adds the batch dim via .newAxis when calling the model.
        let promptArray = MLXArray(promptTokens)
        return LMInput(
            text: .init(tokens: promptArray),
            image: processedImage
        )
    }

    /// Preprocess a single image: resize → rescale → normalize → NCHW MLXArray.
    /// Returns [1, 3, H, W] pixel array with values normalized to ~[-1, 1].
    private func preprocessImage(_ image: CIImage) -> MLXArray {
        let size = config.imageSize
        let targetSize = CGSize(width: size, height: size)

        // Resize using CoreImage (bicubic via affine + render)
        let scaleX = targetSize.width / image.extent.width
        let scaleY = targetSize.height / image.extent.height
        let resized = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Render to bitmap
        let context = CIContext()
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: size * bytesPerRow)

        context.render(
            resized,
            toBitmap: &pixelData,
            rowBytes: bytesPerRow,
            bounds: CGRect(origin: .zero, size: targetSize),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        // Convert to float [3, H, W] in NCHW format
        // Rescale to [0, 1] then normalize: (x - mean) / std
        let pixelCount = size * size
        var floatPixels = [Float](repeating: 0, count: 3 * pixelCount)
        for y in 0..<size {
            for x in 0..<size {
                let srcIdx = y * bytesPerRow + x * bytesPerPixel
                let r = Float(pixelData[srcIdx + 0]) / 255.0
                let g = Float(pixelData[srcIdx + 1]) / 255.0
                let b = Float(pixelData[srcIdx + 2]) / 255.0

                // NCHW: channel-first layout
                let pixelIdx = y * size + x
                floatPixels[0 * pixelCount + pixelIdx] =
                    (r - config.imageMean[0]) / config.imageStd[0]
                floatPixels[1 * pixelCount + pixelIdx] =
                    (g - config.imageMean[1]) / config.imageStd[1]
                floatPixels[2 * pixelCount + pixelIdx] =
                    (b - config.imageMean[2]) / config.imageStd[2]
            }
        }

        return MLXArray(floatPixels, [1, 3, size, size])
    }
}
