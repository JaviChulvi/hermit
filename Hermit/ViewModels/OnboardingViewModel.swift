import Foundation
import Observation

enum OnboardingStep {
    case welcome
    case downloading
    case ready
}

@Observable
@MainActor
final class OnboardingViewModel {
    var currentStep: OnboardingStep = .welcome

    private let modelManager: ModelManager
    private var downloadTask: Task<Void, Never>?

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
        if modelManager.embeddingModelDownloaded && modelManager.llmModelDownloaded {
            currentStep = .ready
        }
    }

    var embeddingDownloadState: DownloadState {
        modelManager.embeddingDownloadState
    }

    var llmDownloadState: DownloadState {
        modelManager.llmDownloadState
    }

    var bothDownloaded: Bool {
        embeddingDownloadState == .completed && llmDownloadState == .completed
    }

    var isDownloading: Bool {
        if case .downloading = embeddingDownloadState { return true }
        if case .downloading = llmDownloadState { return true }
        return false
    }

    var hasError: Bool {
        if case .error = embeddingDownloadState { return true }
        if case .error = llmDownloadState { return true }
        return false
    }

    func startDownloads() {
        currentStep = .downloading
        downloadTask = Task {
            do {
                try await modelManager.downloadEmbeddingModel()
            } catch {
                return
            }

            do {
                try await modelManager.downloadLLMModel()
            } catch {
                return
            }

            currentStep = .ready
        }
    }

    func retryDownloads() {
        startDownloads()
    }

    func cancelDownloads() {
        downloadTask?.cancel()
        downloadTask = nil
        modelManager.cancelDownloads()
        currentStep = .welcome
    }

    func skipToMain() {
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }
}
