import Foundation
import CryptoKit
import XCTest
@testable import VideoCorruptor

final class BERCorpusGoldenTests: XCTestCase {
    private static let requiredKey = Data("REQPROFILEKEY001".utf8)

    private static let expectedBER: [String: (MXFExpectedOutcome, String)] = [
        "ber.headerTruncated.v1": (.rejected, "unexpectedEOF"),
        "ber.indefiniteForm.v1": (.rejected, "invalidBER"),
        "ber.lengthAdditionOverflow.v1": (.rejected, "integerOverflow"),
        "ber.lengthOfLengthTooLarge.v1": (.rejected, "invalidBER"),
        "ber.nonMinimalLongForm.v1": (.acceptedWithWarning, "nonCanonicalBER"),
        "ber.shorterThanPayload.v1": (.rejected, "invalidLength"),
        "ber.valueBeyondEOF.v1": (.rejected, "invalidLength"),
        "ber.zeroRequiredValue.v1": (.rejected, "invalidLength")
    ]

    private static let expectedTruncation: [String: (MXFExpectedOutcome, String)] = [
        "mxf.truncation.betweenCompleteKLVTriplets.v1": (.acceptedWithWarning, "cleanEndBeforeRemainingKLVs"),
        "mxf.truncation.immediatelyPostKey.v1": (.rejected, "unexpectedEOF"),
        "mxf.truncation.immediatelyPostLongBER.v1": (.rejected, "unexpectedEOF"),
        "mxf.truncation.insideKey.v1": (.rejected, "unexpectedEOF"),
        "mxf.truncation.insideLongBER.v1": (.rejected, "unexpectedEOF"),
        "mxf.truncation.oneByteBeforeValueEnd.v1": (.rejected, "unexpectedEOF")
    ]

    private static let expectedOutputHashes: [String: String] = [
        "ber.headerTruncated.v1": "3449b92928d177c53edd8440de80c119a8bc90005244270d3c9530503dcac017",
        "ber.indefiniteForm.v1": "6035aceb35898759edc6f79a2a3e5e176286f5851626ad9e4480b2c135ca167e",
        "ber.lengthAdditionOverflow.v1": "d58ebfd48531d6a4200ba9d88588aeb4c5d4d9c4eea5bcc5447b5a271f8162f7",
        "ber.lengthOfLengthTooLarge.v1": "ded67c7a46dc9f8cf5c3d52a45ff7081ddb0f54021944830a119370475e26fa9",
        "ber.nonMinimalLongForm.v1": "dd55990615c74af2499e55184b869d2b7868db5a80e2868c236c858c201d88cc",
        "ber.shorterThanPayload.v1": "05a91672e062b155ad0459ab61650d58dc34e747bb165cfe5e6ae5d91779ad30",
        "ber.valueBeyondEOF.v1": "2b3ea26d716853b7ec83da2496fe002b5b1be9ced81d0ebb4776cbf5725f94e4",
        "ber.zeroRequiredValue.v1": "557f7f19f6c4c2bfd4be9e08d0c76b08be1b78929462a735046ac4182b6aec91",
        "mxf.truncation.betweenCompleteKLVTriplets.v1": "82355471e047f3d8d9cb68b6630cd54c1a953b7c8a347d9d62013c8f1b24ea79",
        "mxf.truncation.immediatelyPostKey.v1": "48bae7545957b7b3c7a0d8912db7ca7252e7dc7589eae5aa7f70e635284befb1",
        "mxf.truncation.immediatelyPostLongBER.v1": "d69a27f21f7923203f550e517ff3270a9d64e3b60e4d63f98995004a032c637a",
        "mxf.truncation.insideKey.v1": "fd877723ffb01972949ecf7169f41dae5846fba867a098a0725e48722f8f0e40",
        "mxf.truncation.insideLongBER.v1": "3449b92928d177c53edd8440de80c119a8bc90005244270d3c9530503dcac017",
        "mxf.truncation.oneByteBeforeValueEnd.v1": "d5e1c216ad0f4c1af51e899d84e869c907200730ca74f1f9aca6f1f8d6c5c1c3"
    ]

    func testBERAndTruncationCorpusIsCanonicalAcrossDestinations() async throws {
        let root = try temporaryDirectory()
        let sources = try materializeSources(in: root)
        let declaration = try MXFRequiredElementDeclaration(
            profileID: "synthetic.embedded-klv.v1",
            key: Self.requiredKey,
            classification: "required embedded-sequence envelope",
            zeroLengthBoundaryPolicy: .payloadStartsCompleteKLVSequence
        )
        // These exact IDs are the compatibility boundary for the checked synthetic sources.
        let expectedIDs = Set(Self.expectedBER.keys).union(Self.expectedTruncation.keys)
        let waveTwoTruncations = MXFTruncationMutations.all.filter {
            expectedIDs.contains($0.definition.id)
        }
        let fixtures = BERMutations.fixtures(requiredElements: [declaration])
            + waveTwoTruncations.map { $0 as any MXFFixtureMutation }
        let registry = try MXFFixtureRegistry(fixtures: fixtures)

        XCTAssertEqual(Set(try registry.selected(ids: nil).map(\.definition.id)), expectedIDs)

        let generator = MXFCorpusGenerator(
            registry: registry,
            sourceProfile: "synthetic-klv-boundaries-v1",
            sourceRights: MXFSourceRights(
                redistributable: true,
                repositoryEligible: true,
                licenseIdentifier: "CC0-1.0"
            )
        )
        let first = root.appendingPathComponent("corpus-a")
        let second = root.appendingPathComponent("corpus-b")
        let firstReport = try await generator.generate(request(sources: sources, output: first))
        let secondReport = try await generator.generate(request(sources: sources, output: second))

        XCTAssertTrue(firstReport.notApplicable.isEmpty)
        XCTAssertTrue(firstReport.failures.isEmpty)
        XCTAssertEqual(firstReport.manifest, secondReport.manifest)
        XCTAssertEqual(Set(firstReport.manifest.fixtures.map(\.id)), expectedIDs)
        XCTAssertEqual(firstReport.manifest.fixtures.map(\.id), expectedIDs.sorted())

        let firstManifest = try Data(contentsOf: first.appendingPathComponent("manifest.json"))
        let secondManifest = try Data(contentsOf: second.appendingPathComponent("manifest.json"))
        XCTAssertEqual(firstManifest, secondManifest)
        XCTAssertEqual(sha256(firstManifest), sha256(secondManifest))
        XCTAssertEqual(
            sha256(firstManifest),
            "b0b8d7fbd59124321cc9786257467257c575c2e70ac24d7c35e8281aa7f1efc3"
        )

        for entry in firstReport.manifest.fixtures {
            let expected = Self.expectedBER[entry.id] ?? Self.expectedTruncation[entry.id]
            XCTAssertEqual(entry.corpusClass, .parserConformance, entry.id)
            XCTAssertEqual(entry.lifecycle, .draft, entry.id)
            XCTAssertEqual(entry.mutationSchemaVersion, 1, entry.id)
            XCTAssertEqual(entry.expected.outcome, expected?.0, entry.id)
            XCTAssertEqual(entry.expected.category, expected?.1, entry.id)
            XCTAssertEqual(entry.output.sha256, Self.expectedOutputHashes[entry.id], entry.id)
            XCTAssertTrue(entry.output.publicationEligible, entry.id)

            let hasEdits = !entry.mutation.edits.isEmpty
            let hasTruncation = entry.mutation.truncation != nil
            XCTAssertNotEqual(hasEdits, hasTruncation, "\(entry.id) must declare exactly one defect form")
            if hasEdits { XCTAssertEqual(entry.mutation.edits.count, 1, entry.id) }

            let firstOutput = first.appendingPathComponent(entry.output.file.value)
            let secondOutput = second.appendingPathComponent(entry.output.file.value)
            let firstBytes = try Data(contentsOf: firstOutput)
            let secondBytes = try Data(contentsOf: secondOutput)
            XCTAssertEqual(firstBytes, secondBytes, entry.id)
            XCTAssertEqual(sha256(firstBytes), entry.output.sha256, entry.id)
            XCTAssertEqual(sha256(secondBytes), entry.output.sha256, entry.id)
        }

        let zero = try XCTUnwrap(firstReport.manifest.fixtures.first { $0.id == "ber.zeroRequiredValue.v1" })
        XCTAssertEqual(
            zero.mutation.targetClassification,
            "profile.requiredElement:synthetic.embedded-klv.v1:required embedded-sequence envelope"
        )
    }

    private func request(sources: [URL], output: URL) -> MXFCorpusRequest {
        MXFCorpusRequest(
            sources: sources,
            fixtureIDs: nil,
            outputDirectory: output,
            masterSeed: 0x5741_5645_325F_474F,
            includeSources: true
        )
    }

    private func materializeSources(in root: URL) throws -> [URL] {
        try ["ber-general-v1", "ber-long-form-v1", "ber-nine-byte-v1"].map { name in
            let resource = try XCTUnwrap(
                Bundle(for: Self.self).url(forResource: name, withExtension: "mxf.hex")
            )
            let hex = try String(contentsOf: resource, encoding: .utf8)
                .filter { !$0.isWhitespace }
            guard hex.count.isMultiple(of: 2) else {
                throw SyntheticFixtureError.invalidHex(name)
            }
            var bytes = Data()
            bytes.reserveCapacity(hex.count / 2)
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                guard let byte = UInt8(hex[index..<next], radix: 16) else {
                    throw SyntheticFixtureError.invalidHex(name)
                }
                bytes.append(byte)
                index = next
            }
            let output = root.appendingPathComponent("\(name).mxf")
            try bytes.write(to: output)
            return output
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BERCorpusGoldenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum SyntheticFixtureError: Error {
    case invalidHex(String)
}
