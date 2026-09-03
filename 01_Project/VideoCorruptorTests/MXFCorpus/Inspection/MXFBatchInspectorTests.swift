import Foundation
import XCTest
@testable import VideoCorruptor

final class MXFBatchInspectorTests: XCTestCase {
    private let inspector = MXFBatchInspector()

    func testParsesHeaderAndReportsExactPhysicalSpans() throws {
        var data = Data(repeating: 0xee, count: 40)
        try data.checkedWriteUInt32BE(3, at: 10)
        try data.checkedWriteUInt32BE(4, at: 14)

        let result = inspector.inspect(
            batchSpan: try ByteSpan(offset: 10, length: 20), in: data
        )
        guard case .batch(let batch) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(batch.header.count, .init(value: 3, span: try ByteSpan(offset: 10, length: 4)))
        XCTAssertEqual(batch.header.itemSize, .init(value: 4, span: try ByteSpan(offset: 14, length: 4)))
        XCTAssertEqual(batch.header.span, try ByteSpan(offset: 10, length: 8))
        XCTAssertEqual(batch.payloadByteCount, 12)
        XCTAssertEqual(batch.payloadSpan, try ByteSpan(offset: 18, length: 12))
    }

    func testReportsLogicalAndPhysicalHeaderTruncation() throws {
        let data = Data(repeating: 0, count: 20)
        XCTAssertEqual(
            inspector.inspect(batchSpan: try ByteSpan(offset: 10, length: 6), in: data),
            .invalid(.truncatedHeader(
                requiredSpan: try ByteSpan(offset: 10, length: 8),
                availableSpan: try ByteSpan(offset: 10, length: 6)
            ))
        )
        XCTAssertEqual(
            inspector.inspect(batchSpan: try ByteSpan(offset: 17, length: 12), in: data),
            .invalid(.truncatedHeader(
                requiredSpan: try ByteSpan(offset: 17, length: 8),
                availableSpan: try ByteSpan(offset: 17, length: 3)
            ))
        )
    }

    func testRejectsZeroItemSizeWithNonzeroCountBeforePayloadMath() throws {
        let header = try makeHeader(count: 2, itemSize: 0)
        XCTAssertEqual(
            inspector.validate(header: header, enclosingPayloadByteCount: 0,
                               physicalPayloadByteCount: 0),
            .invalid(.zeroItemSizeWithNonzeroCount(header: header))
        )
    }

    func testReportsCheckedUInt64MultiplicationOverflow() throws {
        let header = try makeHeader(count: UInt64.max, itemSize: 2)
        XCTAssertEqual(
            inspector.validate(header: header, enclosingPayloadByteCount: UInt64.max,
                               physicalPayloadByteCount: UInt64.max),
            .invalid(.multiplicationOverflow(header: header))
        )
    }

    func testAppliesCountAndAllocationLimitsBeforeConstructingPayloadSpan() throws {
        let countHeader = try makeHeader(count: 11, itemSize: 1)
        let countLimits = MXFInspectionLimits(maximumElementCount: 10)
        XCTAssertEqual(
            inspector.validate(header: countHeader, enclosingPayloadByteCount: 100,
                               physicalPayloadByteCount: 100, limits: countLimits),
            .invalid(.limitExceeded(header: countHeader, limit: .elementCount,
                                    actual: 11, maximum: 10))
        )

        let allocationHeader = try makeHeader(count: 3, itemSize: 4)
        let allocationLimits = MXFInspectionLimits(maximumElementCount: 10,
                                                   maximumAllocationBytes: 11)
        XCTAssertEqual(
            inspector.validate(header: allocationHeader, enclosingPayloadByteCount: 100,
                               physicalPayloadByteCount: 100, limits: allocationLimits),
            .invalid(.limitExceeded(header: allocationHeader, limit: .allocationBytes,
                                    actual: 12, maximum: 11))
        )
    }

    func testReportsPayloadExceedanceWithBoundedAvailablePhysicalSpan() throws {
        var data = Data(repeating: 0, count: 15)
        try data.checkedWriteUInt32BE(2, at: 0)
        try data.checkedWriteUInt32BE(4, at: 4)
        let header = try makeHeader(count: 2, itemSize: 4)

        XCTAssertEqual(
            inspector.inspect(batchSpan: try ByteSpan(offset: 0, length: 20), in: data),
            .invalid(.payloadExceedsEnclosingSpan(
                header: header, declaredByteCount: 8, availableByteCount: 7,
                availableSpan: try ByteSpan(offset: 8, length: 7)
            ))
        )
    }

    func testZeroCountAndZeroItemSizeProducesEmptyPayloadWithoutRange() throws {
        let header = try makeHeader(count: 0, itemSize: 0)
        XCTAssertEqual(
            inspector.validate(header: header, enclosingPayloadByteCount: 0,
                               physicalPayloadByteCount: 0),
            .batch(.init(header: header, payloadSpan: nil, payloadByteCount: 0))
        )
    }

    private func makeHeader(count: UInt64, itemSize: UInt64) throws -> MXFBatchHeader {
        try MXFBatchHeader(
            count: .init(value: count, span: try ByteSpan(offset: 0, length: 4)),
            itemSize: .init(value: itemSize, span: try ByteSpan(offset: 4, length: 4))
        )
    }
}
