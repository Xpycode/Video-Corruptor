import Foundation
import XCTest
@testable import VideoCorruptor

final class MXFBERTests: XCTestCase {
    func testDecodesShortFormAndMetadataAtNonzeroOffset() throws {
        let result = try MXFBER.decodeLength(
            from: Data([0xff, 0x7f]),
            at: 1,
            maximumValue: 1_000
        )

        XCTAssertEqual(result.value, 127)
        XCTAssertEqual(result.encodedWidth, 1)
        XCTAssertEqual(result.physicalSpan, try ByteSpan(lowerBound: 1, upperBound: 2))
        XCTAssertEqual(result.form, .short)
        XCTAssertEqual(result.canonicality, .canonical)
        XCTAssertEqual(result.diagnostics, [])
    }

    func testDecodesCanonicalLongForm() throws {
        let result = try MXFBER.decodeLength(
            from: Data([0x82, 0x01, 0x00]),
            at: 0,
            maximumValue: 1_000
        )

        XCTAssertEqual(result.value, 256)
        XCTAssertEqual(result.encodedWidth, 3)
        XCTAssertEqual(result.physicalSpan, try ByteSpan(lowerBound: 0, upperBound: 3))
        XCTAssertEqual(result.form, .long(lengthOctetCount: 2))
        XCTAssertEqual(result.canonicality, .canonical)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    func testRejectsReservedIndefiniteForm() {
        assertError(Data([0x80]), maximumValue: .max, equals: .reservedIndefiniteForm(offset: 0))
    }

    func testRejectsExcessiveLengthOfLengthBeforeReadingPayload() {
        assertError(
            Data([0x89]),
            maximumValue: .max,
            equals: .excessiveLengthOfLength(offset: 0, lengthOctetCount: 9, maximum: 8)
        )
    }

    func testRejectsTruncatedLongFormHeader() {
        assertError(
            Data([0xaa, 0x83, 0x01]),
            at: 1,
            maximumValue: .max,
            equals: .truncatedHeader(offset: 1, requiredWidth: 4, availableWidth: 2)
        )
    }

    func testRejectsMissingFirstOctet() {
        assertError(
            Data(),
            maximumValue: .max,
            equals: .truncatedHeader(offset: 0, requiredWidth: 1, availableWidth: 0)
        )
    }

    func testValidNonMinimalSmallValueDecodesWithWarning() throws {
        let result = try MXFBER.decodeLength(
            from: Data([0x81, 0x7f]),
            at: 0,
            maximumValue: .max
        )

        XCTAssertEqual(result.value, 127)
        XCTAssertEqual(result.canonicality, .nonCanonical)
        XCTAssertEqual(result.diagnostics, [
            .nonMinimalLongForm(minimumLengthOctetCount: 1, actualLengthOctetCount: 1)
        ])
    }

    func testLeadingZeroLongFormDecodesWithTypedWarnings() throws {
        let result = try MXFBER.decodeLength(
            from: Data([0x82, 0x00, 0x80]),
            at: 0,
            maximumValue: .max
        )

        XCTAssertEqual(result.value, 128)
        XCTAssertEqual(result.canonicality, .nonCanonical)
        XCTAssertEqual(result.diagnostics, [
            .leadingZeroLengthOctet,
            .nonMinimalLongForm(minimumLengthOctetCount: 1, actualLengthOctetCount: 2)
        ])
    }

    func testDecodesMaximumUInt64WithoutOverflow() throws {
        let result = try MXFBER.decodeLength(
            from: Data([0x88] + Array(repeating: 0xff, count: 8)),
            at: 0,
            maximumValue: .max
        )
        XCTAssertEqual(result.value, .max)
        XCTAssertEqual(result.canonicality, .canonical)
    }

    func testRejectsConfiguredLengthLimitForShortAndLongForms() {
        assertError(
            Data([0x7f]),
            maximumValue: 126,
            equals: .lengthLimitExceeded(value: 127, limit: 126)
        )
        assertError(
            Data([0x82, 0x01, 0x00]),
            maximumValue: 255,
            equals: .lengthLimitExceeded(value: 256, limit: 255)
        )
    }

    private func assertError(
        _ data: Data,
        at offset: UInt64 = 0,
        maximumValue: UInt64,
        equals expected: MXFBERError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try MXFBER.decodeLength(from: data, at: offset, maximumValue: maximumValue),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? MXFBERError, expected, file: file, line: line)
        }
    }
}
