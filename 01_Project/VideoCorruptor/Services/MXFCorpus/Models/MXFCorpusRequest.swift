import Foundation

struct MXFCorpusRequest: Sendable {
    let sources: [URL]
    let fixtureIDs: Set<String>?
    let outputDirectory: URL
    let masterSeed: UInt64
    let includeSources: Bool
}
