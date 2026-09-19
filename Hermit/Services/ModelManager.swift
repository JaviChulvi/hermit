import Foundation
import Observation
import HFAPI
import MLXLMHFAPI
import MLX
import MLXVLM
import MLXEmbedders
import MLXLMCommon
import MLXLMTokenizers
import Metal
import UIKit
import os

private let logger = Logger(subsystem: "com.hermit.app", category: "ModelManager")

/// Whether the Metal GPU is available (false on Simulator)
#if targetEnvironment(simulator)
private let metalAvailable = false
#else
private let metalAvailable: Bool = MTLCreateSystemDefaultDevice() != nil
#endif

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
    case busy

    var errorDescription: String? {
        switch self {
        case .insufficientMemory(let available, let required):
            return "Not enough memory: \(available) MB available, \(required) MB required"
        case .modelNotDownloaded(let name):
            return "Model '\(name)' is not downloaded"
        case .busy:
            return "Hermit is busy. Stop the current response or wait for the document import to finish."
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

    private var embeddingContainer: EmbedderModelContainer?
    private var llmContainer: MLXLMCommon.ModelContainer?

    // MARK: - Private

    private let memoryMonitor: MemoryMonitor
    private let hubClient = HubClient()
    private(set) var isBusy = false
    var onUnloadLLM: () -> Void = {}
    private var cancelOperation: (() -> Void)?
    private var unloadRequested = false

    // Keep the conservative phone baseline until bounded caches are measured on device.
    var inferenceCacheBytes = 0
    @ObservationIgnored nonisolated(unsafe) private var memoryWarningObserver: Any?

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
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                embeddingDownloadState = .notStarted
                throw CancellationError()
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
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                llmDownloadState = .notStarted
                throw CancellationError()
            } else {
                llmDownloadState = .error(message: error.localizedDescription)
                throw error
            }
        }
    }

    func cancelDownloads() {
        if case .downloading = embeddingDownloadState {
            embeddingDownloadState = .notStarted
        }
        if case .downloading = llmDownloadState {
            llmDownloadState = .notStarted
        }
    }

    func deleteModels() throws {
        guard !isBusy else { throw ModelManagerError.busy }
        unloadAll()
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

    // MARK: - Exclusive model access

    // Hold ownership across every await, including the entire generation stream.
    // Reject overlapping UI operations instead of building an unbounded work queue.
    func exclusively<T: Sendable>(
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        guard !isBusy else { throw ModelManagerError.busy }
        try Task.checkCancellation()
        isBusy = true
        let task = Task {
            try Task.checkCancellation()
            return try await operation()
        }
        cancelOperation = { task.cancel() }
        defer {
            cancelOperation = nil
            isBusy = false
            if unloadRequested { unloadAll() }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func withEmbeddingModel<T: Sendable>(
        _ operation: @escaping @MainActor (EmbedderModelContainer) async throws -> T
    ) async throws -> T {
        try await exclusively {
            self.releaseModels()
            let directory = try self.requiredDirectory(for: ModelInfo.embeddingModel)
            self.modelState = .transitioning
            defer {
                self.embeddingContainer = nil
                self.clearMemory()
                self.modelState = .idle
            }
            let container = try await EmbedderModelFactory.shared.loadContainer(
                from: directory, using: TokenizersLoader())
            self.embeddingContainer = container
            self.modelState = .embeddingLoaded
            MLX.Memory.cacheLimit = self.inferenceCacheBytes
            try Task.checkCancellation()
            return try await operation(container)
        }
    }

    func withLLM<T: Sendable>(
        _ operation: @escaping @MainActor (MLXLMCommon.ModelContainer) async throws -> T
    ) async throws -> T {
        try await exclusively {
            if self.llmContainer == nil {
                let directory = try self.requiredDirectory(for: ModelInfo.llmModel)
                let requiredMB = 3200
                guard self.memoryMonitor.hasEnoughMemory(requiredMB: requiredMB) else {
                    throw ModelManagerError.insufficientMemory(
                        availableMB: self.availableMemoryMB, requiredMB: requiredMB)
                }
                self.modelState = .transitioning
                MLX.Memory.cacheLimit = self.inferenceCacheBytes
                do {
                    self.llmContainer = try await VLMModelFactory.shared.loadContainer(
                        from: directory, using: TokenizersLoader())
                    self.modelState = .llmLoaded
                } catch {
                    self.clearMemory()
                    self.modelState = .idle
                    throw error
                }
            }
            MLX.Memory.cacheLimit = self.inferenceCacheBytes
            try Task.checkCancellation()
            return try await operation(self.llmContainer!)
        }
    }

    /// Cancel active work first; its completion releases the session and model safely.
    func unloadAll() {
        if isBusy {
            unloadRequested = true
            cancelOperation?()
            return
        }
        releaseModels()
    }

    private func releaseModels() {
        onUnloadLLM()
        embeddingContainer = nil
        llmContainer = nil
        clearMemory()
        modelState = .idle
        unloadRequested = false
    }

    private func clearMemory() {
        if metalAvailable {
            MLX.Memory.cacheLimit = 0
            MLX.Memory.clearCache()
        }
    }

    private func requiredDirectory(for model: ModelInfo) throws -> URL {
        guard metalAvailable else { throw ModelManagerError.metalUnavailable }
        guard let directory = cachedModelURL(for: model.id) else {
            throw ModelManagerError.modelNotDownloaded(model.name)
        }
        return directory
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
