import Foundation
import XCTest
@testable import VideoCorruptor

final class CountMutationTests: XCTestCase {
    func testFiveDeclaredCountFixturesGenerateExactTypedEdits() async throws {
        let cases: [(String, String, String, UInt64)] = [
            ("count.localSetItemExceedsValue.v1", "invalidLength", "localSet.itemLength", 19),
            ("count.batchExceedsPayload.v1", "invalidCount", "batch.count", 20),
            ("count.batchItemSizeZero.v1", "invalidCount", "batch.itemSize", 24),
            ("count.batchMultiplicationOverflow.v1", "limitExceeded", "batch.count", 20),
            ("count.sliceDeltaExtreme.v1", "limitExceeded", "index.sliceDeltaCount", 35)
        ]
        for testCase in cases {
            let generated = try await generate(testCase.0)
            XCTAssertEqual(generated.expected.category, testCase.1, testCase.0)
            XCTAssertEqual(generated.mutation.targetOffset.value, testCase.3, testCase.0)
            XCTAssertEqual(generated.mutation.edits.first?.field, testCase.2, testCase.0)
            let edit = try XCTUnwrap(generated.mutation.edits.first)
            XCTAssertEqual(edit.originalHex.value.count, edit.replacementHex.value.count)
            XCTAssertEqual(generated.mutation.semanticValues.first?.field, testCase.2)
        }
    }

    func testHugeCountsInTinyOutputTerminateWithLimitExceeded() async throws {
        for id in ["count.batchMultiplicationOverflow.v1", "count.sliceDeltaExtreme.v1"] {
            let generated = try await generate(id)
            XCTAssertEqual(generated.output.size.value, UInt64(sourceData().count))
            XCTAssertEqual(generated.mutation.edits.first?.replacementHex.value, "ffffffff")
            XCTAssertEqual(generated.expected.category, "limitExceeded")
        }
    }

    func testUndeclaredSetIsNotApplicable() throws {
        let inspected = MXFStructuralInspector().inspect(data: sourceData(keyByte: 0x44))
        let fixture = try XCTUnwrap(try MXFFixtureRegistry(fixtures: try fixtures())
            .selected(ids: ["count.batchExceedsPayload.v1"]).first)
        guard case .notApplicable(let reason) = fixture.evaluate(source: inspected) else {
            return XCTFail("an undeclared key must not be targeted")
        }
        XCTAssertTrue(reason.contains("declared profile"))
    }

    private func generate(_ id: String) async throws -> MXFFixtureManifestEntry {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountMutationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mxf")
        try sourceData().write(to: source)
        let output = root.appendingPathComponent("corpus")
        let report = try await MXFCorpusGenerator(registry: try MXFFixtureRegistry(fixtures: try fixtures()))
            .generate(.init(sources: [source], fixtureIDs: [id], outputDirectory: output,
                            masterSeed: 11, includeSources: false))
        XCTAssertTrue(report.notApplicable.isEmpty, id)
        return try XCTUnwrap(report.manifest.fixtures.first)
    }

    private func fixtures() throws -> [any MXFFixtureMutation] {
        CountMutations.fixtures(declarations: [try MXFCountFixtureDeclaration(
            profileID: "synthetic.counts.v1",
            setKey: Data(repeating: 0x33, count: 16),
            batchTag: 0x1001, batchUniversalLabel: Data(repeating: 0xa1, count: 16),
            batchItemOffset: 0, batchLengthEncodedWidth: 1, batchValueLength: 12,
            batchCount: 1, batchItemSize: 4,
            sliceDeltaTag: 0x1002, sliceDeltaUniversalLabel: Data(repeating: 0xa2, count: 16),
            sliceDeltaItemOffset: 15, sliceDeltaLengthEncodedWidth: 1, sliceDeltaValueLength: 12,
            sliceDeltaCount: 1, sliceDeltaItemSize: 4
        )])
    }

    private func sourceData(keyByte: UInt8 = 0x33) -> Data {
        let item1 = Data([0x10, 0x01, 0x0c, 0, 0, 0, 1, 0, 0, 0, 4, 1, 2, 3, 4])
        let item2 = Data([0x10, 0x02, 0x0c, 0, 0, 0, 1, 0, 0, 0, 4, 5, 6, 7, 8])
        return Data(repeating: keyByte, count: 16) + Data([30]) + item1 + item2
    }
}
