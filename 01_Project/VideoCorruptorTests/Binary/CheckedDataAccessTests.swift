import Foundation
import XCTest
@testable import VideoCorruptor

final class CheckedDataAccessTests: XCTestCase {
    private let bytes = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])

    func testBigEndianReadsAtStartAndExactEOF() throws {
        XCTAssertEqual(try bytes.checkedUInt16BE(at: 0), 0x0123)
        XCTAssertEqual(try bytes.checkedUInt16BE(at: 6), 0xCDEF)
        XCTAssertEqual(try bytes.checkedUInt32BE(at: 0), 0x01234567)
        XCTAssertEqual(try bytes.checkedUInt32BE(at: 4), 0x89ABCDEF)
        XCTAssertEqual(try bytes.checkedUInt64BE(at: 0), 0x0123456789ABCDEF)
    }

    func testReadsAroundEOFThrowTypedBoundsErrors() throws {
        try assertOutOfBounds(available: 8, offset: 7, length: 2) {
            _ = try bytes.checkedUInt16BE(at: 7)
        }
        try assertOutOfBounds(available: 8, offset: 8, length: 2) {
            _ = try bytes.checkedUInt16BE(at: 8)
        }
        try assertOutOfBounds(available: 8, offset: 5, length: 4) {
            _ = try bytes.checkedUInt32BE(at: 5)
        }
        try assertOutOfBounds(available: 8, offset: 1, length: 8) {
            _ = try bytes.checkedUInt64BE(at: 1)
        }
    }

    func testOverflowingReadOffsetThrowsArithmeticError() {
        XCTAssertThrowsError(try bytes.checkedUInt64BE(at: UInt64.max)) { error in
            XCTAssertEqual(
                error as? CheckedBinaryError,
                .additionOverflow(lhs: UInt64.max, rhs: 8)
            )
        }
    }

    func testExactByteSliceAtEOF() throws {
        XCTAssertEqual(
            try bytes.checkedBytes(in: ByteSpan(offset: 2, length: 3)),
            Data([0x45, 0x67, 0x89])
        )
        XCTAssertEqual(
            try bytes.checkedBytes(in: ByteSpan(offset: 6, length: 2)),
            Data([0xCD, 0xEF])
        )
    }

    func testByteSlicePastEOFThrowsTypedBoundsError() throws {
        let span = try ByteSpan(offset: 7, length: 2)
        XCTAssertThrowsError(try bytes.checkedBytes(in: span)) { error in
            XCTAssertEqual(
                error as? CheckedDataAccessError,
                .outOfBounds(requested: span, availableByteCount: 8)
            )
        }
    }

    func testBigEndianWritesAtStartAndExactEOF() throws {
        var data = Data(repeating: 0, count: 16)

        try data.checkedWriteUInt16BE(0x0123, at: 0)
        try data.checkedWriteUInt32BE(0x456789AB, at: 2)
        try data.checkedWriteUInt64BE(0xCDEF0123456789AB, at: 8)

        XCTAssertEqual(
            data,
            Data([
                0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0x00, 0x00,
                0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB,
            ])
        )
    }

    func testFailedWritesDoNotMutateData() throws {
        var data = bytes
        let original = data

        try assertOutOfBounds(available: 8, offset: 7, length: 2) {
            try data.checkedWriteUInt16BE(0, at: 7)
        }
        try assertOutOfBounds(available: 8, offset: 8, length: 4) {
            try data.checkedWriteUInt32BE(0, at: 8)
        }
        try assertOutOfBounds(available: 8, offset: 1, length: 8) {
            try data.checkedWriteUInt64BE(0, at: 1)
        }

        XCTAssertEqual(data, original)
    }

    func testExactByteWriteAndLengthMismatch() throws {
        var data = bytes
        let span = try ByteSpan(offset: 2, length: 3)

        try data.checkedWriteBytes(Data([0xAA, 0xBB, 0xCC]), in: span)
        XCTAssertEqual(data, Data([0x01, 0x23, 0xAA, 0xBB, 0xCC, 0xAB, 0xCD, 0xEF]))

        let beforeMismatch = data
        XCTAssertThrowsError(try data.checkedWriteBytes(Data([0x00, 0x01]), in: span)) { error in
            XCTAssertEqual(
                error as? CheckedDataAccessError,
                .replacementLengthMismatch(expected: 3, actual: 2)
            )
        }
        XCTAssertEqual(data, beforeMismatch)
    }

    func testExactByteWritePastEOFDoesNotMutateData() throws {
        var data = bytes
        let original = data
        let span = try ByteSpan(offset: 7, length: 2)

        XCTAssertThrowsError(try data.checkedWriteBytes(Data([0, 0]), in: span)) { error in
            XCTAssertEqual(
                error as? CheckedDataAccessError,
                .outOfBounds(requested: span, availableByteCount: 8)
            )
        }
        XCTAssertEqual(data, original)
    }

    private func assertOutOfBounds(
        available: UInt64,
        offset: UInt64,
        length: UInt64,
        operation: () throws -> Void
    ) throws {
        let span = try ByteSpan(offset: offset, length: length)
        XCTAssertThrowsError(try operation()) { error in
            XCTAssertEqual(
                error as? CheckedDataAccessError,
                .outOfBounds(requested: span, availableByteCount: available)
            )
        }
    }
}
