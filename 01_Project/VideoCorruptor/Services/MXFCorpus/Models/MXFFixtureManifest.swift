import Foundation

struct MXFGeneratorIdentity: Codable, Equatable, Sendable {
    let name: String
    let version: String
}

struct MXFSourceRights: Codable, Equatable, Sendable {
    let redistributable: Bool
    let repositoryEligible: Bool
    let licenseIdentifier: String?

    var permitsPublication: Bool {
        redistributable && repositoryEligible
    }
}

struct MXFSourceIdentity: Codable, Equatable, Sendable {
    let file: MXFRelativePath
    let sha256: String
    let size: MXFDecimalUInt64
    let profile: String
    let rights: MXFSourceRights

    init(
        file: MXFRelativePath,
        sha256: String,
        size: UInt64,
        profile: String,
        rights: MXFSourceRights
    ) throws {
        guard Self.isSHA256(sha256) else { throw MXFModelError.invalidSHA256(sha256) }
        self.file = file
        self.sha256 = sha256
        self.size = MXFDecimalUInt64(size)
        self.profile = profile
        self.rights = rights
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            file: container.decode(MXFRelativePath.self, forKey: .file),
            sha256: container.decode(String.self, forKey: .sha256),
            size: container.decode(MXFDecimalUInt64.self, forKey: .size).value,
            profile: container.decode(String.self, forKey: .profile),
            rights: container.decode(MXFSourceRights.self, forKey: .rights)
        )
    }

    fileprivate static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            ($0 >= "0" && $0 <= "9") || ("a"..."f").contains($0)
        }
    }
}

struct MXFOutputIdentity: Codable, Equatable, Sendable {
    let file: MXFRelativePath
    let sha256: String
    let size: MXFDecimalUInt64
    let publicationEligible: Bool

    init(
        file: MXFRelativePath,
        sha256: String,
        size: UInt64,
        publicationEligible: Bool,
        sourceRights: MXFSourceRights
    ) throws {
        guard MXFSourceIdentity.isSHA256(sha256) else {
            throw MXFModelError.invalidSHA256(sha256)
        }
        guard !publicationEligible || sourceRights.permitsPublication else {
            throw MXFModelError.publicationEligibilityExceedsSourceRights
        }
        self.file = file
        self.sha256 = sha256
        self.size = MXFDecimalUInt64(size)
        self.publicationEligible = publicationEligible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sha256 = try container.decode(String.self, forKey: .sha256)
        guard MXFSourceIdentity.isSHA256(sha256) else {
            throw MXFModelError.invalidSHA256(sha256)
        }
        file = try container.decode(MXFRelativePath.self, forKey: .file)
        self.sha256 = sha256
        size = try container.decode(MXFDecimalUInt64.self, forKey: .size)
        publicationEligible = try container.decode(Bool.self, forKey: .publicationEligible)
    }
}

struct MXFFixtureManifestEntry: Codable, Equatable, Sendable {
    let id: String
    let corpusClass: MXFCorpusClass
    let lifecycle: MXFFixtureLifecycle
    let mutationSchemaVersion: Int
    let source: MXFSourceIdentity
    let output: MXFOutputIdentity
    let seed: MXFDecimalUInt64?
    let mutation: MXFMutationRecord
    let expected: MXFExpectedResult
    let limits: MXFReaderLimits

    enum CodingKeys: String, CodingKey {
        case id, lifecycle, mutationSchemaVersion, source, output, seed, mutation, expected, limits
        case corpusClass = "class"
    }

    init(
        id: String,
        corpusClass: MXFCorpusClass,
        lifecycle: MXFFixtureLifecycle,
        mutationSchemaVersion: Int,
        source: MXFSourceIdentity,
        output: MXFOutputIdentity,
        seed: MXFDecimalUInt64?,
        mutation: MXFMutationRecord,
        expected: MXFExpectedResult,
        limits: MXFReaderLimits
    ) throws {
        guard !output.publicationEligible || source.rights.permitsPublication else {
            throw MXFModelError.publicationEligibilityExceedsSourceRights
        }
        self.id = id
        self.corpusClass = corpusClass
        self.lifecycle = lifecycle
        self.mutationSchemaVersion = mutationSchemaVersion
        self.source = source
        self.output = output
        self.seed = seed
        self.mutation = mutation
        self.expected = expected
        self.limits = limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            corpusClass: container.decode(MXFCorpusClass.self, forKey: .corpusClass),
            lifecycle: container.decode(MXFFixtureLifecycle.self, forKey: .lifecycle),
            mutationSchemaVersion: container.decode(Int.self, forKey: .mutationSchemaVersion),
            source: container.decode(MXFSourceIdentity.self, forKey: .source),
            output: container.decode(MXFOutputIdentity.self, forKey: .output),
            seed: container.decodeIfPresent(MXFDecimalUInt64.self, forKey: .seed),
            mutation: container.decode(MXFMutationRecord.self, forKey: .mutation),
            expected: container.decode(MXFExpectedResult.self, forKey: .expected),
            limits: container.decode(MXFReaderLimits.self, forKey: .limits)
        )
    }
}

struct MXFFixtureManifest: Codable, Equatable, Sendable {
    static let schemaIdentifier = "com.playplayplay.mxf-adversarial-corpus"
    static let schemaVersion = 1

    let schemaIdentifier: String
    let schemaVersion: Int
    let generator: MXFGeneratorIdentity
    let fixtures: [MXFFixtureManifestEntry]

    init(generator: MXFGeneratorIdentity, fixtures: [MXFFixtureManifestEntry]) {
        schemaIdentifier = Self.schemaIdentifier
        schemaVersion = Self.schemaVersion
        self.generator = generator
        self.fixtures = fixtures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(String.self, forKey: .schemaIdentifier)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard identifier == Self.schemaIdentifier, version == Self.schemaVersion else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported MXF corpus schema")
            )
        }
        schemaIdentifier = identifier
        schemaVersion = version
        generator = try container.decode(MXFGeneratorIdentity.self, forKey: .generator)
        fixtures = try container.decode([MXFFixtureManifestEntry].self, forKey: .fixtures)
    }
}
