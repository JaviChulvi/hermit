import Foundation

struct ModelInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let sizeDescription: String
    var isDownloaded: Bool

    static let embeddingModel = ModelInfo(
        id: "mlx-community/all-MiniLM-L6-v2-bf16",
        name: "MiniLM-L6-v2",
        sizeDescription: "~90 MB",
        isDownloaded: false
    )

    static let llmModel = ModelInfo(
        id: "mlx-community/gemma-4-e2b-it-4bit",
        name: "Gemma 4 E2B",
        sizeDescription: "~3.58 GB",
        isDownloaded: false
    )
}
