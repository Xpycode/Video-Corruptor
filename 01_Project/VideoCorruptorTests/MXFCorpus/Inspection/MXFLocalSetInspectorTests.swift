import Foundation
import XCTest
@testable import VideoCorruptor

final class MXFLocalSetInspectorTests: XCTestCase {
    private let inspector = MXFLocalSetInspector()

    func testParsesItemsAndReportsExactPhysicalSpans() throws {
        let data = Data([0xff, 0x01, 0x02, 0x03, 0xaa, 0xbb, 0xcc, 0x10, 0x20, 0x00, 0xee])
        let span = try ByteSpan(lowerBound: 1, upperBound: 10)

        let result = inspector.inspect(data: data, enclosingSpan: span)

        XCTAssertTrue(result.completedWalk)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.items.count, 2)
        guard result.items.count == 2 else { return }
        XCTAssertEqual(result.items[0].tag, 0x0102)
        XCTAssertEqual(result.items[0].tagSpan, try ByteSpan(lowerBound: 1, upperBound: 3))
        XCTAssertEqual(result.items[0].ber.physicalSpan, try ByteSpan(lowerBound: 3, upperBound: 4))
        XCTAssertEqual(result.items[0].valueSpan, try ByteSpan(lowerBound: 4, upperBound: 7))
        XCTAssertEqual(result.items[0].physicalSpan, try ByteSpan(lowerBound: 1, upperBound: 7))
        XCTAssertEqual(result.items[1].tag, 0x1020)
        XCTAssertNil(result.items[1].valueSpan)
        XCTAssertEqual(result.items[1].physicalSpan, try ByteSpan(lowerBound: 7, upperBound: 10))
    }

    func testResolvesOnlyExplicitPrimerMappings() throws {
        let label = Data((0..<16).map(UInt8.init))
        let primer = try MXFPrimerMap(mappings: [0x3f0a: label])
        let data = Data([0x3f, 0x0a, 0x00, 0x3f, 0x0b, 0x00])

        let result = inspector.inspect(
            data: data,
            enclosingSpan: try ByteSpan(lowerBound: 0, upperBound: 6),
            primerMap: primer
        )

        XCTAssertEqual(result.items.count, 2)
        guard result.items.count == 2 else { return }
        XCTAssertEqual(result.items[0].resolvedUniversalLabel, label)
        XCTAssertNil(result.items[1].resolvedUniversalLabel)
    }

    func testRejectsPrimerLabelsThatAreNotSixteenBytes() {
        XCTAssertThrowsError(try MXFPrimerMap(mappings: [1: Data(repeating: 0, count: 15)])) {
            XCTAssertEqual($0 as? MXFPrimerMapError, .invalidUniversalLabelWidth(
                tag: 1,
                actual: 15,
                required: 16
            ))
        }
    }

    func testBERAndValueCannotEscapeEnclosingSpan() throws {
        let truncatedBER = Data([0x01, 0x02, 0x82, 0x00, 0xff])
        let berResult = inspector.inspect(
            data: truncatedBER,
            enclosingSpan: try ByteSpan(lowerBound: 0, upperBound: 4)
        )
        XCTAssertEqual(berResult.error, .malformedBER(
            offset: 2,
            error: .truncatedHeader(offset: 2, requiredWidth: 3, availableWidth: 2)
        ))

        let excessiveValue = Data([0x01, 0x02, 0x05, 0xaa, 0xbb, 0xcc])
        let valueResult = inspector.inspect(
            data: excessiveValue,
            enclosingSpan: try ByteSpan(lowerBound: 0, upperBound: 6)
        )
        XCTAssertEqual(valueResult.error, .itemExceedsEnclosingValue(
            tag: 0x0102,
            valueOffset: 3,
            declaredByteCount: 5,
            availableByteCount: 3
        ))
    }

    func testStopsBeforeItemCountCouldDriveUntrustedAllocation() throws {
        let data = Data([0x00, 0x01, 0x00, 0x00, 0x02, 0x00])
        let result = inspector.inspect(
            data: data,
            enclosingSpan: try ByteSpan(lowerBound: 0, upperBound: 6),
            maximumItemCount: 1
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.error, .itemLimitExceeded(actual: 2, maximum: 1))
    }

    func testRejectsTruncatedTagAndSpanBeyondInput() throws {
        let truncated = inspector.inspect(
            data: Data([0x00]),
            enclosingSpan: try ByteSpan(lowerBound: 0, upperBound: 1)
        )
        XCTAssertEqual(truncated.error, .truncatedTag(offset: 0, availableByteCount: 1))

        let outside = try ByteSpan(lowerBound: 0, upperBound: 2)
        let outsideResult = inspector.inspect(data: Data([0]), enclosingSpan: outside)
        XCTAssertEqual(outsideResult.error, .enclosingSpanOutsideInput(
            span: outside,
            inputByteCount: 1
        ))
    }
}
