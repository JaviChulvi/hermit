import Foundation
import Observation
import HFAPI
import MLXLMHFAPI

enum ModelState: Equatable {
    case idle
    case embeddingLoaded
    case llmLoaded
    case transitioning
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

    // MARK: - Private

    private let memoryMonitor: MemoryMonitor
    private let hubClient = HubClient()
    private var embeddingDownloadTask: Task<Void, Error>?
    private var llmDownloadTask: Task<Void, Error>?

    private static let modelFilePatterns = ["*.safetensors", "*.json", "*.txt", "*.jinja", "*.model"]

    // MARK: - Init

    init(memoryMonitor: MemoryMonitor = MemoryMonitor()) {
        self.memoryMonitor = memoryMonitor
        checkDownloadedModels()
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
