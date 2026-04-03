import Foundation
import PDFKit

enum DocumentProcessorError: LocalizedError {
    case unsupportedFileType(String)
    case emptyDocument
    case noExtractableText
    case readError(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: .\(ext). Only .txt and .pdf files are supported."
        case .emptyDocument:
            return "The document is empty."
        case .noExtractableText:
            return "This PDF does not contain extractable text. It may be a scanned or image-only PDF."
        case .readError(let message):
            return "Failed to read document: \(message)"
        }
    }
}

struct DocumentProcessor {

    static func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "txt":
            return try extractTextFromTXT(url: url)
        case "pdf":
            return try extractTextFromPDF(url: url)
        default:
            throw DocumentProcessorError.unsupportedFileType(ext)
        }
    }

    // MARK: - Private

    private static func extractTextFromTXT(url: URL) throws -> String {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw DocumentProcessorError.readError(error.localizedDescription)
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentProcessorError.emptyDocument
        }

        return text
    }

    private static func extractTextFromPDF(url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentProcessorError.readError("Could not open PDF file.")
        }

        guard document.pageCount > 0 else {
            throw DocumentProcessorError.emptyDocument
        }

        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                if !fullText.isEmpty {
                    fullText += "\n"
                }
                fullText += pageText
            }
        }

        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentProcessorError.noExtractableText
        }

        return fullText
    }
}
