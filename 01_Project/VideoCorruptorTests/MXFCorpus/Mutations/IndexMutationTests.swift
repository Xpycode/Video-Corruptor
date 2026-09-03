import Foundation
import XCTest
@testable import VideoCorruptor

final class IndexMutationTests: XCTestCase {
    func testSevenIndexFixturesMakeOneExactWidthFieldEditAndTypedOutcome() async throws {
        let cases: [(String, String, String, UInt64)] = [
            ("count.indexEntryExceedsPayload.v1", "invalidCount", "index.indexEntryArray.count", 66),
            ("index.streamOffsetBeyondEssence.v1", "invalidOffset", "index.indexEntryArray.streamOffset", 77),
            ("index.streamOffsetsBackward.v1", "invalidOffset", "index.indexEntryArray.streamOffset", 88),
            ("index.streamOffsetsDuplicate.v1", "invalidOffset", "index.indexEntryArray.streamOffset", 88),
            ("index.sidMismatch.v1", "referenceMismatch", "index.indexSID", 31),
            ("index.bodySIDMismatch.v1", "referenceMismatch", "index.bodySID", 38),
            ("index.editRateZeroDenominator.v1", "invalidRate", "index.indexEditRate.denominator", 24)
        ]
        for item in cases {
            let generated = try await generate(item.0)
            XCTAssertEqual(generated.expected.category, item.1, item.0)
            XCTAssertEqual(generated.mutation.targetOffset.value, item.3, item.0)
            XCTAssertEqual(generated.mutation.edits.count, 1, item.0)
            XCTAssertEqual(generated.mutation.edits[0].field, item.2, item.0)
            XCTAssertEqual(generated.mutation.edits[0].originalHex.value.count,
                           generated.mutation.edits[0].replacementHex.value.count, item.0)
            XCTAssertTrue(generated.mutation.targetClassification.contains("tag.0x"), item.0)
            XCTAssertTrue(generated.mutation.targetClassification.contains("offset."), item.0)
        }
    }

    func testDefinitionsRecordExactSetTagsAndDeclaredItemOffsets() throws {
        for fixture in try fixtures() {
            XCTAssertEqual(fixture.definition.parameters["setKey"], String(repeating: "55", count: 16))
            for field in MXFIndexTableField.allCases {
                let parameter = try XCTUnwrap(fixture.definition.parameters[field.rawValue])
                XCTAssertTrue(parameter.contains("tag=0x"))
                XCTAssertTrue(parameter.contains("itemOffset="))
            }
            XCTAssertEqual(fixture.definition.corpusClass, .parserConformance)
        }
    }

    func testUndeclaredSetIsNotApplicable() throws {
        let registry = try MXFFixtureRegistry(fixtures: try fixtures())
        let fixture = try XCTUnwrap(registry.selected(ids: ["index.sidMismatch.v1"]).first)
        guard case .notApplicable(let reason) = fixture.evaluate(
            source: MXFStructuralInspector().inspect(data: sourceData(setKeyByte: 0x44))
        ) else { return XCTFail("undeclared source must be rejected") }
        XCTAssertTrue(reason.contains("preconditions"))
    }

    private func generate(_ id: String) async throws -> MXFFixtureManifestEntry {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexMutationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mxf")
        try sourceData().write(to: source)
        let report = try await MXFCorpusGenerator(registry: try MXFFixtureRegistry(fixtures: try fixtures()))
            .generate(.init(sources: [source], fixtureIDs: [id], outputDirectory: root.appendingPathComponent("corpus"),
                            masterSeed: 45, includeSources: false))
        XCTAssertTrue(report.notApplicable.isEmpty, id)
        return try XCTUnwrap(report.manifest.fixtures.first)
    }

    private func fixtures() throws -> [any MXFFixtureMutation] {
        let tags: [UInt16: MXFIndexTableField] = [
            0x0101: .indexEditRate, 0x0102: .indexSID, 0x0103: .bodySID,
            0x0104: .sliceCount, 0x0105: .deltaEntryArray, 0x0106: .indexEntryArray
        ]
        let offsets: [MXFIndexTableField: UInt64] = [
            .indexEditRate: 0, .indexSID: 11, .bodySID: 18, .sliceCount: 25,
            .deltaEntryArray: 29, .indexEntryArray: 46
        ]
        return IndexMutations.fixtures(declarations: [try .init(
            profileID: "synthetic.index.v1", setKey: Data(repeating: 0x55, count: 16), tags: tags,
            universalLabels: Dictionary(uniqueKeysWithValues: tags.keys.map { ($0, Data(repeating: UInt8($0 & 0xff), count: 16)) }),
            itemOffsets: offsets,
            itemLengthEncodedWidths: Dictionary(uniqueKeysWithValues: MXFIndexTableField.allCases.map { ($0, 1) }),
            baselineStreamOffsets: [4, 20], indexEntryValueLength: 30, indexEntryItemSize: 11,
            expectedIndexSID: 7, expectedBodySID: 9,
            essenceStreamSpan: ByteSpan(offset: 113, length: 64)
        )])
    }

    private func sourceData(setKeyByte: UInt8 = 0x55, indexSID: UInt32 = 7) -> Data {
        var set = Data()
        appendItem(0x0101, be32(25) + be32(1), to: &set)
        appendItem(0x0102, be32(indexSID), to: &set)
        appendItem(0x0103, be32(9), to: &set)
        appendItem(0x0104, Data([0]), to: &set)
        appendItem(0x0105, be32(1) + be32(6) + Data(repeating: 0, count: 6), to: &set)
        var entries = be32(2) + be32(11)
        for value: UInt64 in [4, 20] { entries += Data([0, 0, 0]) + be64(value) }
        appendItem(0x0106, entries, to: &set)
        return Data(repeating: setKeyByte, count: 16) + Data([UInt8(set.count)]) + set
            + Data(repeating: 0xee, count: 16) + Data([64]) + Data(repeating: 0xab, count: 64)
    }

    private func appendItem(_ tag: UInt16, _ value: Data, to data: inout Data) {
        data += Data([UInt8(tag >> 8), UInt8(truncatingIfNeeded: tag), UInt8(value.count)]) + value
    }
}

private func be32(_ value: UInt32) -> Data {
    Data([UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value)])
}

private func be64(_ value: UInt64) -> Data {
    Data((0..<8).reversed().map { UInt8(value >> UInt64($0 * 8)) })
}
