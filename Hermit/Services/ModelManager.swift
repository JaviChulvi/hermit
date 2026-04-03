import Foundation
import Observation
import HFAPI
import MLXLMHFAPI
import MLX
import MLXLLM
import MLXEmbedders
import MLXLMCommon
import MLXLMTokenizers
import UIKit

enum ModelState: Equatable {
    case idle
    case embeddingLoaded
    case llmLoaded
    case transitioning
}

enum ModelManagerError: LocalizedError {
    case insufficientMemory(availableMB: Int, requiredMB: Int)
    case modelNotDownloaded(String)

    var errorDescription: String? {
        switch self {
        case .insufficientMemory(let available, let required):
            return "Not enough memory: \(available) MB available, \(required) MB required"
        case .modelNotDownloaded(let name):
            return "Model '\(name)' is not downloaded"
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
        checkDownloadedModels()
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
        if modelState == .llmLoaded {
            unloadLLM()
        }

        modelState = .transitioning

        guard let directory = cachedModelURL(for: ModelInfo.embeddingModel.id) else {
            modelState = .idle
            throw ModelManagerError.modelNotDownloaded(ModelInfo.embeddingModel.name)
        }

        MLX.Memory.cacheLimit = 0

        let container = try await MLXEmbedders.loadModelContainer(
            from: directory,
            using: TokenizersLoader()
        )

        embeddingContainer = container
        modelState = .embeddingLoaded
    }

    func loadLLM() async throws {
        if modelState == .embeddingLoaded {
            unloadEmbedding()
        }

        modelState = .transitioning

        let requiredMB = 4000
        if !memoryMonitor.hasEnoughMemory(requiredMB: requiredMB) {
            modelState = .idle
            throw ModelManagerError.insufficientMemory(
                availableMB: memoryMonitor.availableMemoryMB,
                requiredMB: requiredMB
            )
        }

        guard let directory = cachedModelURL(for: ModelInfo.llmModel.id) else {
            modelState = .idle
            throw ModelManagerError.modelNotDownloaded(ModelInfo.llmModel.name)
        }

        MLX.Memory.cacheLimit = 0

        let container = try await LLMModelFactory.shared.loadContainer(
            from: directory,
            using: TokenizersLoader()
        )

        llmContainer = container
        modelState = .llmLoaded
    }

    // MARK: - Model Unloading

    func unloadEmbedding() {
        let hadModel = embeddingContainer != nil
        embeddingContainer = nil
        if hadModel { MLX.Memory.cacheLimit = 0 }
        modelState = .idle
    }

    func unloadLLM() {
        let hadModel = llmContainer != nil
        llmContainer = nil
        if hadModel { MLX.Memory.cacheLimit = 0 }
        modelState = .idle
    }

    func unloadAll() {
        let hadModels = embeddingContainer != nil || llmContainer != nil
        embeddingContainer = nil
        llmContainer = nil
        if hadModels { MLX.Memory.cacheLimit = 0 }
        modelState = .idle
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
        guard let repoId = Repo.ID(rawValue: modelId) else { return nil }
        return hubClient.resolveCachedSnapshot(
            repo: repoId,
            revision: "main",
            matching: ["config.json"]
        )
    }
}
