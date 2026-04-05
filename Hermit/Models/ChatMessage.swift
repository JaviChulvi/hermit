import Foundation

struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let imageData: Data?

    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    init(
        id: UUID = UUID(), role: Role, content: String,
        timestamp: Date = Date(), imageData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.imageData = imageData
    }
}
