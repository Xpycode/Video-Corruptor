import Foundation
import XCTest
@testable import VideoCorruptor

final class ManifestModelTests: XCTestCase {
    func testManifestRoundTripsWithStringEncodedUInt64Values() throws {
        let manifest = try makeManifest()
        let data = try JSONEncoder().encode(manifest)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"schemaIdentifier\":\"com.playplayplay.mxf-adversarial-corpus\""))
        XCTAssertTrue(json.contains("\"schemaVersion\":1"))
        XCTAssertTrue(json.contains("\"seed\":\"18446744073709551615\""))
        XCTAssertTrue(json.contains("\"offset\":\"4096\""))
        XCTAssertTrue(json.contains("\"size\":\"8192\""))
        XCTAssertEqual(try JSONDecoder().decode(MXFFixtureManifest.self, from: data), manifest)
    }

    func testMalformedUnsignedDecimalsAreRejected() throws {
        for invalid in ["", "01", "-1", "+1", "18446744073709551616", "1.0"] {
            let json = "\"\(invalid)\""
            XCTAssertThrowsError(
                try JSONDecoder().decode(MXFDecimalUInt64.self, from: Data(json.utf8)),
                "Expected rejection for \(invalid)"
            )
        }
    }

    func testMalformedHexIsRejected() throws {
        for invalid in ["", "0", "0x00", "AB", "ag", "00 11", "١٢"] {
            let json = "\"\(invalid)\""
            XCTAssertThrowsError(
                try JSONDecoder().decode(MXFLowercaseHex.self, from: Data(json.utf8)),
                "Expected rejection for \(invalid)"
            )
        }
    }

    func testRelativePathsRejectAbsoluteAndTraversalForms() {
        for invalid in ["", "/tmp/file.mxf", "../file.mxf", "fixtures/../file.mxf", "./file.mxf", "a//b", "a\\b"] {
            XCTAssertThrowsError(try MXFRelativePath(invalid), "Expected rejection for \(invalid)")
        }
    }

    func testSemanticValuesValidateSignedAndUnsignedDecimals() throws {
        _ = try MXFSemanticValue(field: "count", kind: .unsigned, original: "0", replacement: String(UInt64.max))
        _ = try MXFSemanticValue(field: "delta", kind: .signed, original: String(Int64.min), replacement: String(Int64.max))

        XCTAssertThrowsError(
            try MXFSemanticValue(field: "count", kind: .unsigned, original: "-1", replacement: "2")
        )
        XCTAssertThrowsError(
            try MXFSemanticValue(field: "delta", kind: .signed, original: "-01", replacement: "2")
        )
    }

    func testSourceRightsBoundOutputPublicationEligibility() throws {
        let rights = MXFSourceRights(
            redistributable: false,
            repositoryEligible: true,
            licenseIdentifier: nil
        )
        XCTAssertFalse(rights.permitsPublication)
        XCTAssertThrowsError(
            try MXFOutputIdentity(
                file: MXFRelativePath("fixtures/output.mxf"),
                sha256: String(repeating: "b", count: 64),
                size: 1,
                publicationEligible: true,
                sourceRights: rights
            )
        ) { error in
            XCTAssertEqual(error as? MXFModelError, .publicationEligibilityExceedsSourceRights)
        }
    }

    func testNotApplicableIsReportedOutsideManifestFixtureList() throws {
        let manifest = try makeManifest()
        let report = MXFCorpusReport(
            manifest: manifest,
            notApplicable: [
                MXFNotApplicableFixture(
                    fixtureID: "mxf.missing.rip.v1",
                    source: try MXFRelativePath("sources/source.mxf"),
                    reason: "Source has no RIP"
                ),
            ],
            failures: [],
            runMetadata: MXFCorpusRunMetadata(
                startedAt: Date(timeIntervalSince1970: 100),
                completedAt: Date(timeIntervalSince1970: 101)
            )
        )

        XCTAssertEqual(report.manifest.fixtures.count, 1)
        XCTAssertEqual(report.notApplicable.count, 1)
        XCTAssertFalse(report.manifest.fixtures.contains { $0.id == "mxf.missing.rip.v1" })
        XCTAssertEqual(try JSONDecoder().decode(MXFCorpusReport.self, from: JSONEncoder().encode(report)), report)
    }

    func testApplicabilityCarriesEitherTargetOrSpecificReason() {
        let applicable = MXFFixtureApplicability.applicable(
            targetOffset: 4096,
            targetClassification: "partitionPack"
        )
        let notApplicable = MXFFixtureApplicability.notApplicable(reason: "No partition pack")

        XCTAssertEqual(
            applicable,
            .applicable(targetOffset: 4096, targetClassification: "partitionPack")
        )
        XCTAssertEqual(notApplicable, .notApplicable(reason: "No partition pack"))
    }

    func testSchemaIdentityIsValidatedDuringDecode() throws {
        let data = try JSONEncoder().encode(makeManifest())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
            .replacingOccurrences(
                of: "com.playplayplay.mxf-adversarial-corpus",
                with: "unrelated.schema"
            )

        XCTAssertThrowsError(try JSONDecoder().decode(MXFFixtureManifest.self, from: Data(json.utf8)))
    }

    private func makeManifest() throws -> MXFFixtureManifest {
        let rights = MXFSourceRights(
            redistributable: true,
            repositoryEligible: true,
            licenseIdentifier: "CC0-1.0"
        )
        let source = try MXFSourceIdentity(
            file: MXFRelativePath("sources/source.mxf"),
            sha256: String(repeating: "a", count: 64),
            size: 8192,
            profile: "OP1a",
            rights: rights
        )
        let output = try MXFOutputIdentity(
            file: MXFRelativePath("fixtures/ber-indefinite.mxf"),
            sha256: String(repeating: "b", count: 64),
            size: 8192,
            publicationEligible: true,
            sourceRights: rights
        )
        let mutation = MXFMutationRecord(
            targetOffset: MXFDecimalUInt64(4096),
            targetClassification: "pictureEssenceKLV",
            edits: [
                MXFByteEdit(
                    offset: MXFDecimalUInt64(4096),
                    originalHex: try MXFLowercaseHex("83ffffff"),
                    replacementHex: try MXFLowercaseHex("80ffffff"),
                    field: "klv.valueLength"
                ),
            ],
            truncation: nil,
            semanticValues: [
                try MXFSemanticValue(
                    field: "klv.valueLength",
                    kind: .unsigned,
                    original: "16777215",
                    replacement: "0"
                ),
            ]
        )
        let limits = MXFReaderLimits(
            maxInputBytes: MXFDecimalUInt64(20_000),
            maxKLVElements: MXFDecimalUInt64(10_000),
            maxBERValueLength: MXFDecimalUInt64(UInt64.max),
            maxAllocationBytes: MXFDecimalUInt64(1_048_576),
            maxLocalSetItems: MXFDecimalUInt64(4_096),
            maxPartitionHops: MXFDecimalUInt64(128),
            maxVisitedOffsets: MXFDecimalUInt64(10_000)
        )
        let entry = try MXFFixtureManifestEntry(
            id: "mxf.ber.indefiniteForm.v1",
            corpusClass: .parserConformance,
            lifecycle: .draft,
            mutationSchemaVersion: 1,
            source: source,
            output: output,
            seed: MXFDecimalUInt64(UInt64.max),
            mutation: mutation,
            expected: MXFExpectedResult(
                outcome: .rejected,
                category: "invalidBER",
                consumerCode: nil
            ),
            limits: limits
        )
        return MXFFixtureManifest(
            generator: MXFGeneratorIdentity(name: "VideoCorruptor", version: "1.0.0"),
            fixtures: [entry]
        )
    }
}
