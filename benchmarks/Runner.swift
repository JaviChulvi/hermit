// Native validation only. Build with prepare.py; this file is not an app target.
import Foundation
import Accelerate
import CoreImage
import MLX
import MLXNN
import MLXLLM
import MLXVLM
import MLXLMCommon
import MLXEmbedders
import MLXLMTokenizers

struct Passage: Codable, Sendable { let id: String; let text: String; let language: String }
struct Question: Codable, Sendable { let id: String; let text: String; let document: String; let language: String }
struct Corpus: Codable, Sendable { let documents: [Passage]; let questions: [Question] }

func write(_ rows: Any, to path: String) throws {
    try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
        .write(to: URL(fileURLWithPath: path), options: .atomic)
}

func legacyModel(_ directory: URL) async throws -> MLXLMCommon.ModelContainer {
    let configData = try Data(contentsOf: directory.appendingPathComponent("config.json"))
    let base = try JSONDecoder.json5().decode(BaseConfiguration.self, from: configData)
    let configuration = try JSONDecoder.json5().decode(Gemma4VLMConfiguration.self, from: configData)
    let model = Gemma4VLMModel(configuration)
    try loadWeights(modelDirectory: directory, model: model, perLayerQuantization: base.perLayerQuantization)
    let tokenizer = try await TokenizersLoader().load(from: directory)
    let processorConfig = try JSONDecoder.json5().decode(Gemma4ProcessorConfiguration.self,
        from: Data(contentsOf: directory.appendingPathComponent("processor_config.json")))
    let processor = Gemma4Processor(processorConfig, vlmConfig: configuration, tokenizer: tokenizer)
    let generation = try JSONSerialization.jsonObject(with: Data(contentsOf:
        directory.appendingPathComponent("generation_config.json"))) as! [String: Any]
    let eos = (generation["eos_token_id"] as? [Int]) ?? [generation["eos_token_id"] as? Int].compactMap { $0 }
    return ModelContainer(context: ModelContext(configuration: ModelConfiguration(directory: directory,
        extraEOSTokens: ["<end_of_turn>"], eosTokenIds: Set(eos)), model: model,
        processor: processor, tokenizer: tokenizer))
}

func gemma(arm: String, directory: URL, prompt: String, imagePath: String?, output: String) async throws {
    Memory.cacheLimit = 0
    let start = Date()
    let container = try await arm == "legacy" ? legacyModel(directory)
        : VLMModelFactory.shared.loadContainer(from: directory, using: TokenizersLoader())
    let loadSeconds = Date().timeIntervalSince(start)
    var rows: [[String: Any]] = []
    // Each arm runs in its own process. Warm each setting, then interleave 5 repeats.
    let repetitions = Int(ProcessInfo.processInfo.environment["HERMIT_BENCH_REPEATS"] ?? "5")!
    let caches = (ProcessInfo.processInfo.environment["HERMIT_BENCH_CACHE_MB"] ?? "0,32,64").split(separator: ",").map { Int($0)! }
    for repetition in -1..<repetitions {
        for cacheMB in caches {
            Memory.clearCache()
            Memory.cacheLimit = cacheMB * 1024 * 1024
            Memory.peakMemory = 0
            let instructions = "You are Hermit. Be concise, answer in the user's language, and say if you don't know."
            let preprocessingStart = Date()
            let shape = try await container.perform { context in
                let images: [UserInput.Image] = try imagePath.map { [.ciImage(try CIImage(contentsOf: URL(fileURLWithPath: $0)).unwrap())] } ?? []
                let input = try await context.processor.prepare(input: UserInput(chat: [
                    .system(instructions), .user(prompt, images: images)
                ], processing: .init()))
                input.image?.pixels.eval()
                Stream.gpu.synchronize()
                return ["tokens": input.text.tokens.size, "pixels": input.image?.pixels.size ?? 0]
            }
            let preprocessingSeconds = Date().timeIntervalSince(preprocessingStart)
            let session = ChatSession(container, history: [.system(instructions)],
                generateParameters: .init(maxTokens: 128, temperature: 0, repetitionPenalty: 1.1, repetitionContextSize: 64),
                processing: .init())
            let images: [UserInput.Image] = try imagePath.map { [.ciImage(try CIImage(contentsOf: URL(fileURLWithPath: $0)).unwrap())] } ?? []
            var text = ""
            var stats: GenerateCompletionInfo?
            let responseStart = Date()
            for try await event in session.streamDetails(to: [.user(prompt, images: images)]) {
                if let chunk = event.chunk { text += chunk }
                if let info = event.info { stats = info }
            }
            await session.synchronize()
            Stream.gpu.synchronize()
            let elapsed = Date().timeIntervalSince(responseStart)
            guard let info = stats else { throw NSError(domain: "Missing generation metrics", code: 1) }
            rows.append(["arm": arm, "repetition": repetition, "cacheMB": cacheMB, "prompt": prompt,
                "image": imagePath ?? "", "loadSeconds": loadSeconds, "preprocessSeconds": preprocessingSeconds,
                "prepared": shape, "responseSeconds": elapsed, "promptTokens": info.promptTokenCount,
                "generatedTokens": info.generationTokenCount, "prefillSeconds": info.promptTime,
                "decodeSeconds": info.generateTime, "stopReason": String(describing: info.stopReason),
                "activeBytes": Memory.activeMemory, "peakBytes": Memory.peakMemory,
                "cachedBytes": Memory.cacheMemory, "output": text])
            try write(rows, to: output)
            print("\(arm) cache=\(cacheMB) repeat=\(repetition) tokens=\(info.generationTokenCount) time=\(elapsed)")
        }
    }
}

extension Optional {
    func unwrap() throws -> Wrapped {
        guard let value = self else { throw NSError(domain: "Missing input", code: 1) }
        return value
    }
}

func embeddings(directory: URL, corpusPath: String, candidate: String, output: String) async throws {
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: corpusPath)))
    Memory.cacheLimit = 0
    let fullTokenizer = try await EmbeddingTokenizerLoader().load(from: directory)
    let loader: any TokenizerLoader = candidate == "legacy" ? TokenizersLoader() : EmbeddingTokenizerLoader()
    let container = try await EmbedderModelFactory.shared.loadContainer(from: directory, using: loader)
    let data = try await container.perform { context in
        var chunks: [[String: Any]] = []
        var failures: [[String: Any]] = []
        let capacity = context.model.maxPositionEmbeddings ?? 512
        let parameters = candidate == "tokenizer_only" ? [256, 32] : candidate.split(separator: "_").compactMap { Int($0) }
        let started = Date()
        for document in corpus.documents {
            let pieces: [String]
            if candidate.hasPrefix("legacy") {
                pieces = LegacyChunkingStrategy.chunk(text: document.text, targetWords: 300, overlapWords: 50)
            } else {
                pieces = try ChunkingStrategy.chunk(text: document.text, maxTokens: parameters[0], overlapTokens: parameters[1]) {
                    context.tokenizer.encode(text: $0, addSpecialTokens: true).count
                }
            }
            let lengths = pieces.map { context.tokenizer.encode(text: $0, addSpecialTokens: true).count }
            guard lengths.allSatisfy({ $0 <= capacity }) else {
                failures.append(["document": document.id, "tokenLengths": lengths]); continue
            }
            for (index, text) in pieces.enumerated() {
                let vector: [Float]
                if candidate.hasPrefix("legacy") || candidate == "tokenizer_only" {
                    let encoded = context.tokenizer.encode(text: text, addSpecialTokens: true)
                    let tokens = MLXArray(encoded).expandedDimensions(axis: 0)
                    let result = context.model(tokens, positionIds: nil, tokenTypeIds: MLXArray.zeros(like: tokens), attentionMask: MLXArray.ones(like: tokens))
                    let pooled = context.pooling(result, normalize: true, applyLayerNorm: true)
                    pooled.eval()
                    vector = pooled.squeezed().asArray(Float.self)
                } else {
                    vector = try embed([text], context: context)[0]
                }
                chunks.append(["document": document.id, "language": document.language, "index": index,
                    "text": text, "tokens": lengths[index], "fullTokens": fullTokenizer.encode(text: text, addSpecialTokens: true).count, "vector": vector])
            }
        }
        var queries: [[String: Any]] = []
        for query in corpus.questions {
            queries.append(["id": query.id, "document": query.document, "language": query.language,
                "text": query.text, "vector": try queryVector(query.text, context: context, legacyPooling: candidate.hasPrefix("legacy") || candidate == "tokenizer_only")])
        }
        return try JSONSerialization.data(withJSONObject: ["candidate": candidate, "chunks": chunks,
            "queries": queries, "failures": failures, "seconds": Date().timeIntervalSince(started),
            "capacity": capacity, "peakBytes": Memory.peakMemory], options: [.sortedKeys])
    }
    try data.write(to: URL(fileURLWithPath: output), options: .atomic)
}

func queryVector(_ text: String, context: EmbedderModelContext, legacyPooling: Bool) throws -> [Float] {
    guard legacyPooling else { return try embed([text], context: context)[0] }
    let tokens = MLXArray(context.tokenizer.encode(text: text, addSpecialTokens: true)).expandedDimensions(axis: 0)
    let output = context.model(tokens, positionIds: nil, tokenTypeIds: MLXArray.zeros(like: tokens), attentionMask: MLXArray.ones(like: tokens))
    let vector = context.pooling(output, normalize: true, applyLayerNorm: true)
    vector.eval()
    return vector.squeezed().asArray(Float.self)
}

func batches(directory: URL, corpusPath: String, output: String) async throws {
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: corpusPath)))
    Memory.cacheLimit = 0
    let container = try await EmbedderModelFactory.shared.loadContainer(from: directory, using: EmbeddingTokenizerLoader())
    let data = try await container.perform { context in
        let texts = try corpus.documents.prefix(32).flatMap {
            try ChunkingStrategy.chunk(text: $0.text, maxTokens: 256, overlapTokens: 32) {
                context.tokenizer.encode(text: $0, addSpecialTokens: true).count
            }
        }
        let reference = try texts.map { try embed([$0], context: context)[0] }
        let balancedQuestions = ["en", "es"].flatMap { language in Array(corpus.questions.filter { $0.language == language }.prefix(16)) }
        let queries = try balancedQuestions.map { try embed([$0.text], context: context)[0] }
        let referenceRanks = queries.map { findTopK(query: $0, candidates: reference, k: 3).map(\.index) }
        var rows: [[String: Any]] = []
        for repetition in -1..<5 {
            for size in [1, 4, 8] {
                Memory.clearCache(); Memory.peakMemory = 0
                let start = Date()
                var vectors: [[Float]] = []
                for index in stride(from: 0, to: texts.count, by: size) {
                    vectors += try embed(Array(texts[index..<min(index + size, texts.count)]), context: context)
                }
                Stream.gpu.synchronize()
                let elapsed = Date().timeIntervalSince(start)
                let similarities = zip(reference, vectors).map { cosineSimilarity($0, $1) }
                rows.append(["batch": size, "repetition": repetition, "chunks": texts.count,
                    "seconds": elapsed, "minimumCosine": similarities.min()!, "peakBytes": Memory.peakMemory,
                    "top3Agreement": Double(zip(referenceRanks, queries.map { findTopK(query: $0, candidates: vectors, k: 3).map(\.index) }).filter { $0 == $1 }.count) / Double(queries.count)])
            }
        }
        return try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
    }
    try data.write(to: URL(fileURLWithPath: output), options: .atomic)
}

@main struct Run {
    static func main() async throws {
        let args = CommandLine.arguments
        switch args[1] {
        case "search": try searchBenchmark(output: args[2])
        case "sessions": try await sessionChecks(directory: URL(fileURLWithPath: args[2]), output: args[3], imagePath: args[4])
        case "answers": try await answers(directory: URL(fileURLWithPath: args[2]), cases: args[3], output: args[4])
        case "fixtures": try makeFixtures(directory: args[2])
        case "gemma":
            try await gemma(arm: args[2], directory: URL(fileURLWithPath: args[3]), prompt: args[4],
                imagePath: args[5] == "-" ? nil : args[5], output: args[6])
        case "embeddings":
            try await embeddings(directory: URL(fileURLWithPath: args[2]), corpusPath: args[3], candidate: args[4], output: args[5])
        case "batches":
            try await batches(directory: URL(fileURLWithPath: args[2]), corpusPath: args[3], output: args[4])
        default: fatalError("Use gemma, embeddings, or batches")
        }
    }
}

func searchBenchmark(output: String) throws {
    var seed: UInt64 = 20260919
    func vector() -> [Float] {
        (0..<384).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24) * 2 - 1
        }
    }
    let queries = (0..<10).map { _ in vector() }
    var rows: [[String: Any]] = []
    for count in [1000, 10000, 30000] {
        let vectors = (0..<count).map { _ in vector() }
        let unitVectors = vectors.map { normalized($0)! }
        let expected = queries.map { query in
            vectors.enumerated().map { (index: $0.offset, score: cosineSimilarity(query, $0.element)) }
                .sorted { $0.score > $1.score }.prefix(3).map(\.index)
        }
        for repetition in -1..<5 {
            for arm in ["full_sort_cosine", "bounded_normalized"] {
                let start = Date()
                let ranks: [[Int]] = queries.map { query in
                    if arm == "full_sort_cosine" {
                        return vectors.enumerated().map { (index: $0.offset, score: cosineSimilarity(query, $0.element)) }
                            .sorted { $0.score > $1.score }.prefix(3).map(\.index)
                    }
                    let query = normalized(query)!
                    return topK(unitVectors.enumerated().lazy.map {
                        (index: $0.offset, score: vDSP.dot(query, $0.element))
                    }, k: 3).map(\.index)
                }
                let elapsed = Date().timeIntervalSince(start)
                guard ranks == expected else { throw NSError(domain: "Top-K rank mismatch", code: 1) }
                rows.append(["arm": arm, "vectors": count, "dimensions": 384, "queries": queries.count,
                    "repetition": repetition, "seconds": elapsed, "rankAgreement": true])
            }
        }
    }
    try write(rows, to: output)
}
