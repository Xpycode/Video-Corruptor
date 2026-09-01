import Foundation

enum MXFGenerationCheckpoint: Equatable, Sendable {
    case beforeSource(URL)
    case beforeInspection(URL)
    case beforeFixture(String)
    case beforeCopy(String)
    case beforeMutation(String)
    case beforeVerification(String)
    case beforePublication
}

typealias MXFGenerationCancellationCheck = @Sendable (MXFGenerationCheckpoint) throws -> Void

enum MXFCorpusGeneratorError: Error, Equatable, Sendable {
    case sourceIsNotRegularFile(URL)
    case sourceExceedsInspectionLimit(size: UInt64, limit: UInt64)
    case sourceChanged(URL)
    case inspectionDidNotComplete(URL)
    case invalidGeneratedTree(String)
}

struct MXFCorpusGenerator: Sendable {
    let registry: MXFFixtureRegistry
    let generatorIdentity: MXFGeneratorIdentity
    let inspectionLimits: MXFInspectionLimits
    let sourceProfile: String
    let sourceRights: MXFSourceRights
    let cancellationCheck: MXFGenerationCancellationCheck

    init(
        registry: MXFFixtureRegistry,
        generatorIdentity: MXFGeneratorIdentity = MXFGeneratorIdentity(
            name: "VideoCorruptor",
            version: "1.0.0"
        ),
        inspectionLimits: MXFInspectionLimits = MXFInspectionLimits(),
        sourceProfile: String = "unknown",
        sourceRights: MXFSourceRights = MXFSourceRights(
            redistributable: false,
            repositoryEligible: false,
            licenseIdentifier: nil
        ),
        cancellationCheck: @escaping MXFGenerationCancellationCheck = { _ in
            try Task.checkCancellation()
        }
    ) {
        self.registry = registry
        self.generatorIdentity = generatorIdentity
        self.inspectionLimits = inspectionLimits
        self.sourceProfile = sourceProfile
        self.sourceRights = sourceRights
        self.cancellationCheck = cancellationCheck
    }

    func generate(_ request: MXFCorpusRequest) async throws -> MXFCorpusReport {
        let atomic = try MXFAtomicOutput(destinationURL: request.outputDirectory)
        var published = false
        defer { if !published { atomic.discard() } }

        let fixtures = try registry.selected(ids: request.fixtureIDs)
        let fileManager = FileManager.default
        let fixturesDirectory = atomic.stagingURL.appendingPathComponent("fixtures", isDirectory: true)
        try fileManager.createDirectory(at: fixturesDirectory, withIntermediateDirectories: false)
        if request.includeSources {
            try fileManager.createDirectory(
                at: atomic.stagingURL.appendingPathComponent("sources", isDirectory: true),
                withIntermediateDirectories: false
            )
        }

        var entries: [MXFFixtureManifestEntry] = []
        var notApplicable: [MXFNotApplicableFixture] = []
        var generatedFixtureIDs = Set<String>()

        // Deliberately serial: fixture ordering and I/O pressure remain deterministic.
        for sourceURL in request.sources.sorted(by: { $0.path < $1.path }) {
            try cancellationCheck(.beforeSource(sourceURL))
            let source = sourceURL.standardizedFileURL
            let attributes = try fileManager.attributesOfItem(atPath: source.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let number = attributes[.size] as? NSNumber else {
                throw MXFCorpusGeneratorError.sourceIsNotRegularFile(source)
            }
            let sourceSize = number.uint64Value
            guard sourceSize <= inspectionLimits.maximumInputBytes else {
                throw MXFCorpusGeneratorError.sourceExceedsInspectionLimit(
                    size: sourceSize,
                    limit: inspectionLimits.maximumInputBytes
                )
            }
            let sourceHash = try SHA256Hasher.hash(fileAt: source) { try cancellationCheck(.beforeSource(source)) }
            let sourceToken = String(sourceHash.prefix(16))
            let sourceRelative = try MXFRelativePath("sources/\(sourceToken)-\(safeName(source.lastPathComponent))")
            let sourceIdentity = try MXFSourceIdentity(
                file: sourceRelative,
                sha256: sourceHash,
                size: sourceSize,
                profile: sourceProfile,
                rights: sourceRights
            )

            if request.includeSources {
                let includedSource = atomic.stagingURL.appendingPathComponent(sourceRelative.value)
                _ = try StreamingFileIO.copy(from: source, to: includedSource) {
                    try cancellationCheck(.beforeCopy(sourceRelative.value))
                }
            }

            try cancellationCheck(.beforeInspection(source))
            let inspected = try MXFStructuralInspector().inspect(
                fileAt: source,
                limits: inspectionLimits,
                shouldCancel: { _ in Task.isCancelled }
            )
            guard inspected.completedWalk else {
                throw MXFCorpusGeneratorError.inspectionDidNotComplete(source)
            }

            for fixture in fixtures {
                let definition = fixture.definition
                guard !generatedFixtureIDs.contains(definition.id) else { continue }
                try cancellationCheck(.beforeFixture(definition.id))
                switch fixture.evaluate(source: inspected) {
                case .notApplicable(let reason):
                    notApplicable.append(MXFNotApplicableFixture(
                        fixtureID: definition.id,
                        source: sourceRelative,
                        reason: reason
                    ))
                case .applicable(let targetOffset, let targetClassification):
                    notApplicable.removeAll { $0.fixtureID == definition.id }
                    let outputRelative = try MXFRelativePath(
                        "fixtures/\(safeName(definition.id))-\(sourceToken).mxf"
                    )
                    let outputURL = atomic.stagingURL.appendingPathComponent(outputRelative.value)
                    try cancellationCheck(.beforeCopy(definition.id))
                    _ = try StreamingFileIO.copy(from: source, to: outputURL) {
                        try cancellationCheck(.beforeCopy(definition.id))
                    }

                    let fixtureSeed = SeedDerivation.derive(master: request.masterSeed, key: definition.id)
                    var rng = SeededRNG(seed: fixtureSeed)
                    try cancellationCheck(.beforeMutation(definition.id))
                    let mutation = try fixture.apply(to: outputURL, source: inspected, rng: &rng)
                    guard mutation.targetOffset.value == targetOffset,
                          mutation.targetClassification == targetClassification else {
                        throw MXFCorpusGeneratorError.invalidGeneratedTree(
                            "Fixture \(definition.id) changed its evaluated target"
                        )
                    }

                    try cancellationCheck(.beforeVerification(definition.id))
                    try MXFCorpusVerifier().verify(
                        sourceURL: source,
                        outputURL: outputURL,
                        edits: mutation.edits,
                        truncation: mutation.truncation,
                        postconditions: fixture.postconditions(for: inspected)
                    )
                    let outputHash = try SHA256Hasher.hash(fileAt: outputURL)
                    let outputSize = try fileSize(at: outputURL)
                    let outputIdentity = try MXFOutputIdentity(
                        file: outputRelative,
                        sha256: outputHash,
                        size: outputSize,
                        publicationEligible: sourceRights.permitsPublication,
                        sourceRights: sourceRights
                    )
                    entries.append(try MXFFixtureManifestEntry(
                        id: definition.id,
                        corpusClass: definition.corpusClass,
                        lifecycle: definition.lifecycle,
                        mutationSchemaVersion: definition.mutationSchemaVersion,
                        source: sourceIdentity,
                        output: outputIdentity,
                        seed: MXFDecimalUInt64(fixtureSeed),
                        mutation: mutation,
                        expected: definition.defaultExpectedResult,
                        limits: definition.recommendedLimits
                    ))
                    generatedFixtureIDs.insert(definition.id)
                }
            }

            guard try SHA256Hasher.hash(fileAt: source) == sourceHash,
                  try fileSize(at: source) == sourceSize else {
                throw MXFCorpusGeneratorError.sourceChanged(source)
            }
        }

        // Source iteration determines applicability, but the schema's canonical ordering is by
        // stable fixture ID and must not depend on which synthetic/real source satisfied it.
        entries.sort { $0.id < $1.id }
        let manifest = MXFFixtureManifest(generator: generatorIdentity, fixtures: entries)
        let manifestData = try MXFManifestEncoder().encode(manifest)
        try manifestData.write(
            to: atomic.stagingURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try validateTree(manifest, root: atomic.stagingURL, includeSources: request.includeSources)
        try cancellationCheck(.beforePublication)
        try atomic.publish()
        published = true
        return MXFCorpusReport(
            manifest: manifest,
            notApplicable: notApplicable,
            failures: [],
            runMetadata: nil
        )
    }

    private func validateTree(
        _ manifest: MXFFixtureManifest,
        root: URL,
        includeSources: Bool
    ) throws {
        try MXFManifestValidator().validate(manifest, corpusRoot: root)
        for fixture in manifest.fixtures {
            let output = root.appendingPathComponent(fixture.output.file.value)
            guard try fileSize(at: output) == fixture.output.size.value,
                  try SHA256Hasher.hash(fileAt: output) == fixture.output.sha256 else {
                throw MXFCorpusGeneratorError.invalidGeneratedTree(fixture.output.file.value)
            }
            if includeSources {
                let source = root.appendingPathComponent(fixture.source.file.value)
                guard try fileSize(at: source) == fixture.source.size.value,
                      try SHA256Hasher.hash(fileAt: source) == fixture.source.sha256 else {
                    throw MXFCorpusGeneratorError.invalidGeneratedTree(fixture.source.file.value)
                }
            }
        }
    }

    private func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let number = attributes[.size] as? NSNumber else {
            throw MXFCorpusGeneratorError.sourceIsNotRegularFile(url)
        }
        return number.uint64Value
    }

    private func safeName(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            let allowed = CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_"
            return allowed ? Character(String(scalar)) : "_"
        }
        let result = String(scalars)
        return result.isEmpty ? "file" : result
    }
}
