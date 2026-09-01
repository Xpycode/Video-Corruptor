import Foundation

struct MXFNotApplicableFixture: Codable, Equatable, Sendable {
    let fixtureID: String
    let source: MXFRelativePath
    let reason: String
}

struct MXFFailedFixture: Codable, Equatable, Sendable {
    let fixtureID: String
    let source: MXFRelativePath
    let reason: String
}

struct MXFCorpusRunMetadata: Codable, Equatable, Sendable {
    let startedAt: Date
    let completedAt: Date?
}

struct MXFCorpusReport: Codable, Equatable, Sendable {
    let manifest: MXFFixtureManifest
    let notApplicable: [MXFNotApplicableFixture]
    let failures: [MXFFailedFixture]
    let runMetadata: MXFCorpusRunMetadata?
}
