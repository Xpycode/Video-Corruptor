import XCTest
@testable import VideoCorruptor

final class CheckedBinaryArithmeticTests: XCTestCase {
    func testCheckedAdditionAcceptsBoundaries() throws {
        XCTAssertEqual(try CheckedBinaryArithmetic.add(0, 0), 0)
        XCTAssertEqual(try CheckedBinaryArithmetic.add(UInt64.max, 0), UInt64.max)
    }

    func testCheckedAdditionThrowsTypedOverflow() {
        XCTAssertThrowsError(try CheckedBinaryArithmetic.add(UInt64.max, 1)) { error in
            XCTAssertEqual(
                error as? CheckedBinaryError,
                .additionOverflow(lhs: UInt64.max, rhs: 1)
            )
        }
    }

    func testCheckedMultiplicationAcceptsZeroAndBoundary() throws {
        XCTAssertEqual(try CheckedBinaryArithmetic.multiply(UInt64.max, 0), 0)
        XCTAssertEqual(try CheckedBinaryArithmetic.multiply(UInt64.max, 1), UInt64.max)
    }

    func testCheckedMultiplicationThrowsTypedOverflow() {
        XCTAssertThrowsError(try CheckedBinaryArithmetic.multiply(UInt64.max, 2)) { error in
            XCTAssertEqual(
                error as? CheckedBinaryError,
                .multiplicationOverflow(lhs: UInt64.max, rhs: 2)
            )
        }
    }

    func testUInt64ToIntConversionIsExact() throws {
        XCTAssertEqual(try CheckedBinaryArithmetic.int(exactly: 0), 0)
        XCTAssertEqual(
            try CheckedBinaryArithmetic.int(exactly: UInt64(Int.max)),
            Int.max
        )

        let tooLarge = UInt64(Int.max) + 1
        XCTAssertThrowsError(try CheckedBinaryArithmetic.int(exactly: tooLarge)) { error in
            XCTAssertEqual(error as? CheckedBinaryError, .uint64DoesNotFitInt(tooLarge))
        }
        XCTAssertThrowsError(try CheckedBinaryArithmetic.int(exactly: UInt64.max)) { error in
            XCTAssertEqual(error as? CheckedBinaryError, .uint64DoesNotFitInt(UInt64.max))
        }
    }

    func testIntToUInt64ConversionIsExact() throws {
        XCTAssertEqual(try CheckedBinaryArithmetic.uint64(exactly: 0), 0)
        XCTAssertEqual(
            try CheckedBinaryArithmetic.uint64(exactly: Int.max),
            UInt64(Int.max)
        )
        XCTAssertThrowsError(try CheckedBinaryArithmetic.uint64(exactly: -1)) { error in
            XCTAssertEqual(error as? CheckedBinaryError, .negativeIntDoesNotFitUInt64(-1))
        }
        XCTAssertThrowsError(try CheckedBinaryArithmetic.uint64(exactly: Int.min)) { error in
            XCTAssertEqual(error as? CheckedBinaryError, .negativeIntDoesNotFitUInt64(Int.min))
        }
    }

    func testSpanIsNonemptyAndHalfOpen() throws {
        let span = try ByteSpan(offset: 10, length: 5)

        XCTAssertEqual(span.lowerBound, 10)
        XCTAssertEqual(span.upperBound, 15)
        XCTAssertEqual(span.length, 5)
        XCTAssertEqual(span.range, 10..<15)
        XCTAssertTrue(span.contains(10))
        XCTAssertTrue(span.contains(14))
        XCTAssertFalse(span.contains(15))
    }

    func testSpanCanEndAtEOFBoundary() throws {
        let span = try ByteSpan(offset: UInt64.max - 1, length: 1)

        XCTAssertEqual(span.upperBound, UInt64.max)
        XCTAssertTrue(span.contains(UInt64.max - 1))
        XCTAssertFalse(span.contains(UInt64.max))
    }

    func testEmptyAndInvalidSpansThrowTypedErrors() {
        XCTAssertThrowsError(try ByteSpan(offset: 7, length: 0)) { error in
            XCTAssertEqual(error as? CheckedBinaryError, .emptySpan(offset: 7))
        }
        XCTAssertThrowsError(try ByteSpan(lowerBound: 7, upperBound: 7)) { error in
            XCTAssertEqual(error as? CheckedBinaryError, .emptySpan(offset: 7))
        }
        XCTAssertThrowsError(try ByteSpan(lowerBound: 8, upperBound: 7)) { error in
            XCTAssertEqual(
                error as? CheckedBinaryError,
                .invalidSpanBounds(lowerBound: 8, upperBound: 7)
            )
        }
        XCTAssertThrowsError(try ByteSpan(offset: UInt64.max, length: 1)) { error in
            XCTAssertEqual(
                error as? CheckedBinaryError,
                .additionOverflow(lhs: UInt64.max, rhs: 1)
            )
        }
    }

    func testSpanContainment() throws {
        let outer = try ByteSpan(offset: 10, length: 10)

        XCTAssertTrue(outer.contains(try ByteSpan(offset: 10, length: 10)))
        XCTAssertTrue(outer.contains(try ByteSpan(offset: 12, length: 3)))
        XCTAssertFalse(outer.contains(try ByteSpan(offset: 9, length: 3)))
        XCTAssertFalse(outer.contains(try ByteSpan(offset: 19, length: 2)))
    }

    func testSpanOverlapExcludesAdjacency() throws {
        let span = try ByteSpan(offset: 10, length: 10)

        XCTAssertTrue(span.overlaps(try ByteSpan(offset: 5, length: 6)))
        XCTAssertTrue(span.overlaps(try ByteSpan(offset: 19, length: 2)))
        XCTAssertTrue(span.overlaps(try ByteSpan(offset: 10, length: 10)))
        XCTAssertFalse(span.overlaps(try ByteSpan(offset: 0, length: 10)))
        XCTAssertFalse(span.overlaps(try ByteSpan(offset: 20, length: 1)))
    }
}
