import Foundation
import XCTest
@testable import VideoCorruptor

final class MXFPartitionInspectorTests: XCTestCase {
    private let inspector = MXFPartitionInspector()

    func testClassifiesAllTwelvePartitionPackKeysFromPhysicalUL() {
        let kinds: [(UInt8, MXFPartitionKind)] = [(2, .header), (3, .body), (4, .footer)]
        let states: [(UInt8, MXFPartitionClosure, MXFPartitionCompleteness)] = [
            (1, .open, .incomplete), (2, .closed, .incomplete),
            (3, .open, .complete), (4, .closed, .complete)
        ]
        for (kindByte, kind) in kinds {
            for (stateByte, closure, completeness) in states {
                XCTAssertEqual(
                    inspector.classify(key: key(kind: kindByte, status: stateByte)),
                    MXFPartitionKeyClassification(
                        kind: kind, closure: closure, completeness: completeness
                    )
                )
            }
        }
    }

    func testSimilarAndInvalidKeysAreNotClassified() {
        XCTAssertNil(inspector.classify(key: Data(repeating: 0, count: 15)))
        for (index, replacement): (Int, UInt8) in [(0, 0x07), (12, 0x02), (13, 0x05),
                                                    (14, 0x05), (15, 0x01)] {
            var candidate = key()
            candidate[index] = replacement
            XCTAssertNil(inspector.classify(key: candidate), "index \(index)")
        }
        let value = try? ByteSpan(offset: 17, length: 88)
        let keySpan = try? ByteSpan(offset: 0, length: 16)
        if let value, let keySpan {
            XCTAssertEqual(
                inspector.inspect(key: Data(repeating: 0, count: 16), keySpan: keySpan,
                                  valueSpan: value, in: Data(repeating: 0, count: 105)),
                .notPartitionPack
            )
        } else {
            XCTFail("test spans must be constructible")
        }
    }

    func testParsesEveryFixedFieldAndReportsPhysicalSpans() throws {
        let valueOffset: UInt64 = 33
        var file = Data(repeating: 0xee, count: Int(valueOffset + 88))
        try file.checkedWriteUInt16BE(1, at: valueOffset)
        try file.checkedWriteUInt16BE(3, at: valueOffset + 2)
        try file.checkedWriteUInt32BE(0x0102_0304, at: valueOffset + 4)
        try file.checkedWriteUInt64BE(0x1112_1314_1516_1718, at: valueOffset + 8)
        try file.checkedWriteUInt64BE(0x2122_2324_2526_2728, at: valueOffset + 16)
        try file.checkedWriteUInt64BE(0x3132_3334_3536_3738, at: valueOffset + 24)
        try file.checkedWriteUInt64BE(0x4142_4344_4546_4748, at: valueOffset + 32)
        try file.checkedWriteUInt64BE(0x5152_5354_5556_5758, at: valueOffset + 40)
        try file.checkedWriteUInt32BE(0x6162_6364, at: valueOffset + 48)
        try file.checkedWriteUInt64BE(0x7172_7374_7576_7778, at: valueOffset + 52)
        try file.checkedWriteUInt32BE(0x8182_8384, at: valueOffset + 60)
        let operationalPattern = Data(0..<16)
        try file.checkedWriteBytes(operationalPattern,
                                   in: ByteSpan(offset: valueOffset + 64, length: 16))
        try file.checkedWriteUInt32BE(2, at: valueOffset + 80)
        try file.checkedWriteUInt32BE(16, at: valueOffset + 84)

        let result = inspector.inspect(
            key: key(kind: 3, status: 4),
            keySpan: try ByteSpan(offset: 8, length: 16),
            valueSpan: try ByteSpan(offset: valueOffset, length: 88),
            in: file
        )
        guard case .partitionPack(let pack) = result else {
            return XCTFail("expected parsed partition, got \(result)")
        }
        XCTAssertEqual(pack.keyClassification, .init(kind: .body, closure: .closed,
                                                       completeness: .complete))
        XCTAssertEqual(pack.majorVersion.value, 1)
        XCTAssertEqual(pack.minorVersion.value, 3)
        XCTAssertEqual(pack.kagSize.value, 0x0102_0304)
        XCTAssertEqual(pack.thisPartition.value, 0x1112_1314_1516_1718)
        XCTAssertEqual(pack.previousPartition.value, 0x2122_2324_2526_2728)
        XCTAssertEqual(pack.footerPartition.value, 0x3132_3334_3536_3738)
        XCTAssertEqual(pack.headerByteCount.value, 0x4142_4344_4546_4748)
        XCTAssertEqual(pack.indexByteCount.value, 0x5152_5354_5556_5758)
        XCTAssertEqual(pack.indexSID.value, 0x6162_6364)
        XCTAssertEqual(pack.bodyOffset.value, 0x7172_7374_7576_7778)
        XCTAssertEqual(pack.bodySID.value, 0x8182_8384)
        XCTAssertEqual(pack.operationalPattern.value, operationalPattern)
        XCTAssertEqual(pack.essenceContainerCount.value, 2)
        XCTAssertEqual(pack.essenceContainerElementSize.value, 16)
        XCTAssertEqual(pack.majorVersion.span, try ByteSpan(offset: valueOffset, length: 2))
        XCTAssertEqual(pack.thisPartition.span, try ByteSpan(offset: valueOffset + 8, length: 8))
        XCTAssertEqual(pack.indexSID.span, try ByteSpan(offset: valueOffset + 48, length: 4))
        XCTAssertEqual(pack.bodyOffset.span, try ByteSpan(offset: valueOffset + 52, length: 8))
        XCTAssertEqual(pack.operationalPattern.span, try ByteSpan(offset: valueOffset + 64, length: 16))
        XCTAssertEqual(pack.essenceContainerElementSize.span,
                       try ByteSpan(offset: valueOffset + 84, length: 4))
    }

    func testPhysicalHeaderKindDoesNotDependOnCorruptThisPartition() throws {
        var data = Data(repeating: 0, count: 88)
        try data.checkedWriteUInt64BE(9_999, at: 8)
        let result = inspector.inspect(
            key: key(kind: 2, status: 3), keySpan: try ByteSpan(offset: 400, length: 16),
            valueSpan: try ByteSpan(offset: 0, length: 88), in: data
        )
        guard case .partitionPack(let pack) = result else { return XCTFail("not parsed") }
        XCTAssertEqual(pack.keyClassification.kind, .header)
        XCTAssertEqual(pack.thisPartition.value, 9_999)
    }

    func testDistinguishesEachTruncatedFixedField() throws {
        let boundaries: [(Int, MXFPartitionFixedField)] = [
            (0, .majorVersion), (2, .minorVersion), (4, .kagSize), (8, .thisPartition),
            (16, .previousPartition), (24, .footerPartition), (32, .headerByteCount),
            (40, .indexByteCount), (48, .indexSID), (52, .bodyOffset), (60, .bodySID),
            (64, .operationalPattern), (80, .essenceContainerCount),
            (84, .essenceContainerElementSize)
        ]
        for (available, expectedField) in boundaries {
            let valueOffset: UInt64 = 20
            let data = Data(repeating: 0, count: Int(valueOffset) + available)
            let result = inspector.inspect(
                key: key(), keySpan: try ByteSpan(offset: 0, length: 16),
                valueSpan: try ByteSpan(offset: valueOffset, length: UInt64(max(available, 1))),
                in: data
            )
            if available == 0 {
                // A nonempty ByteSpan cannot express a declared zero-length value; exercise that
                // boundary through a structurally inspected zero-value KLV instead.
                let structural = MXFStructuralInspector().inspect(data: key() + Data([0]))
                XCTAssertEqual(inspector.inspect(element: structural.elements[0], in: key() + Data([0])),
                               .invalid(.truncatedFixedField(
                                field: .majorVersion,
                                requiredSpan: try ByteSpan(offset: 17, length: 2),
                                availableValueSpan: nil
                               )))
            } else if case .invalid(.truncatedFixedField(let field, _, _)) = result {
                XCTAssertEqual(field, expectedField, "available \(available)")
            } else {
                XCTFail("expected truncation for \(available), got \(result)")
            }
        }
    }

    func testFileInspectionReadsOnlyFixedPrefixAndKeepsPhysicalSpans() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MXFPartitionInspectorTests-\(UUID().uuidString)")
        var bytes = Data(repeating: 0, count: 128)
        try bytes.checkedWriteUInt64BE(77, at: 8)
        try bytes.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let result = try inspector.inspect(
            fileAt: url, key: key(kind: 4, status: 4),
            keySpan: ByteSpan(offset: 900, length: 16), valueOffset: 0,
            declaredValueLength: 128
        )
        guard case .partitionPack(let pack) = result else { return XCTFail("not parsed") }
        XCTAssertEqual(pack.keyClassification.kind, .footer)
        XCTAssertEqual(pack.thisPartition.value, 77)
        XCTAssertEqual(pack.thisPartition.span, try ByteSpan(offset: 8, length: 8))
        XCTAssertEqual(pack.valueSpan, try ByteSpan(offset: 0, length: 128))
    }

    private func key(kind: UInt8 = 2, status: UInt8 = 1) -> Data {
        Data([0x06, 0x0e, 0x2b, 0x34, 0x02, 0x05, 0x01, 0x01,
              0x0d, 0x01, 0x02, 0x01, 0x01, kind, status, 0x00])
    }
}
