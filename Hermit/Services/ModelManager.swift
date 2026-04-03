import Foundation
import Observation

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
        modelDirectoryContainsConfig(for: ModelInfo.embeddingModel.id, subdirectory: "embeddings")
    }

    var llmModelDownloaded: Bool {
        modelDirectoryContainsConfig(for: ModelInfo.llmModel.id, subdirectory: "llm")
    }

    // MARK: - Private

    private let memoryMonitor: MemoryMonitor

    // MARK: - Init

    init(memoryMonitor: MemoryMonitor = MemoryMonitor()) {
        self.memoryMonitor = memoryMonitor
        checkDownloadedModels()
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

    private func modelDirectoryContainsConfig(for modelId: String, subdirectory: String) -> Bool {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let configURL = documentsURL
            .appendingPathComponent("models")
            .appendingPathComponent(subdirectory)
            .appendingPathComponent(modelId.replacingOccurrences(of: "/", with: "_"))
            .appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configURL.path)
    }
}
