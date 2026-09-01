import Foundation
import XCTest
@testable import VideoCorruptor

final class BERMutationTests: XCTestCase {
    func testEveryBERFixtureGeneratesWithExactExpectedCategory() async throws {
        let cases: [(String, Data, MXFExpectedOutcome, String)] = [
            ("ber.indefiniteForm.v1", klv(length: Data([0x01]), payload: Data([0xaa])), .rejected, "invalidBER"),
            ("ber.lengthOfLengthTooLarge.v1", klv(length: Data([0x01]), payload: Data([0xaa])), .rejected, "invalidBER"),
            ("ber.headerTruncated.v1", klv(length: Data([0x81, 0x80]), payload: Data(repeating: 0xaa, count: 128)), .rejected, "unexpectedEOF"),
            ("ber.valueBeyondEOF.v1", klv(length: Data([0x02]), payload: Data([0xaa, 0xbb])), .rejected, "invalidLength"),
            ("ber.lengthAdditionOverflow.v1", klv(length: Data([0x88]) + Data(repeating: 0, count: 7) + Data([0x01]), payload: Data([0xaa])), .rejected, "integerOverflow"),
            ("ber.nonMinimalLongForm.v1", klv(length: Data([0x02]), payload: Data([0xaa, 0xbb])), .acceptedWithWarning, "nonCanonicalBER"),
            ("ber.shorterThanPayload.v1", klv(length: Data([0x02]), payload: Data([0xaa, 0xbb])), .rejected, "invalidLength")
        ]

        for fixtureCase in cases {
            let generated = try await generate(id: fixtureCase.0, sourceData: fixtureCase.1)
            XCTAssertEqual(generated.entry.expected.outcome, fixtureCase.2, fixtureCase.0)
            XCTAssertEqual(generated.entry.expected.category, fixtureCase.3, fixtureCase.0)
            XCTAssertEqual(generated.entry.mutation.targetOffset.value, 16, fixtureCase.0)
            XCTAssertEqual(generated.entry.mutation.targetClassification, "klv.ber.valueLength")
            XCTAssertFalse(generated.entry.mutation.edits.isEmpty && generated.entry.mutation.truncation == nil)
        }
    }

    func testSameWidthEditsAndHeaderTruncationNeverLeaveStaleBERBytes() async throws {
        let ordinary = try await generate(
            id: "ber.valueBeyondEOF.v1",
            sourceData: klv(length: Data([0x81, 0x80]), payload: Data(repeating: 0xaa, count: 128))
        )
        let edit = try XCTUnwrap(ordinary.entry.mutation.edits.first)
        XCTAssertEqual(edit.originalHex.value.count, edit.replacementHex.value.count)
        XCTAssertEqual(edit.originalHex.value.count, 4)

        let truncated = try await generate(
            id: "ber.headerTruncated.v1",
            sourceData: klv(length: Data([0x82, 0x01, 0x00]), payload: Data(repeating: 0xaa, count: 256))
        )
        XCTAssertTrue(truncated.entry.mutation.edits.isEmpty)
        XCTAssertEqual(truncated.entry.mutation.truncation?.retainedSize.value, 18)
        XCTAssertEqual(truncated.entry.output.size.value, 18)
    }

    func testNonMinimalLongFormKeepsPhysicalEndpointAndHasOnlyWarning() async throws {
        let generated = try await generate(
            id: "ber.nonMinimalLongForm.v1",
            sourceData: klv(length: Data([0x02]), payload: Data([0xaa, 0xbb]))
        )
        let output = try Data(contentsOf: generated.outputURL)
        XCTAssertEqual(Data(output[16...18]), Data([0x81, 0x01, 0xbb]))

        let inspected = MXFStructuralInspector().inspect(data: output)
        XCTAssertTrue(inspected.completedWalk)
        XCTAssertEqual(inspected.elements.first?.physicalSpan.upperBound, 19)
        XCTAssertEqual(inspected.diagnostics, [
            .nonCanonicalBER(
                offset: 16,
                diagnostic: .nonMinimalLongForm(minimumLengthOctetCount: 1, actualLengthOctetCount: 1)
            )
        ])
    }

    func testApplicabilityRulesAreExplicitAndDeterministic() throws {
        let fixtures = try MXFFixtureRegistry(fixtures: BERMutations.fixtures)
        let shortSource = MXFStructuralInspector().inspect(
            data: klv(length: Data([0x01]), payload: Data([0xaa]))
        )

        for id in ["ber.headerTruncated.v1", "ber.lengthAdditionOverflow.v1"] {
            let fixture = try XCTUnwrap(try fixtures.selected(ids: [id]).first)
            guard case .notApplicable(let reason) = fixture.evaluate(source: shortSource) else {
                return XCTFail("Expected notApplicable for \(id)")
            }
            XCTAssertTrue(reason.contains("no complete KLV satisfies"))
        }

        let twoElements = MXFStructuralInspector().inspect(
            data: klv(length: Data([0x01]), payload: Data([0xaa]))
                + klv(keyByte: 0x22, length: Data([0x02]), payload: Data([0xbb, 0xcc]))
        )
        let beyondEOF = try XCTUnwrap(
            try fixtures.selected(ids: ["ber.valueBeyondEOF.v1"]).first
        )
        XCTAssertEqual(
            beyondEOF.evaluate(source: twoElements),
            .applicable(targetOffset: 34, targetClassification: "klv.ber.valueLength")
        )
    }

    private func generate(id: String, sourceData: Data) async throws -> GeneratedFixture {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.mxf")
        try sourceData.write(to: source)
        let output = root.appendingPathComponent("corpus")
        let generator = MXFCorpusGenerator(
            registry: try MXFFixtureRegistry(fixtures: BERMutations.fixtures)
        )
        let report = try await generator.generate(MXFCorpusRequest(
            sources: [source],
            fixtureIDs: [id],
            outputDirectory: output,
            masterSeed: 7,
            includeSources: false
        ))
        XCTAssertTrue(report.notApplicable.isEmpty, id)
        let entry = try XCTUnwrap(report.manifest.fixtures.first)
        return GeneratedFixture(
            entry: entry,
            outputURL: output.appendingPathComponent(entry.output.file.value)
        )
    }

    private func klv(
        keyByte: UInt8 = 0x11,
        length: Data,
        payload: Data
    ) -> Data {
        Data(repeating: keyByte, count: 16) + length + payload
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BERMutationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct GeneratedFixture {
    let entry: MXFFixtureManifestEntry
    let outputURL: URL
}
