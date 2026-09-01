import Foundation

enum MXFManifestValidationError: Error, Equatable, Sendable {
    case duplicateFixtureID(String)
    case duplicateOutputPath(String)
    case missingMutation(fixtureID: String)
    case overlappingEdits(fixtureID: String, firstOffset: UInt64, secondOffset: UInt64)
    case editLengthMismatch(fixtureID: String, offset: UInt64)
    case missingExpectedResult(fixtureID: String)
    case missingConsumerCode(fixtureID: String)
    case invalidLifecycle(fixtureID: String, reason: String)
    case pathEscapesCorpusRoot(String)
}

struct MXFManifestValidator: Sendable {
    func validate(_ manifest: MXFFixtureManifest, corpusRoot: URL? = nil) throws {
        var fixtureIDs = Set<String>()
        var outputPaths = Set<String>()

        for fixture in manifest.fixtures {
            guard fixtureIDs.insert(fixture.id).inserted else {
                throw MXFManifestValidationError.duplicateFixtureID(fixture.id)
            }
            guard outputPaths.insert(fixture.output.file.value).inserted else {
                throw MXFManifestValidationError.duplicateOutputPath(fixture.output.file.value)
            }
            try validateFixture(fixture)

            if let corpusRoot {
                try validatePath(fixture.source.file, beneath: corpusRoot)
                try validatePath(fixture.output.file, beneath: corpusRoot)
            }
        }
    }

    private func validateFixture(_ fixture: MXFFixtureManifestEntry) throws {
        let edits = fixture.mutation.edits.sorted { $0.offset.value < $1.offset.value }
        guard !edits.isEmpty || fixture.mutation.truncation != nil else {
            throw MXFManifestValidationError.missingMutation(fixtureID: fixture.id)
        }

        var previousEnd: UInt64?
        var previousOffset: UInt64?
        for edit in edits {
            let originalLength = UInt64(edit.originalHex.value.utf8.count / 2)
            let replacementLength = UInt64(edit.replacementHex.value.utf8.count / 2)
            guard originalLength == replacementLength else {
                throw MXFManifestValidationError.editLengthMismatch(
                    fixtureID: fixture.id,
                    offset: edit.offset.value
                )
            }
            let end = try CheckedBinaryArithmetic.add(edit.offset.value, originalLength)
            if let previousEnd, let previousOffset, edit.offset.value < previousEnd {
                throw MXFManifestValidationError.overlappingEdits(
                    fixtureID: fixture.id,
                    firstOffset: previousOffset,
                    secondOffset: edit.offset.value
                )
            }
            previousEnd = end
            previousOffset = edit.offset.value
        }

        guard !fixture.expected.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MXFManifestValidationError.missingExpectedResult(fixtureID: fixture.id)
        }
        guard fixture.mutationSchemaVersion > 0 else {
            throw MXFManifestValidationError.invalidLifecycle(
                fixtureID: fixture.id,
                reason: "mutation schema version must be positive"
            )
        }
        if fixture.lifecycle == .approved {
            guard let consumerCode = fixture.expected.consumerCode,
                  !consumerCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MXFManifestValidationError.missingConsumerCode(fixtureID: fixture.id)
            }
        }
    }

    private func validatePath(_ path: MXFRelativePath, beneath root: URL) throws {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"

        var resolvedCandidate = resolvedRoot
        for component in path.value.split(separator: "/") {
            resolvedCandidate = resolvedCandidate
                .appendingPathComponent(String(component))
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard resolvedCandidate.path.hasPrefix(rootPath) else {
                throw MXFManifestValidationError.pathEscapesCorpusRoot(path.value)
            }
        }
    }
}
