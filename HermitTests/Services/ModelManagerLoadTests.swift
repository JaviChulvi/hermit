import Testing
import Foundation
@testable import Hermit

@MainActor
struct ModelManagerLoadTests {
    @Test func overlappingWorkIsRejectedAndOwnerIsPreserved() async throws {
        let manager = ModelManager()
        try await manager.exclusively {
            #expect(manager.isBusy)
            do {
                _ = try await manager.exclusively { Issue.record("Overlapping operation started") }
                Issue.record("Expected busy error")
            } catch ModelManagerError.busy {
                #expect(manager.isBusy)
            }
        }
        #expect(!manager.isBusy)
    }

    @Test func memoryWarningCancelsBeforeReleasingModels() async {
        let manager = ModelManager()
        var released = false
        manager.onUnloadLLM = { released = true }
        do {
            try await manager.exclusively {
                manager.unloadAll()
                #expect(!released)
                #expect(manager.isBusy)
                try Task.checkCancellation()
            }
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(released)
            #expect(!manager.isBusy)
            #expect(manager.modelState == .idle)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func failedLoadReleasesOwnership() async throws {
        let manager = ModelManager()
        guard !manager.embeddingModelDownloaded else { return }
        do {
            _ = try await manager.withEmbeddingModel { _ in Issue.record("Expected unavailable model") }
        } catch let error as ModelManagerError {
            switch error {
            case .metalUnavailable, .modelNotDownloaded: break
            default: Issue.record("Unexpected error: \(error)")
            }
        }
        #expect(!manager.isBusy)
        #expect(manager.modelState == .idle)
    }
}
