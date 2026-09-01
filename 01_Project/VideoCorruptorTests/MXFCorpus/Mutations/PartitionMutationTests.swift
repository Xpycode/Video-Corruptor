import Foundation
import XCTest
@testable import VideoCorruptor

final class PartitionMutationTests: XCTestCase {
    func testPartitionOffsetMatrixGeneratesExactEightByteEditAndCategory() async throws {
        let cases: [(String, String, MXFPartitionLinkResolution?)] = [
            ("partition.footerAtEOF.v1", "invalidOffset", .endOfFile),
            ("partition.footerBeyondEOF.v1", "invalidOffset", .beyondEndOfFile),
            ("partition.footerInsideValue.v1", "invalidPartition", .insideElement(elementOffset: 17)),
            ("partition.footerWrongKey.v1", "invalidPartition", .nonPartitionElement(elementOffset: 227)),
            ("partition.thisOffsetMismatch.v1", "invalidOffset", nil)
        ]
        for item in cases {
            let generated = try await generate(id: item.0, data: fixture(partitionCount: 2, trailing: true))
            XCTAssertEqual(generated.entry.lifecycle, .draft, item.0)
            XCTAssertEqual(generated.entry.expected.category, item.1, item.0)
            XCTAssertNil(generated.entry.expected.consumerCode, item.0)
            XCTAssertEqual(generated.entry.source.profile, "synthetic.op1a.partition.v1", item.0)
            XCTAssertEqual(generated.entry.mutation.edits.count, 1, item.0)
            XCTAssertEqual(generated.entry.mutation.edits[0].originalHex.value.count, 16, item.0)
            XCTAssertEqual(generated.entry.mutation.edits[0].replacementHex.value.count, 16, item.0)
            XCTAssertEqual(generated.entry.mutation.semanticValues.count, 1, item.0)

            let graph = try graph(generated.outputURL, start: 17, following: item.2 == nil ? .previous : .footer)
            if let resolution = item.2 {
                XCTAssertEqual(graph.nodesByPhysicalOffset[17]?.footer.resolution, resolution, item.0)
                XCTAssertEqual(graph.traversal.hopCount, 1, item.0)
            } else {
                XCTAssertTrue(graph.diagnostics.contains { if case .thisPartitionMismatch = $0 { true } else { false } })
                XCTAssertEqual(graph.traversal.hopCount, 0)
            }
        }
    }

    func testPreviousCyclesHaveExactHopCountsAndOnlyNecessaryFieldEdits() async throws {
        let selfCycle = try await generate(
            id: "partition.previousSelfCycle.v1", data: fixture(partitionCount: 2, trailing: false)
        )
        XCTAssertEqual(selfCycle.entry.expected.category, "partitionCycle")
        XCTAssertEqual(selfCycle.entry.mutation.edits.count, 1)
        let selfGraph = try graph(selfCycle.outputURL, start: 122, following: .previous)
        XCTAssertEqual(selfGraph.traversal.path, [122, 122])
        XCTAssertEqual(selfGraph.traversal.hopCount, 1)

        let twoNode = try await generate(
            id: "partition.previousTwoNodeCycle.v1", data: fixture(partitionCount: 2, trailing: false)
        )
        XCTAssertEqual(twoNode.entry.mutation.edits.count, 1, "valid second-to-first link is retained")
        XCTAssertEqual(twoNode.entry.mutation.semanticValues.count, 1)
        let twoGraph = try graph(twoNode.outputURL, start: 17, following: .previous)
        XCTAssertEqual(twoGraph.traversal.path, [17, 122, 17])
        XCTAssertEqual(twoGraph.traversal.hopCount, 2)
    }

    func testTwoNodeCycleUsesTwoEditsWhenReciprocalLinkMustAlsoChange() async throws {
        let generated = try await generate(
            id: "partition.previousTwoNodeCycle.v1",
            data: fixture(partitionCount: 2, trailing: false, secondPrevious: 0)
        )
        XCTAssertEqual(generated.entry.mutation.edits.count, 2)
        XCTAssertEqual(generated.entry.mutation.edits.map(\.offset.value), [50, 155])
        let graph = try graph(generated.outputURL, start: 17, following: .previous)
        XCTAssertEqual(graph.traversal.hopCount, 2)
        XCTAssertTrue(graph.diagnostics.contains(.cycle(kind: .previous, offsets: [17, 122, 17])))
    }

    func testApplicabilityIsDeterministicAndShapeDependent() throws {
        let registry = try MXFFixtureRegistry(fixtures: PartitionMutations.fixtures)
        let one = MXFStructuralInspector().inspect(data: fixture(partitionCount: 1, trailing: false))
        let twoNode = try XCTUnwrap(try registry.selected(ids: ["partition.previousTwoNodeCycle.v1"]).first)
        guard case .notApplicable(let reason) = twoNode.evaluate(source: one) else {
            return XCTFail("two-node cycle requires two partitions")
        }
        XCTAssertTrue(reason.contains("cannot isolate"))

        let noWrongKey = MXFStructuralInspector().inspect(data: fixture(partitionCount: 1, trailing: false, filler: false))
        let wrongKey = try XCTUnwrap(try registry.selected(ids: ["partition.footerWrongKey.v1"]).first)
        guard case .notApplicable = wrongKey.evaluate(source: noWrongKey) else {
            return XCTFail("wrong-key offset requires a non-partition element")
        }
    }

    private struct Generated { let entry: MXFFixtureManifestEntry; let outputURL: URL }

    private func generate(id: String, data: Data) async throws -> Generated {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PartitionMutationTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mxf")
        try data.write(to: source)
        let output = root.appendingPathComponent("corpus")
        let report = try await MXFCorpusGenerator(
            registry: try MXFFixtureRegistry(fixtures: PartitionMutations.fixtures),
            sourceProfile: "synthetic.op1a.partition.v1"
        ).generate(MXFCorpusRequest(sources: [source], fixtureIDs: [id], outputDirectory: output,
                                    masterSeed: 9, includeSources: false))
        XCTAssertTrue(report.notApplicable.isEmpty, id)
        let entry = try XCTUnwrap(report.manifest.fixtures.first)
        return Generated(entry: entry, outputURL: output.appendingPathComponent(entry.output.file.value))
    }

    private func graph(_ url: URL, start: UInt64, following: MXFPartitionLinkKind) throws -> MXFPartitionGraph {
        let structural = try MXFStructuralInspector().inspect(fileAt: url)
        return try MXFPartitionGraphInspector().inspect(fileAt: url, structuralFile: structural,
            traversalStartOffset: start, following: following,
            limits: .init(maximumPartitionHops: 4, maximumVisitedOffsets: 4))
    }

    private func fixture(partitionCount: Int, trailing: Bool, secondPrevious: UInt64 = 17,
                         filler: Bool = true) -> Data {
        var data = filler ? Data(repeating: 0x11, count: 16) + Data([0]) : Data()
        for index in 0..<partitionCount {
            let offset = UInt64(data.count)
            data += partitionKey(kind: index == 0 ? 2 : 3) + Data([88])
            let value = UInt64(data.count)
            data += Data(repeating: 0, count: 88)
            try! data.checkedWriteUInt16BE(1, at: value)
            try! data.checkedWriteUInt16BE(3, at: value + 2)
            try! data.checkedWriteUInt32BE(1, at: value + 4)
            try! data.checkedWriteUInt64BE(offset, at: value + 8)
            let previous: UInt64 = index == 0 ? 0 : secondPrevious
            try! data.checkedWriteUInt64BE(previous, at: value + 16)
            try! data.checkedWriteUInt64BE(0, at: value + 24)
            try! data.checkedWriteUInt32BE(16, at: value + 84)
        }
        if trailing { data += Data(repeating: 0x22, count: 16) + Data([0]) }
        return data
    }

    private func partitionKey(kind: UInt8) -> Data {
        Data([0x06, 0x0e, 0x2b, 0x34, 0x02, 0x05, 0x01, 0x01,
              0x0d, 0x01, 0x02, 0x01, 0x01, kind, 0x04, 0x00])
    }
}
