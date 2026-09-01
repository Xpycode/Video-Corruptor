import Foundation
import XCTest
@testable import VideoCorruptor

final class ManifestGoldenTests: XCTestCase {
    private let encoder = MXFManifestEncoder()
    private let validator = MXFManifestValidator()

    func testCanonicalManifestMatchesCheckedGoldenBytes() throws {
        let manifest = MXFFixtureManifest(
            generator: MXFGeneratorIdentity(name: "VideoCorruptor", version: "1.0.0"),
            fixtures: []
        )
        let goldenURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "manifest-v1.golden", withExtension: "json")
        )
        XCTAssertEqual(try encoder.encode(manifest), try Data(contentsOf: goldenURL))
    }

    func testEncoderSortsFixturesAndEdits() throws {
        let later = try makeEntry(
            id: "mxf.z.v1",
            outputPath: "fixtures/z.mxf",
            edits: [try makeEdit(offset: 20), try makeEdit(offset: 10)]
        )
        let earlier = try makeEntry(
            id: "mxf.a.v1",
            outputPath: "fixtures/a.mxf",
            edits: [try makeEdit(offset: 4), try makeEdit(offset: 2)]
        )
        let manifest = MXFFixtureManifest(
            generator: MXFGeneratorIdentity(name: "VideoCorruptor", version: "1"),
            fixtures: [later, earlier]
        )

        let decoded = try JSONDecoder().decode(
            MXFFixtureManifest.self,
            from: encoder.encode(manifest)
        )
        XCTAssertEqual(decoded.fixtures.map(\.id), ["mxf.a.v1", "mxf.z.v1"])
        XCTAssertEqual(
            decoded.fixtures[0].mutation.edits.map(\.offset.value),
            [2, 4]
        )
        XCTAssertEqual(
            decoded.fixtures[1].mutation.edits.map(\.offset.value),
            [10, 20]
        )
    }

    func testValidatorRejectsDuplicateFixtureIDsAndOutputs() throws {
        let entry = try makeEntry(id: "mxf.a.v1", outputPath: "fixtures/a.mxf")
        XCTAssertThrowsError(
            try validator.validate(makeManifest([entry, entry]))
        ) { error in
            XCTAssertEqual(error as? MXFManifestValidationError, .duplicateFixtureID("mxf.a.v1"))
        }

        let other = try makeEntry(id: "mxf.b.v1", outputPath: "fixtures/a.mxf")
        XCTAssertThrowsError(
            try validator.validate(makeManifest([entry, other]))
        ) { error in
            XCTAssertEqual(
                error as? MXFManifestValidationError,
                .duplicateOutputPath("fixtures/a.mxf")
            )
        }
    }

    func testValidatorRejectsEmptyMutationButAllowsTruncationOnly() throws {
        let empty = try makeEntry(id: "mxf.empty.v1", outputPath: "fixtures/empty.mxf", edits: [])
        XCTAssertThrowsError(try validator.validate(makeManifest([empty]))) { error in
            XCTAssertEqual(
                error as? MXFManifestValidationError,
                .missingMutation(fixtureID: "mxf.empty.v1")
            )
        }

        let truncation = try MXFTruncationRecord(
            originalSize: 100,
            retainedSize: 50,
            containingElement: "RIP",
            boundary: "inside RIP"
        )
        let truncationOnly = try makeEntry(
            id: "mxf.truncate.v1",
            outputPath: "fixtures/truncate.mxf",
            edits: [],
            truncation: truncation
        )
        XCTAssertNoThrow(try validator.validate(makeManifest([truncationOnly])))
    }

    func testValidatorRejectsOverlappingAndLengthMismatchedEdits() throws {
        let overlapping = try makeEntry(
            id: "mxf.overlap.v1",
            outputPath: "fixtures/overlap.mxf",
            edits: [try makeEdit(offset: 10, hex: "0000"), try makeEdit(offset: 11)]
        )
        XCTAssertThrowsError(try validator.validate(makeManifest([overlapping]))) { error in
            XCTAssertEqual(
                error as? MXFManifestValidationError,
                .overlappingEdits(fixtureID: "mxf.overlap.v1", firstOffset: 10, secondOffset: 11)
            )
        }

        let mismatch = MXFByteEdit(
            offset: MXFDecimalUInt64(0),
            originalHex: try MXFLowercaseHex("00"),
            replacementHex: try MXFLowercaseHex("0000"),
            field: nil
        )
        let mismatched = try makeEntry(
            id: "mxf.mismatch.v1",
            outputPath: "fixtures/mismatch.mxf",
            edits: [mismatch]
        )
        XCTAssertThrowsError(try validator.validate(makeManifest([mismatched]))) { error in
            XCTAssertEqual(
                error as? MXFManifestValidationError,
                .editLengthMismatch(fixtureID: "mxf.mismatch.v1", offset: 0)
            )
        }
    }

    func testValidatorRejectsMissingExpectedResultAndApprovedConsumerCode() throws {
        let missingExpected = try makeEntry(
            id: "mxf.expected.v1",
            outputPath: "fixtures/expected.mxf",
            category: "   "
        )
        XCTAssertThrowsError(try validator.validate(makeManifest([missingExpected]))) { error in
            XCTAssertEqual(
                error as? MXFManifestValidationError,
                .missingExpectedResult(fixtureID: "mxf.expected.v1")
            )
        }

        let approved = try makeEntry(
            id: "mxf.approved.v1",
            outputPath: "fixtures/approved.mxf",
            lifecycle: .approved,
            consumerCode: nil
        )
        XCTAssertThrowsError(try validator.validate(makeManifest([approved]))) { error in
            XCTAssertEqual(
                error as? MXFManifestValidationError,
                .missingConsumerCode(fixtureID: "mxf.approved.v1")
            )
        }
    }

    func testAbsoluteAndTraversalPathsFailDuringSafeDecode() throws {
        for path in ["/tmp/output.mxf", "fixtures/../output.mxf"] {
            let json = "\"\(path)\""
            XCTAssertThrowsError(
                try JSONDecoder().decode(MXFRelativePath.self, from: Data(json.utf8))
            )
        }
    }

    func testValidatorRejectsSymlinkEscape() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("ManifestGoldenTests-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("corpus", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("fixtures"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("sources"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("fixtures/escape"),
            withDestinationURL: outside
        )

        let entry = try makeEntry(
            id: "mxf.escape.v1",
            outputPath: "fixtures/escape/output.mxf"
        )
        XCTAssertThrowsError(try validator.validate(makeManifest([entry]), corpusRoot: root)) { error in
            XCTAssertEqual(
                error as? MXFManifestValidationError,
                .pathEscapesCorpusRoot("fixtures/escape/output.mxf")
            )
        }
    }

    private func makeManifest(_ fixtures: [MXFFixtureManifestEntry]) -> MXFFixtureManifest {
        MXFFixtureManifest(
            generator: MXFGeneratorIdentity(name: "VideoCorruptor", version: "1"),
            fixtures: fixtures
        )
    }

    private func makeEdit(offset: UInt64, hex: String = "00") throws -> MXFByteEdit {
        MXFByteEdit(
            offset: MXFDecimalUInt64(offset),
            originalHex: try MXFLowercaseHex(hex),
            replacementHex: try MXFLowercaseHex(String(repeating: "f", count: hex.count)),
            field: "field"
        )
    }

    private func makeEntry(
        id: String,
        outputPath: String,
        edits: [MXFByteEdit]? = nil,
        truncation: MXFTruncationRecord? = nil,
        lifecycle: MXFFixtureLifecycle = .draft,
        category: String = "invalidLength",
        consumerCode: String? = nil
    ) throws -> MXFFixtureManifestEntry {
        let rights = MXFSourceRights(
            redistributable: true,
            repositoryEligible: true,
            licenseIdentifier: "CC0-1.0"
        )
        let source = try MXFSourceIdentity(
            file: MXFRelativePath("sources/source.mxf"),
            sha256: String(repeating: "a", count: 64),
            size: 100,
            profile: "OP1a",
            rights: rights
        )
        let output = try MXFOutputIdentity(
            file: MXFRelativePath(outputPath),
            sha256: String(repeating: "b", count: 64),
            size: truncation?.retainedSize.value ?? 100,
            publicationEligible: true,
            sourceRights: rights
        )
        let limits = MXFReaderLimits(
            maxInputBytes: MXFDecimalUInt64(1_000),
            maxKLVElements: MXFDecimalUInt64(100),
            maxBERValueLength: MXFDecimalUInt64(1_000),
            maxAllocationBytes: MXFDecimalUInt64(1_000),
            maxLocalSetItems: MXFDecimalUInt64(100),
            maxPartitionHops: MXFDecimalUInt64(10),
            maxVisitedOffsets: MXFDecimalUInt64(100)
        )
        return try MXFFixtureManifestEntry(
            id: id,
            corpusClass: .parserConformance,
            lifecycle: lifecycle,
            mutationSchemaVersion: 1,
            source: source,
            output: output,
            seed: nil,
            mutation: MXFMutationRecord(
                targetOffset: MXFDecimalUInt64(0),
                targetClassification: "test",
                edits: edits ?? [try makeEdit(offset: 0)],
                truncation: truncation,
                semanticValues: []
            ),
            expected: MXFExpectedResult(
                outcome: .rejected,
                category: category,
                consumerCode: consumerCode
            ),
            limits: limits
        )
    }
}
