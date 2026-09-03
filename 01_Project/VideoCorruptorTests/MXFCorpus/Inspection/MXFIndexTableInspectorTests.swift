import Foundation
import XCTest
@testable import VideoCorruptor

final class MXFIndexTableInspectorTests: XCTestCase {
    private let inspector = MXFIndexTableInspector()
    private let tags: [UInt16: MXFIndexTableField] = [
        0x0101: .indexEditRate, 0x0102: .indexSID, 0x0103: .bodySID,
        0x0104: .sliceCount, 0x0105: .deltaEntryArray, 0x0106: .indexEntryArray
    ]

    func testInspectsRequiredFieldsAndExactPhysicalSpans() throws {
        let fixture = makeFixture(offsets: [4, 20])
        let result = inspector.inspect(
            data: fixture.data, setSpan: fixture.span,
            schema: try MXFIndexTableFieldSchema(tags: tags)
        )
        guard case .indexTable(let table) = result else { return XCTFail("got \(result)") }

        XCTAssertEqual(table.indexEditRate.numerator, 25)
        XCTAssertEqual(table.indexEditRate.denominator, 1)
        XCTAssertEqual(table.indexEditRate.numeratorSpan, try ByteSpan(offset: 3, length: 4))
        XCTAssertEqual(table.indexEditRate.denominatorSpan, try ByteSpan(offset: 7, length: 4))
        XCTAssertEqual(table.indexEditRate.setItem.physicalSpan, try ByteSpan(offset: 0, length: 11))
        XCTAssertEqual(table.indexSID.value, 7)
        XCTAssertEqual(table.bodySID.value, 9)
        XCTAssertEqual(table.sliceCount.value, 0)
        XCTAssertEqual(table.deltaEntryArray.batch.header.count.value, 1)
        XCTAssertEqual(table.indexEntryArray.batch.header.count.value, 2)
        XCTAssertEqual(table.streamOffsets.map(\.value), [4, 20])
        XCTAssertEqual(table.streamOffsets[0].fieldSpan, try ByteSpan(offset: 60, length: 8))
        XCTAssertEqual(table.streamOffsets[0].entrySpan, try ByteSpan(offset: 57, length: 11))
    }

    func testUsesOnlyExplicitSchemaAndReportsMissingField() throws {
        var schema = tags
        schema.removeValue(forKey: 0x0102)
        XCTAssertEqual(
            inspector.inspect(
                data: makeFixture().data, setSpan: makeFixture().span,
                schema: try MXFIndexTableFieldSchema(tags: schema)
            ),
            .invalid(.missingField(.indexSID))
        )
    }

    func testReportsWrongWidthAndZeroDenominatorWithPhysicalSpans() throws {
        let wrongWidth = makeFixture(indexSID: Data([0, 0, 7]))
        XCTAssertEqual(
            inspector.inspect(data: wrongWidth.data, setSpan: wrongWidth.span,
                              schema: try MXFIndexTableFieldSchema(tags: tags)),
            .invalid(.wrongWidth(
                field: .indexSID, expected: 4, actual: 3,
                valueSpan: try ByteSpan(offset: 14, length: 3)
            ))
        )

        let zeroRate = makeFixture(denominator: 0)
        XCTAssertEqual(
            inspector.inspect(data: zeroRate.data, setSpan: zeroRate.span,
                              schema: try MXFIndexTableFieldSchema(tags: tags)),
            .invalid(.zeroEditRateDenominator(span: try ByteSpan(offset: 7, length: 4)))
        )
    }

    func testRejectsEntryCountBeyondPayloadBeforeEntryWalk() throws {
        let fixture = makeFixture(offsets: [4], declaredEntryCount: 100)
        let result = inspector.inspect(
            data: fixture.data, setSpan: fixture.span,
            schema: try MXFIndexTableFieldSchema(tags: tags)
        )
        guard case .invalid(.invalidBatch(field: .indexEntryArray, error: let error)) = result,
              case .payloadExceedsEnclosingSpan(let header, let declared, let available, _) = error else {
            return XCTFail("got \(result)")
        }
        XCTAssertEqual(header.count.value, 100)
        XCTAssertEqual(declared, 1_100)
        XCTAssertEqual(available, 11)
    }

    func testReportsTruncatedIndexArrayHeaderAtItsValueSpan() throws {
        let fixture = makeFixture(indexEntryValue: Data([0, 0, 0, 1]))
        let result = inspector.inspect(
            data: fixture.data, setSpan: fixture.span,
            schema: try MXFIndexTableFieldSchema(tags: tags)
        )
        guard case .invalid(.invalidBatch(field: .indexEntryArray,
                                          error: .truncatedHeader(let required, let available))) = result else {
            return XCTFail("got \(result)")
        }
        XCTAssertEqual(required.length, 8)
        XCTAssertEqual(available?.length, 4)
    }

    func testEnforcesSliceDeltaAndEntryCountLimitsBeforeAllocation() throws {
        let slice = makeFixture(sliceCount: 5, entryItemSize: 31)
        XCTAssertEqual(
            inspector.inspect(data: slice.data, setSpan: slice.span,
                              schema: try MXFIndexTableFieldSchema(tags: tags), maximumSliceCount: 4),
            .invalid(.sliceCountLimitExceeded(
                actual: 5, maximum: 4, span: try ByteSpan(offset: 28, length: 1)
            ))
        )

        let delta = makeFixture(deltaCount: 5)
        let result = inspector.inspect(
            data: delta.data, setSpan: delta.span,
            schema: try MXFIndexTableFieldSchema(tags: tags), maximumDeltaCount: 4
        )
        guard case .invalid(.deltaCountLimitExceeded(let actual, let maximum, let span)) = result else {
            return XCTFail("got \(result)")
        }
        XCTAssertEqual(actual, 5)
        XCTAssertEqual(maximum, 4)
        XCTAssertEqual(span.length, 4)

        let entries = makeFixture(offsets: [4], declaredEntryCount: 7)
        let limited = inspector.inspect(
            data: entries.data, setSpan: entries.span,
            schema: try MXFIndexTableFieldSchema(tags: tags),
            limits: MXFInspectionLimits(maximumElementCount: 6)
        )
        guard case .invalid(.invalidBatch(field: .indexEntryArray,
                                          error: .limitExceeded(_, .elementCount, 7, 6))) = limited else {
            return XCTFail("got \(limited)")
        }
    }

    func testReportsSIDAndStreamOffsetRelationshipsAtExactField() throws {
        let fixture = makeFixture(offsets: [4, 4])
        XCTAssertEqual(
            inspector.inspect(
                data: fixture.data, setSpan: fixture.span,
                schema: try MXFIndexTableFieldSchema(tags: tags),
                relationships: .init(expectedIndexSID: 8)
            ),
            .invalid(.indexSIDMismatch(
                actual: 7, expected: 8, span: try ByteSpan(offset: 14, length: 4)
            ))
        )

        let duplicate = inspector.inspect(
            data: fixture.data, setSpan: fixture.span,
            schema: try MXFIndexTableFieldSchema(tags: tags)
        )
        guard case .invalid(.nonIncreasingStreamOffset(let index, 4, 4, let span)) = duplicate else {
            return XCTFail("got \(duplicate)")
        }
        XCTAssertEqual(index, 1)
        XCTAssertEqual(span.length, 8)

        let outside = makeFixture(offsets: [40])
        let outsideResult = inspector.inspect(
            data: outside.data, setSpan: outside.span,
            schema: try MXFIndexTableFieldSchema(tags: tags),
            relationships: .init(essenceStreamSpan: try ByteSpan(offset: 500, length: 32))
        )
        guard case .invalid(.streamOffsetOutsideEssence(0, 40, let span, let essence)) = outsideResult else {
            return XCTFail("got \(outsideResult)")
        }
        XCTAssertEqual(span.length, 8)
        XCTAssertEqual(essence, try ByteSpan(offset: 500, length: 32))
    }

    private func makeFixture(
        denominator: UInt32 = 1,
        indexSID: Data = be32(7),
        sliceCount: UInt8 = 0,
        deltaCount: UInt32 = 1,
        entryItemSize: UInt32 = 11,
        offsets: [UInt64] = [4, 20],
        declaredEntryCount: UInt32? = nil,
        indexEntryValue: Data? = nil
    ) -> (data: Data, span: ByteSpan) {
        var data = Data()
        appendItem(0x0101, be32(25) + be32(denominator), to: &data)
        appendItem(0x0102, indexSID, to: &data)
        appendItem(0x0103, be32(9), to: &data)
        appendItem(0x0104, Data([sliceCount]), to: &data)

        var delta = be32(deltaCount) + be32(6)
        delta += Data(repeating: 0, count: Int(deltaCount) * 6)
        appendItem(0x0105, delta, to: &data)

        var entries = be32(declaredEntryCount ?? UInt32(offsets.count)) + be32(entryItemSize)
        for offset in offsets {
            var entry = Data(repeating: 0, count: Int(entryItemSize))
            if entry.count >= 11 {
                entry.replaceSubrange(3..<11, with: be64(offset))
            }
            entries += entry
        }
        appendItem(0x0106, indexEntryValue ?? entries, to: &data)
        return (data, try! ByteSpan(offset: 0, length: UInt64(data.count)))
    }

    private func appendItem(_ tag: UInt16, _ value: Data, to data: inout Data) {
        data += Data([UInt8(tag >> 8), UInt8(tag & 0xff), UInt8(value.count)])
        data += value
    }

}

private func be32(_ value: UInt32) -> Data {
    Data([UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value)])
}

private func be64(_ value: UInt64) -> Data {
    Data((0..<8).reversed().map { UInt8(value >> UInt64($0 * 8)) })
}
