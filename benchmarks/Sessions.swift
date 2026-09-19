// Compile the actual LLMService/ChatMessage with this native model-owner adapter.
// This does not test the iOS ModelManager or memory-warning lifecycle.
import CoreImage
import Foundation
import MLXLMCommon
import MLXLMTokenizers
import MLXRandom
import MLXVLM

@MainActor final class ModelManager {
    let container: ModelContainer
    var onUnloadLLM: () -> Void = {}
    init(_ container: ModelContainer) { self.container = container }
    func withLLM<T: Sendable>(
        _ operation: @escaping @MainActor (ModelContainer) async throws -> T
    ) async throws -> T { try await operation(container) }
}

@MainActor func state(_ service: LLMService) -> (session: ObjectIdentifier?, tokens: Int) {
    let mirror = Mirror(reflecting: service)
    let session = (mirror.descendant("session") as? ChatSession).map(ObjectIdentifier.init)
    return (session, mirror.descendant("sessionTokens") as! Int)
}

@MainActor func sessionChecks(directory: URL, output: String, imagePath: String) async throws {
    let container = try await VLMModelFactory.shared.loadContainer(from: directory, using: TokenizersLoader())
    let manager = ModelManager(container)
    let service = LLMService(modelManager: manager)
    MLXRandom.seed(20260919)
    var rows: [[String: Any]] = []
    let first = ChatMessage(role: .user, content: "Remember the code cobalt7. Reply only OK.")
    let answer = try await service.respond(to: first, history: [], onUpdate: { _ in })
    let initial = state(service)
    let second = ChatMessage(role: .user, content: "What code did I give you? Reply with only the code.")
    let followup = try await service.respond(to: second, history: [first, answer], onUpdate: { _ in })
    let reused = state(service)
    guard initial.session == reused.session, reused.tokens > initial.tokens else {
        throw NSError(domain: "Session reuse failed", code: 1)
    }
    rows.append(["check": "cached follow-up", "passed": true, "output": followup.content,
        "initialTokens": initial.tokens, "totalTokens": reused.tokens])
    let changed = try await service.respond(
        to: ChatMessage(role: .user, content: "According to the updated manual, what is the code? Reply only the code."),
        history: [first, answer, second, followup], ragContext: "Updated manual: the current code is amber9.", onUpdate: { _ in })
    guard state(service).session != reused.session else { throw NSError(domain: "Prefix reset failed", code: 2) }
    rows.append(["check": "changed context resets cache", "passed": true, "output": changed.content])
    do {
        _ = try await service.respond(to: ChatMessage(role: .user, content: String(repeating: "word ", count: 5000)),
            history: [], onUpdate: { _ in })
        throw NSError(domain: "Oversized input was accepted", code: 3)
    } catch LLMServiceError.inputTooLong {
        rows.append(["check": "oversized current question rejected", "passed": true])
    }
    let longHistory = [ChatMessage(role: .user, content: String(repeating: "word ", count: 5000)),
        ChatMessage(role: .assistant, content: "OK")]
    let trimmed = try await service.respond(to: ChatMessage(role: .user, content: "Reply only OK."),
        history: longHistory, onUpdate: { _ in })
    guard state(service).tokens <= LLMService.contextTokens else { throw NSError(domain: "Budget exceeded", code: 4) }
    rows.append(["check": "old turns trimmed to budget", "passed": true, "output": trimmed.content,
        "totalTokens": state(service).tokens])
    manager.onUnloadLLM()
    guard state(service).session == nil, state(service).tokens == 0 else {
        throw NSError(domain: "Unload callback failed", code: 5)
    }
    rows.append(["check": "unload callback releases session", "passed": true])
    let photo = try Data(contentsOf: URL(fileURLWithPath: imagePath))
    let imageMessage = ChatMessage(role: .user, content: "How many cats are in this image? Reply only the number.", imageData: photo)
    let imageAnswer = try await service.respond(to: imageMessage, history: [], onUpdate: { _ in })
    let imageState = state(service)
    let imageFollowup = try await service.respond(to: ChatMessage(role: .user,
        content: "How many cats did you just see? Reply only the number."),
        history: [imageMessage, imageAnswer], onUpdate: { _ in })
    guard imageState.session == state(service).session, state(service).tokens <= LLMService.contextTokens else {
        throw NSError(domain: "Image session reuse failed", code: 6)
    }
    rows.append(["check": "photo and cached photo follow-up", "passed": true,
        "output": imageAnswer.content, "followup": imageFollowup.content,
        "imageTurnTokens": imageState.tokens, "totalTokens": state(service).tokens])
    do {
        _ = try await service.respond(to: ChatMessage(role: .user,
            content: String(repeating: "word ", count: 2900), imageData: photo), history: [], onUpdate: { _ in })
        throw NSError(domain: "Oversized combined image input was accepted", code: 7)
    } catch LLMServiceError.inputTooLong {
        rows.append(["check": "combined image and text budget enforced", "passed": true])
    }
    try write(rows, to: output)
}

struct AnswerCase: Decodable { let id: String; let arm: String; let language: String; let question: String; let context: String }

@MainActor func answers(directory: URL, cases: String, output: String) async throws {
    let cases = try JSONDecoder().decode([AnswerCase].self, from: Data(contentsOf: URL(fileURLWithPath: cases)))
    let container = try await VLMModelFactory.shared.loadContainer(from: directory, using: TokenizersLoader())
    let service = LLMService(modelManager: ModelManager(container))
    var rows: [[String: Any]] = []
    for item in cases {
        service.resetSession()
        MLXRandom.seed(20260919)
        let instruction = item.language == "es"
            ? "\nResponde solo con una frase breve, sin explicaciones."
            : "\nAnswer with the shortest possible phrase, without explanation."
        let response = try await service.respond(to: ChatMessage(role: .user,
            content: item.question + instruction),
            history: [], ragContext: item.context, onUpdate: { _ in })
        rows.append(["id": item.id, "arm": item.arm, "language": item.language,
            "output": response.content, "sessionTokens": state(service).tokens])
        try write(rows, to: output)
        print("answer \(rows.count)/\(cases.count) \(item.arm) \(item.id)")
    }
}
