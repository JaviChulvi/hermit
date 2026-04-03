import Foundation

struct Document: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var fileExtension: String
    var dateAdded: Date
    var chunkCount: Int
    var isProcessed: Bool

    init(
        id: UUID = UUID(),
        name: String,
        fileExtension: String,
        dateAdded: Date = Date(),
        chunkCount: Int = 0,
        isProcessed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.dateAdded = dateAdded
        self.chunkCount = chunkCount
        self.isProcessed = isProcessed
    }
}
