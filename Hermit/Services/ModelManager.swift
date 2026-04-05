import Foundation
import Observation
import HFAPI
import MLXLMHFAPI
import MLX
import MLXLLM
import MLXEmbedders
import MLXLMCommon
import MLXLMTokenizers
import Metal
import UIKit
import os

private let logger = Logger(subsystem: "com.hermit.app", category: "ModelManager")

/// Whether the Metal GPU is available (false on Simulator)
private let metalAvailable: Bool = MTLCreateSystemDefaultDevice() != nil

enum ModelState: Equatable {
    case idle
    case embeddingLoaded
    case llmLoaded
    case transitioning
}

enum ModelManagerError: LocalizedError {
    case insufficientMemory(availableMB: Int, requiredMB: Int)
    case modelNotDownloaded(String)
    case metalUnavailable

    var errorDescription: String? {
        switch self {
        case .insufficientMemory(let available, let required):
            return "Not enough memory: \(available) MB available, \(required) MB required"
        case .modelNotDownloaded(let name):
            return "Model '\(name)' is not downloaded"
        case .metalUnavailable:
            return "MLX requires a physical device with Metal GPU support. The iOS Simulator is not supported."
        }
    }
}

@Observable
@MainActor
final class ModelManager {
    // MARK: - Public State

    private(set) var modelState: ModelState = .idle
    private(set) var embeddingDownloadState: DownloadState = .notStarted
    private(set) var llmDownloadState: DownloadState = .notStarted

    var embeddingModelDownloaded: Bool {
        cachedModelURL(for: ModelInfo.embeddingModel.id) != nil
    }

    var llmModelDownloaded: Bool {
        cachedModelURL(for: ModelInfo.llmModel.id) != nil
    }

    var availableMemoryMB: Int {
        memoryMonitor.availableMemoryMB
    }

    // MARK: - Model Containers

    private(set) var embeddingContainer: MLXEmbedders.ModelContainer?
    private(set) var llmContainer: MLXLMCommon.ModelContainer?

    // MARK: - Private

    private let memoryMonitor: MemoryMonitor
    private let hubClient = HubClient()
    private var embeddingDownloadTask: Task<Void, Error>?
    private var llmDownloadTask: Task<Void, Error>?
    nonisolated(unsafe) private var memoryWarningObserver: Any?

    private static let modelFilePatterns = ["*.safetensors", "*.json", "*.txt", "*.jinja", "*.model"]

    // MARK: - Init

    init(memoryMonitor: MemoryMonitor = MemoryMonitor()) {
        self.memoryMonitor = memoryMonitor
        logger.info("ModelManager init — available RAM: \(memoryMonitor.availableMemoryMB) MB")
        logger.info("HF cache directory: \(self.hubClient.cache.cacheDirectory.path)")
        checkDownloadedModels()
        logger.info("Embedding downloaded: \(self.embeddingModelDownloaded), LLM downloaded: \(self.llmModelDownloaded)")
        subscribeToMemoryWarnings()
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Download Methods

    func downloadEmbeddingModel() async throws {
        embeddingDownloadState = .downloading(progress: 0)

        do {
            try Task.checkCancellation()
            let _ = try await hubClient.download(
                id: ModelInfo.embeddingModel.id,
                revision: nil,
                matching: Self.modelFilePatterns,
                useLatest: false,
                progressHandler: { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        self?.embeddingDownloadState = .downloading(progress: fraction)
                    }
                }
            )
            embeddingDownloadState = .completed
        } catch is CancellationError {
            embeddingDownloadState = .notStarted
        } catch {
            if Task.isCancelled {
                embeddingDownloadState = .notStarted
            } else {
                embeddingDownloadState = .error(message: error.localizedDescription)
                throw error
            }
        }
    }

    func downloadLLMModel() async throws {
        llmDownloadState = .downloading(progress: 0)

        do {
            try Task.checkCancellation()
            let _ = try await hubClient.download(
                id: ModelInfo.llmModel.id,
                revision: nil,
                matching: Self.modelFilePatterns,
                useLatest: false,
                progressHandler: { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        self?.llmDownloadState = .downloading(progress: fraction)
                    }
                }
            )
            llmDownloadState = .completed
        } catch is CancellationError {
            llmDownloadState = .notStarted
        } catch {
            if Task.isCancelled {
                llmDownloadState = .notStarted
            } else {
                llmDownloadState = .error(message: error.localizedDescription)
                throw error
            }
        }
    }

    func cancelDownloads() {
        embeddingDownloadTask?.cancel()
        llmDownloadTask?.cancel()
        embeddingDownloadTask = nil
        llmDownloadTask = nil
        if case .downloading = embeddingDownloadState {
            embeddingDownloadState = .notStarted
        }
        if case .downloading = llmDownloadState {
            llmDownloadState = .notStarted
        }
    }

    func deleteModels() throws {
        let cacheDir = hubClient.cache.cacheDirectory

        for modelId in [ModelInfo.embeddingModel.id, ModelInfo.llmModel.id] {
            let dirName = "models--\(modelId.replacingOccurrences(of: "/", with: "--"))"
            let modelDir = cacheDir.appendingPathComponent(dirName)
            if FileManager.default.fileExists(atPath: modelDir.path) {
                try FileManager.default.removeItem(at: modelDir)
            }
        }

        embeddingDownloadState = .notStarted
        llmDownloadState = .notStarted
        modelState = .idle
    }

    func diskSpaceUsedMB() -> Int {
        let cacheDir = hubClient.cache.cacheDirectory

        guard let enumerator = FileManager.default.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return Int(totalSize / (1024 * 1024))
    }

    // MARK: - Model Loading

    func loadEmbeddingModel() async throws {
        guard metalAvailable else {
            logger.error("Metal GPU not available — cannot load MLX models on Simulator")
            throw ModelManagerError.metalUnavailable
        }

        logger.info("loadEmbeddingModel() — current state: \(String(describing: self.modelState))")

        if modelState == .embeddingLoaded, embeddingContainer != nil {
            logger.info("Embedding model already loaded, skipping")
            return
        }

        if modelState == .llmLoaded {
            logger.info("LLM is loaded, unloading first...")
            unloadLLM()
        }

        modelState = .transitioning

        guard let directory = cachedModelURL(for: ModelInfo.embeddingModel.id) else {
            logger.error("Embedding model not found on disk. Model ID: \(ModelInfo.embeddingModel.id)")
            modelState = .idle
            throw ModelManagerError.modelNotDownloaded(ModelInfo.embeddingModel.name)
        }

        logger.info("Embedding model directory: \(directory.path)")

        // List files in the directory for debugging
        if let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            logger.info("Files in model directory: \(files.joined(separator: ", "))")
        }

        if metalAvailable {
            let memBefore = Memory.snapshot()
            logger.info("Memory before load — active: \(memBefore.activeMemory / 1024 / 1024) MB, cache: \(memBefore.cacheMemory / 1024 / 1024) MB, peak: \(memBefore.peakMemory / 1024 / 1024) MB")
        }
        logger.info("System available RAM: \(self.memoryMonitor.availableMemoryMB) MB")

        if metalAvailable {
            logger.info("Setting MLX cache limit to 0...")
            MLX.Memory.cacheLimit = 0
            MLX.Memory.clearCache()
            logger.info("Cache cleared. Cache memory now: \(Memory.cacheMemory / 1024 / 1024) MB")
        }

        do {
            logger.info("Loading embedding model container from disk...")
            let container = try await MLXEmbedders.loadModelContainer(
                from: directory,
                using: TokenizersLoader()
            )

            logger.info("Embedding model loaded successfully!")
            if metalAvailable {
                let memAfter = Memory.snapshot()
                logger.info("Memory after load — active: \(memAfter.activeMemory / 1024 / 1024) MB, cache: \(memAfter.cacheMemory / 1024 / 1024) MB")
            }

            embeddingContainer = container
            modelState = .embeddingLoaded
            logger.info("State → .embeddingLoaded")
        } catch {
            logger.error("Failed to load embedding model: \(error.localizedDescription)")
            logger.error("Error type: \(type(of: error))")
            logger.error("Full error: \(String(describing: error))")
            modelState = .idle
            throw error
        }
    }

    func loadLLM() async throws {
        guard metalAvailable else {
            logger.error("Metal GPU not available — cannot load MLX models on Simulator")
            throw ModelManagerError.metalUnavailable
        }

        logger.info("loadLLM() — current state: \(String(describing: self.modelState))")

        if modelState == .llmLoaded, llmContainer != nil {
            logger.info("LLM already loaded, skipping")
            return
        }

        if modelState == .embeddingLoaded {
            logger.info("Embedding is loaded, unloading first...")
            unloadEmbedding()
        }

        modelState = .transitioning

        let requiredMB = 3200
        logger.info("Checking memory: available \(self.memoryMonitor.availableMemoryMB) MB, required \(requiredMB) MB")
        if !memoryMonitor.hasEnoughMemory(requiredMB: requiredMB) {
            logger.error("Insufficient memory for LLM: \(self.memoryMonitor.availableMemoryMB) MB < \(requiredMB) MB")
            modelState = .idle
            throw ModelManagerError.insufficientMemory(
                availableMB: memoryMonitor.availableMemoryMB,
                requiredMB: requiredMB
            )
        }

        guard let directory = cachedModelURL(for: ModelInfo.llmModel.id) else {
            logger.error("LLM model not found on disk. Model ID: \(ModelInfo.llmModel.id)")
            modelState = .idle
            throw ModelManagerError.modelNotDownloaded(ModelInfo.llmModel.name)
        }

        logger.info("LLM model directory: \(directory.path)")

        if let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            logger.info("Files in LLM directory: \(files.joined(separator: ", "))")
        }

        if metalAvailable {
            let memBefore = Memory.snapshot()
            logger.info("Memory before LLM load — active: \(memBefore.activeMemory / 1024 / 1024) MB, cache: \(memBefore.cacheMemory / 1024 / 1024) MB")
            logger.info("Setting MLX cache limit to 0...")
            MLX.Memory.cacheLimit = 0
            MLX.Memory.clearCache()
        }

        do {
            // Register Gemma 4 VLM model type (no-op if already registered)
            await registerGemma4ModelType()

            logger.info("Loading VLM container from disk...")

            // Custom loading path: build ModelContext with our VLM processor
            let configURL = directory.appending(component: "config.json")
            let configData = try Data(contentsOf: configURL)
            let decoder = JSONDecoder.json5()
            let baseConfig: MLXLMCommon.BaseConfiguration = try decoder.decode(
                MLXLMCommon.BaseConfiguration.self, from: configData)

            // Create VLM model via type registry
            let model = try await LLMTypeRegistry.shared.createModel(
                configuration: configData, modelType: baseConfig.modelType)

            // Load weights (calls model.sanitize() internally)
            try loadWeights(
                modelDirectory: directory, model: model,
                perLayerQuantization: baseConfig.perLayerQuantization)

            // Load tokenizer
            let tokenizer = try await TokenizersLoader().load(from: directory)

            // Load processor config and create image-aware processor
            let vlmConfig = try JSONDecoder.json5().decode(
                Gemma4VLMConfiguration.self, from: configData)
            let processorConfigURL = directory.appending(component: "processor_config.json")
            let processorConfig: Gemma4ProcessorConfiguration
            if let processorData = try? Data(contentsOf: processorConfigURL) {
                processorConfig = try JSONDecoder.json5().decode(
                    Gemma4ProcessorConfiguration.self, from: processorData)
            } else {
                processorConfig = Gemma4ProcessorConfiguration()
            }
            let processor = Gemma4Processor(
                processorConfig, vlmConfig: vlmConfig, tokenizer: tokenizer)

            // Read EOS token IDs from generation_config.json (like LLMModelFactory does)
            var eosTokenIds = Set<Int>()
            let genConfigURL = directory.appending(component: "generation_config.json")
            if let genData = try? Data(contentsOf: genConfigURL),
                let genJSON = try? JSONSerialization.jsonObject(with: genData) as? [String: Any]
            {
                if let eosId = genJSON["eos_token_id"] as? Int {
                    eosTokenIds.insert(eosId)
                } else if let eosIds = genJSON["eos_token_id"] as? [Int] {
                    eosTokenIds.formUnion(eosIds)
                }
            }

            // Build ModelContext → ModelContainer
            let modelConfig = ModelConfiguration(
                directory: directory,
                extraEOSTokens: ["<end_of_turn>"],
                eosTokenIds: eosTokenIds)
            let context = ModelContext(
                configuration: modelConfig, model: model,
                processor: processor, tokenizer: tokenizer)
            let container = ModelContainer(context: context)

            logger.info("VLM loaded successfully!")
            if metalAvailable {
                let memAfter = Memory.snapshot()
                logger.info("Memory after LLM load — active: \(memAfter.activeMemory / 1024 / 1024) MB, cache: \(memAfter.cacheMemory / 1024 / 1024) MB")
            }

            llmContainer = container
            modelState = .llmLoaded
            logger.info("State → .llmLoaded")
        } catch {
            logger.error("Failed to load LLM: \(error.localizedDescription)")
            logger.error("Error type: \(type(of: error))")
            logger.error("Full error: \(String(describing: error))")
            modelState = .idle
            throw error
        }
    }

    // MARK: - Model Unloading

    func unloadEmbedding() {
        logger.info("unloadEmbedding() — had model: \(self.embeddingContainer != nil)")
        let hadModel = embeddingContainer != nil
        embeddingContainer = nil
        if hadModel && metalAvailable {
            MLX.Memory.cacheLimit = 0
            MLX.Memory.clearCache()
        }
        modelState = .idle
        logger.info("Embedding unloaded")
    }

    func unloadLLM() {
        logger.info("unloadLLM() — had model: \(self.llmContainer != nil)")
        let hadModel = llmContainer != nil
        llmContainer = nil
        if hadModel && metalAvailable {
            MLX.Memory.cacheLimit = 0
            MLX.Memory.clearCache()
        }
        modelState = .idle
        logger.info("LLM unloaded")
    }

    func unloadAll() {
        logger.info("unloadAll()")
        let hadModels = embeddingContainer != nil || llmContainer != nil
        embeddingContainer = nil
        llmContainer = nil
        if hadModels && metalAvailable {
            MLX.Memory.cacheLimit = 0
            MLX.Memory.clearCache()
        }
        modelState = .idle
        logger.info("All models unloaded. State → .idle")
    }

    // MARK: - Memory Warning

    private func subscribeToMemoryWarnings() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            NSLog("[ModelManager] Memory warning received – unloading all models")
            Task { @MainActor [weak self] in
                self?.unloadAll()
            }
        }
    }

    // MARK: - Public Methods

    func checkDownloadedModels() {
        if embeddingModelDownloaded {
            embeddingDownloadState = .completed
        }
        if llmModelDownloaded {
            llmDownloadState = .completed
        }
    }

    func modelDirectory(for modelId: String) -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("models").appendingPathComponent(modelId)
    }

    // MARK: - Private Helpers

    private func cachedModelURL(for modelId: String) -> URL? {
        guard let repoId = Repo.ID(rawValue: modelId) else {
            logger.error("Invalid repo ID: \(modelId)")
            return nil
        }
        let url = hubClient.resolveCachedSnapshot(
            repo: repoId,
            revision: "main",
            matching: ["config.json"]
        )
        if let url {
            logger.debug("cachedModelURL(\(modelId)) → \(url.path)")
        } else {
            logger.warning("cachedModelURL(\(modelId)) → nil (not found in cache)")
        }
        return url
    }
}
