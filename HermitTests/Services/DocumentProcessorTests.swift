import Testing
import Foundation
@testable import Hermit

struct DocumentProcessorTests {

    private func fixtureURL(named name: String, ext: String) -> URL {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            fatalError("Missing test fixture: \(name).\(ext)")
        }
        return url
    }

    @Test func extractTextFromTXTFile() throws {
        let url = fixtureURL(named: "sample", ext: "txt")
        let text = try DocumentProcessor.extractText(from: url)

        #expect(!text.isEmpty)
        #expect(text.contains("The History of Artificial Intelligence"))
    }

    @Test func extractTextFromPDFFile() throws {
        let url = fixtureURL(named: "sample", ext: "pdf")
        let text = try DocumentProcessor.extractText(from: url)

        #expect(!text.isEmpty)
        #expect(text.contains("On-Device Machine Learning"))
    }

    @Test func throwsErrorForUnsupportedFileType() {
        let url = URL(fileURLWithPath: "/tmp/image.png")

        #expect(throws: DocumentProcessorError.self) {
            try DocumentProcessor.extractText(from: url)
        }
    }

    @Test func extractedTXTContentMatchesExpected() throws {
        let url = fixtureURL(named: "sample", ext: "txt")
        let text = try DocumentProcessor.extractText(from: url)

        #expect(text.hasPrefix("The History of Artificial Intelligence"))
    }
}

// Helper class to locate the test bundle
private class BundleToken {}
