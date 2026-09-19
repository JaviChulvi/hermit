import CoreImage
import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
import MLXEmbedders
import MLXLMTokenizers

struct Passage: Decodable, Sendable { let id: String; let text: String; let language: String }
struct Question: Decodable, Sendable { let id: String; let text: String; let document: String; let language: String }
struct Corpus: Decodable, Sendable { let documents: [Passage]; let questions: [Question] }

func gemma(directory: URL, output: URL) async throws {
    await registerGemma4ModelType()
    let configData = try Data(contentsOf: directory.appendingPathComponent("config.json"))
    let base = try JSONDecoder.json5().decode(MLXLMCommon.BaseConfiguration.self, from: configData)
    let model = try await LLMTypeRegistry.shared.createModel(configuration: configData, modelType: base.modelType)
    print("Original registered model: \(type(of: model))")
    try loadWeights(modelDirectory: directory, model: model, perLayerQuantization: base.perLayerQuantization)
    let tokenizer = try await TokenizersLoader().load(from: directory)
    let configuration = try JSONDecoder.json5().decode(Gemma4VLMConfiguration.self, from: configData)
    let processorConfig = try JSONDecoder.json5().decode(Gemma4ProcessorConfiguration.self,
        from: Data(contentsOf: directory.appendingPathComponent("processor_config.json")))
    let processor = Gemma4Processor(processorConfig, vlmConfig: configuration, tokenizer: tokenizer)
    let context = ModelContext(configuration: ModelConfiguration(directory: directory,
        extraEOSTokens: ["<end_of_turn>"]), model: model, processor: processor, tokenizer: tokenizer)
    let session = ChatSession(context, generateParameters: .init(maxTokens: 64, temperature: 0), processing: .init())
    let answer = try await session.respond(to: "Reply with only the capital of France.")
    try Data(answer.utf8).write(to: output)
}

func embeddings(directory: URL, corpusPath: URL, output: URL) async throws {
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: corpusPath))
    let container = try await MLXEmbedders.loadModelContainer(from: directory, using: TokenizersLoader())
    let data = try await container.perform { model, tokenizer, pooling in
        func embed(_ text: String) -> [Float] {
            let tokens = MLXArray(tokenizer.encode(text: text, addSpecialTokens: true)).expandedDimensions(axis: 0)
            let output = model(tokens, positionIds: nil, tokenTypeIds: MLXArray.zeros(like: tokens), attentionMask: MLXArray.ones(like: tokens))
            let vector = pooling(output, normalize: true, applyLayerNorm: true)
            vector.eval()
            return vector.squeezed().asArray(Float.self)
        }
        var chunks: [[String: Any]] = [], failures: [[String: Any]] = []
        let start = Date()
        for document in corpus.documents {
            let pieces = ChunkingStrategy.chunk(text: document.text, targetWords: 300, overlapWords: 50)
            let lengths = pieces.map { tokenizer.encode(text: $0, addSpecialTokens: true).count }
            // Reject out-of-capacity inputs rather than invoke an undefined gather.
            guard lengths.allSatisfy({ $0 <= 512 }) else {
                failures.append(["document": document.id, "tokenLengths": lengths]); continue
            }
            for (index, text) in pieces.enumerated() {
                chunks.append(["document": document.id, "language": document.language, "index": index,
                    "text": text, "tokens": lengths[index], "fullTokens": lengths[index], "vector": embed(text)])
            }
        }
        var queries: [[String: Any]] = []
        for query in corpus.questions {
            queries.append(["id": query.id, "document": query.document, "language": query.language,
                "text": query.text, "vector": embed(query.text)])
        }
        return try JSONSerialization.data(withJSONObject: ["candidate": "original_stack", "chunks": chunks,
            "queries": queries, "failures": failures, "seconds": Date().timeIntervalSince(start),
            "capacity": 512, "shortTokenCount": tokenizer.encode(text: "hello", addSpecialTokens: true).count,
            "longTokenCount": tokenizer.encode(text: String(repeating: "hello ", count: 600), addSpecialTokens: true).count], options: [.sortedKeys])
    }
    try data.write(to: output, options: .atomic)
}

@main struct Run {
    static func main() async throws {
        Memory.cacheLimit = 0
        let args = CommandLine.arguments
        if args[1] == "gemma" {
            do { try await gemma(directory: URL(fileURLWithPath: args[2]), output: URL(fileURLWithPath: args[3])) }
            catch {
                try Data(String(reflecting: error).utf8).write(to: URL(fileURLWithPath: args[3]))
                print("Original Gemma load failed: \(String(reflecting: error))")
            }
        } else {
            try await embeddings(directory: URL(fileURLWithPath: args[2]), corpusPath: URL(fileURLWithPath: args[3]), output: URL(fileURLWithPath: args[4]))
        }
    }
}
