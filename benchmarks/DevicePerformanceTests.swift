// Added only to the isolated device test target, never the shipping app.
import CoreImage
import Foundation
import MLX
import MLXLMCommon
import Testing
@testable import Hermit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["HERMIT_DEVICE_BENCHMARKS"] == "1"), .serialized)
@MainActor
struct DevicePerformanceTests {
    struct Inputs: Decodable, Sendable {
        let textPrompt: String
        let photoPrompt: String
        let documents: [String]
        let queries: [String]
    }

    private var documents: URL { URL.documentsDirectory }

    private func save(_ rows: [[String: Any]], name: String) throws {
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
            .write(to: documents.appendingPathComponent(name), options: .atomic)
    }

    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / 4)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }

    @Test func cacheAndBatchSweeps() async throws {
        let inputs = try JSONDecoder().decode(Inputs.self,
            from: Data(contentsOf: documents.appendingPathComponent("hermit-benchmark-inputs.json")))
        let photo = documents.appendingPathComponent("hermit-cats.png")
        let manager = ModelManager()
        try #require(manager.llmModelDownloaded && manager.embeddingModelDownloaded)
        defer { manager.unloadAll() }
        var gaps: [Double] = []
        let heartbeat = Task { @MainActor in
            var previous = Date()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { break }
                let now = Date()
                gaps.append(now.timeIntervalSince(previous))
                previous = now
            }
        }
        defer { heartbeat.cancel() }

        var rows: [[String: Any]] = []
        try await manager.withLLM { container in
            // Independent fresh sessions, warm once per setting, then interleave.
            for repetition in -1..<5 {
                for cacheMB in [0, 32, 64] {
                    for isPhoto in [false, true] {
                        Memory.clearCache()
                        Memory.cacheLimit = cacheMB * 1024 * 1024
                        Memory.peakMemory = 0
                        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
                        let instructions = "You are Hermit. Be concise, answer in the user's language, and say if you don't know."
                        let prompt = isPhoto ? inputs.photoPrompt : inputs.textPrompt
                        let preprocessingStart = Date()
                        let shape = try await container.perform { context in
                            let images: [UserInput.Image] = isPhoto ? [.ciImage(try #require(CIImage(contentsOf: photo)))] : []
                            let input = try await context.processor.prepare(input: UserInput(chat: [
                                .system(instructions), .user(prompt, images: images)
                            ], processing: .init()))
                            input.image?.pixels.eval()
                            Stream.gpu.synchronize()
                            return ["tokens": input.text.tokens.size, "pixels": input.image?.pixels.size ?? 0]
                        }
                        let preprocessingSeconds = Date().timeIntervalSince(preprocessingStart)
                        let session = ChatSession(container, history: [.system(instructions)],
                            generateParameters: .init(maxTokens: 128, temperature: 0,
                                repetitionPenalty: 1.1, repetitionContextSize: 64), processing: .init())
                        let images: [UserInput.Image] = isPhoto ? [.ciImage(try #require(CIImage(contentsOf: photo)))] : []
                        var text = ""
                        var stats: GenerateCompletionInfo?
                        let started = Date()
                        for try await event in session.streamDetails(to: [.user(prompt, images: images)]) {
                            if let chunk = event.chunk { text += chunk }
                            if let info = event.info { stats = info }
                        }
                        await session.synchronize()
                        Stream.gpu.synchronize()
                        let elapsed = Date().timeIntervalSince(started)
                        let info = try #require(stats)
                        rows.append(["workload": isPhoto ? "photo" : "text", "cacheMB": cacheMB,
                            "repetition": repetition, "preprocessSeconds": preprocessingSeconds,
                            "prepared": shape, "responseSeconds": elapsed, "prefillSeconds": info.promptTime,
                            "decodeSeconds": info.generateTime, "promptTokens": info.promptTokenCount,
                            "generatedTokens": info.generationTokenCount, "peakBytes": Memory.peakMemory,
                            "footprintBytes": self.footprint(), "availableBytes": os_proc_available_memory(),
                            "thermalBefore": thermalBefore, "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue,
                            "output": text])
                        try self.save(rows, name: "hermit-device-cache.json")
                        print("DEVICE cache=\(cacheMB) photo=\(isPhoto) repeat=\(repetition) seconds=\(elapsed)")
                    }
                }
            }
        }
        manager.unloadAll()

        // These timings include the app's model load/unload for each embedding call.
        let texts = try await manager.withEmbeddingModel { container in
            try await container.perform { context in
                try inputs.documents.flatMap { text in
                    try ChunkingStrategy.chunk(text: text, maxTokens: 256, overlapTokens: 32) {
                        context.tokenizer.encode(text: $0, addSpecialTokens: true).count
                    }
                }
            }
        }
        let singles = EmbeddingService(modelManager: manager)
        let reference = try await singles.embed(chunks: texts, progress: { _, _ in })
        let queries = try await singles.embed(chunks: inputs.queries, progress: { _, _ in })
        let referenceRanks = queries.map { findTopK(query: $0, candidates: reference, k: 3).map(\.index) }
        var batches: [[String: Any]] = []
        for repetition in -1..<5 {
            for size in [1, 4, 8] {
                Memory.peakMemory = 0
                let started = Date()
                let vectors = try await EmbeddingService(modelManager: manager, batchSize: size)
                    .embed(chunks: texts, progress: { _, _ in })
                Stream.gpu.synchronize()
                let elapsed = Date().timeIntervalSince(started)
                let ranks = queries.map { findTopK(query: $0, candidates: vectors, k: 3).map(\.index) }
                let agreement = Double(zip(referenceRanks, ranks).filter { $0 == $1 }.count) / Double(queries.count)
                batches.append(["batch": size, "repetition": repetition, "chunks": texts.count,
                    "seconds": elapsed, "peakBytes": Memory.peakMemory, "footprintBytes": footprint(),
                    "minimumCosine": zip(reference, vectors).map { cosineSimilarity($0, $1) }.min()!,
                    "top3Agreement": agreement, "thermal": ProcessInfo.processInfo.thermalState.rawValue])
                try save(batches, name: "hermit-device-batches.json")
                #expect(manager.modelState == .idle && !manager.isBusy)
            }
        }
        try save([["mainActorSchedulingGapsSeconds": gaps, "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "finalFootprintBytes": footprint(), "finalMLXActiveBytes": Memory.activeMemory,
            "finalMLXCacheBytes": Memory.cacheMemory]], name: "hermit-device-runtime.json")
    }
}
