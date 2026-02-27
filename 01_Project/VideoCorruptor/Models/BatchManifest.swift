import Foundation

/// JSON manifest for batch output, consumable by VideoAnalyzer/VCR.
struct BatchManifest: Codable, Sendable {
    let generatedAt: Date
    let masterSeed: String
    let entries: [ManifestEntry]

    struct ManifestEntry: Codable, Sendable {
        let sourceFile: String
        let corruptionType: String
        let outputFile: String
        let status: String
        let severity: Double?
        let seed: String?
        let stackedTypes: [String]?
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}
