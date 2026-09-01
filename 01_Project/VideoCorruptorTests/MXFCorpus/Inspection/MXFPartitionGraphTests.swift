import Foundation
import XCTest
@testable import VideoCorruptor

final class MXFPartitionGraphTests: XCTestCase {
    private let inspector = MXFPartitionGraphInspector()

    func testMapsPhysicalNodesLinksAndTraversesPreviousChain() throws {
        let fixture = try makeFixture([
            Pack(this: 17, previous: 0, footer: 227, kind: 2),
            Pack(this: 122, previous: 17, footer: 227, kind: 3),
            Pack(this: 227, previous: 122, footer: 0, kind: 4)
        ])
        let graph = try inspect(fixture, start: 227)

        XCTAssertEqual(Set(graph.nodesByPhysicalOffset.keys), [17, 122, 227])
        XCTAssertEqual(graph.nodesByPhysicalOffset[17]?.pack.keyClassification.kind, .header)
        XCTAssertEqual(graph.nodesByPhysicalOffset[122]?.previous.resolution,
                       .partition(physicalOffset: 17))
        XCTAssertEqual(graph.nodesByPhysicalOffset[17]?.footer.resolution,
                       .partition(physicalOffset: 227))
        XCTAssertEqual(graph.traversal.path, [227, 122, 17])
        XCTAssertEqual(graph.traversal.visitedPhysicalOffsets, [17, 122, 227])
        XCTAssertEqual(graph.traversal.hopCount, 2)
        XCTAssertEqual(graph.traversal.terminatedAt, .absent)
        XCTAssertEqual(graph.diagnostics, [])
    }

    func testThisPartitionMismatchDoesNotChangePhysicalIdentity() throws {
        let fixture = try makeFixture([Pack(this: 9_999, previous: 0, footer: 0, kind: 2)])
        let graph = try inspect(fixture, start: 17)

        XCTAssertNotNil(graph.nodesByPhysicalOffset[17])
        XCTAssertNil(graph.nodesByPhysicalOffset[9_999])
        XCTAssertEqual(graph.diagnostics, [
            .thisPartitionMismatch(
                physicalOffset: 17, declaredOffset: 9_999,
                fieldSpan: try ByteSpan(offset: 42, length: 8)
            )
        ])
    }

    func testSelfCycleTerminatesAfterExactlyOneHop() throws {
        let fixture = try makeFixture([Pack(this: 17, previous: 17, footer: 0, kind: 3)])
        let graph = try inspect(fixture, start: 17)

        XCTAssertEqual(graph.traversal.path, [17, 17])
        XCTAssertEqual(graph.traversal.visitedPhysicalOffsets, [17])
        XCTAssertEqual(graph.traversal.hopCount, 1)
        XCTAssertEqual(graph.diagnostics, [.cycle(kind: .previous, offsets: [17, 17])])
    }

    func testTwoNodeCycleTerminatesAfterExactlyTwoHops() throws {
        let fixture = try makeFixture([
            Pack(this: 17, previous: 122, footer: 0, kind: 3),
            Pack(this: 122, previous: 17, footer: 0, kind: 3)
        ])
        let graph = try inspect(fixture, start: 17)

        XCTAssertEqual(graph.traversal.path, [17, 122, 17])
        XCTAssertEqual(graph.traversal.visitedPhysicalOffsets, [17, 122])
        XCTAssertEqual(graph.traversal.hopCount, 2)
        XCTAssertEqual(graph.diagnostics,
                       [.cycle(kind: .previous, offsets: [17, 122, 17])])
    }

    func testHopAndVisitedLimitsStopBeforeExceededOperation() throws {
        let fixture = try makeFixture([
            Pack(this: 17, previous: 122, footer: 0, kind: 3),
            Pack(this: 122, previous: 17, footer: 0, kind: 3)
        ])
        let hopLimited = try inspect(
            fixture, start: 17,
            limits: .init(maximumPartitionHops: 1, maximumVisitedOffsets: 2)
        )
        XCTAssertEqual(hopLimited.traversal.path, [17, 122])
        XCTAssertEqual(hopLimited.traversal.hopCount, 1)
        XCTAssertEqual(hopLimited.diagnostics, [
            .limitExceeded(limit: .partitionHops, attempted: 2, maximum: 1)
        ])

        let visitedLimited = try inspect(
            fixture, start: 17,
            limits: .init(maximumPartitionHops: 2, maximumVisitedOffsets: 1)
        )
        XCTAssertEqual(visitedLimited.traversal.path, [17])
        XCTAssertEqual(visitedLimited.traversal.visitedPhysicalOffsets, [17])
        XCTAssertEqual(visitedLimited.traversal.hopCount, 1)
        XCTAssertEqual(visitedLimited.diagnostics, [
            .limitExceeded(limit: .visitedOffsets, attempted: 2, maximum: 1)
        ])
    }

    func testDiagnosesEOFBeyondInteriorAndWrongKeyTargetsFromElementMap() throws {
        // Layout: filler 0..<17, partition 17..<122, non-partition 122..<139.
        let eof: UInt64 = 139
        let targets: [(UInt64, MXFPartitionLinkResolution)] = [
            (eof, .endOfFile),
            (eof + 1, .beyondEndOfFile),
            (30, .insideElement(elementOffset: 17)),
            (122, .nonPartitionElement(elementOffset: 122))
        ]
        for (target, expected) in targets {
            let fixture = try makeFixture(
                [Pack(this: 17, previous: 0, footer: target, kind: 2)],
                trailingElement: true
            )
            let graph = try inspect(fixture, start: 17)
            XCTAssertEqual(graph.nodesByPhysicalOffset[17]?.footer.resolution, expected)
            XCTAssertTrue(graph.diagnostics.contains { diagnostic in
                guard case .invalidLink(let link) = diagnostic else { return false }
                return link.kind == .footer && link.resolution == expected
            })
        }
    }

    func testFooterTraversalUsesSameBoundedCycleAccounting() throws {
        let fixture = try makeFixture([
            Pack(this: 17, previous: 0, footer: 122, kind: 2),
            Pack(this: 122, previous: 17, footer: 17, kind: 4)
        ])
        let graph = try inspect(fixture, start: 17, following: .footer)
        XCTAssertEqual(graph.traversal.path, [17, 122, 17])
        XCTAssertEqual(graph.traversal.hopCount, 2)
        XCTAssertTrue(graph.diagnostics.contains(.cycle(kind: .footer, offsets: [17, 122, 17])))
    }

    func testZeroVisitedLimitDoesNotVisitStart() throws {
        let fixture = try makeFixture([Pack(this: 17, previous: 0, footer: 0, kind: 2)])
        let graph = try inspect(
            fixture, start: 17,
            limits: .init(maximumPartitionHops: 10, maximumVisitedOffsets: 0)
        )
        XCTAssertEqual(graph.traversal.path, [])
        XCTAssertEqual(graph.traversal.hopCount, 0)
        XCTAssertEqual(graph.diagnostics, [
            .limitExceeded(limit: .visitedOffsets, attempted: 1, maximum: 0)
        ])
    }

    private struct Pack {
        let this: UInt64
        let previous: UInt64
        let footer: UInt64
        let kind: UInt8
    }

    private struct Fixture {
        let url: URL
        let structural: MXFInspectedFile
    }

    private func makeFixture(_ packs: [Pack], trailingElement: Bool = false) throws -> Fixture {
        var data = Data(repeating: 0x11, count: 16) + Data([0])
        for pack in packs {
            let keyOffset = UInt64(data.count)
            XCTAssertEqual(keyOffset, pack.this == 9_999 ? 17 : pack.this)
            data += partitionKey(kind: pack.kind) + Data([88])
            let valueOffset = UInt64(data.count)
            data += Data(repeating: 0, count: 88)
            try data.checkedWriteUInt16BE(1, at: valueOffset)
            try data.checkedWriteUInt16BE(3, at: valueOffset + 2)
            try data.checkedWriteUInt32BE(1, at: valueOffset + 4)
            try data.checkedWriteUInt64BE(pack.this, at: valueOffset + 8)
            try data.checkedWriteUInt64BE(pack.previous, at: valueOffset + 16)
            try data.checkedWriteUInt64BE(pack.footer, at: valueOffset + 24)
            try data.checkedWriteUInt32BE(16, at: valueOffset + 84)
        }
        if trailingElement { data += Data(repeating: 0x22, count: 16) + Data([0]) }
        let structural = MXFStructuralInspector().inspect(data: data)
        XCTAssertTrue(structural.completedWalk)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MXFPartitionGraphTests-\(UUID().uuidString)")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return Fixture(url: url, structural: structural)
    }

    private func inspect(
        _ fixture: Fixture,
        start: UInt64,
        following: MXFPartitionLinkKind = .previous,
        limits: MXFPartitionGraphLimits = .init()
    ) throws -> MXFPartitionGraph {
        try inspector.inspect(fileAt: fixture.url, structuralFile: fixture.structural,
                              traversalStartOffset: start, following: following, limits: limits)
    }

    private func partitionKey(kind: UInt8) -> Data {
        Data([0x06, 0x0e, 0x2b, 0x34, 0x02, 0x05, 0x01, 0x01,
              0x0d, 0x01, 0x02, 0x01, 0x01, kind, 0x04, 0x00])
    }
}
