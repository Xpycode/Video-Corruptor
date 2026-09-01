import Foundation
import XCTest
@testable import VideoCorruptor

final class MXFStructuralInspectorTests: XCTestCase {
    private let inspector = MXFStructuralInspector()

    func testWalksCompleteElementsOnlyFromTrustedBoundaries() throws {
        let firstKey = Data(repeating: 0x11, count: 16)
        let secondKey = Data(repeating: 0x22, count: 16)
        let data = Data([0xaa, 0xbb])
            + firstKey + Data([0x02, 0x01, 0x02])
            + secondKey + Data([0x00])

        let result = inspector.inspect(data: data, trustedStartOffset: 2)

        XCTAssertTrue(result.completedWalk)
        XCTAssertEqual(result.elements.count, 2)
        XCTAssertEqual(result.elements[0].key, firstKey)
        XCTAssertEqual(result.elements[0].keySpan, try ByteSpan(lowerBound: 2, upperBound: 18))
        XCTAssertEqual(result.elements[0].valueSpan, try ByteSpan(lowerBound: 19, upperBound: 21))
        XCTAssertEqual(result.elements[0].physicalSpan, try ByteSpan(lowerBound: 2, upperBound: 21))
        XCTAssertNil(result.elements[1].valueSpan)
        XCTAssertEqual(result.elements[1].physicalSpan, try ByteSpan(lowerBound: 21, upperBound: 38))
        XCTAssertEqual(result.counters, MXFInspectionCounters(
            candidateCount: 2,
            completeElementCount: 2,
            inspectedByteCount: 36
        ))
        XCTAssertEqual(result.diagnostics, [])
    }

    func testReportsTruncatedKeyAsPartialCandidate() throws {
        let result = inspector.inspect(data: Data(repeating: 0x44, count: 15))

        XCTAssertFalse(result.completedWalk)
        XCTAssertEqual(result.elements, [])
        XCTAssertEqual(
            result.partialElement,
            .truncatedKey(
                offset: 0,
                availableSpan: try ByteSpan(lowerBound: 0, upperBound: 15)
            )
        )
        XCTAssertEqual(result.diagnostics, [.truncatedKey(offset: 0, availableByteCount: 15)])
        XCTAssertEqual(result.counters.candidateCount, 1)
    }

    func testDistinguishesTruncatedBERHeader() throws {
        let data = key() + Data([0x83, 0x01])
        let result = inspector.inspect(data: data)

        XCTAssertEqual(result.elements, [])
        XCTAssertEqual(
            result.partialElement,
            .malformedBER(keySpan: try ByteSpan(lowerBound: 0, upperBound: 16), berOffset: 16)
        )
        XCTAssertEqual(result.diagnostics, [
            .malformedBER(
                offset: 16,
                error: .truncatedHeader(offset: 16, requiredWidth: 4, availableWidth: 2)
            )
        ])
    }

    func testMalformedBERIsReportedAndNeverSilentlyResynchronized() {
        let bytesAfterMalformedBER = key(0x99) + Data([0x00])
        let data = key() + Data([0x80]) + bytesAfterMalformedBER
        let result = inspector.inspect(data: data)

        XCTAssertFalse(result.completedWalk)
        XCTAssertTrue(result.elements.isEmpty)
        XCTAssertEqual(result.counters.candidateCount, 1)
        XCTAssertEqual(result.diagnostics, [
            .malformedBER(offset: 16, error: .reservedIndefiniteForm(offset: 16))
        ])
    }

    func testReportsTruncatedValueAndAvailablePhysicalSpan() throws {
        let data = key() + Data([0x05, 0xaa, 0xbb])
        let result = inspector.inspect(data: data)
        let expectedBER = try MXFBER.decodeLength(from: data, at: 16)

        XCTAssertEqual(result.elements, [])
        XCTAssertEqual(result.partialElement, .truncatedValue(
            keySpan: try ByteSpan(lowerBound: 0, upperBound: 16),
            ber: expectedBER,
            valueOffset: 17,
            availableValueSpan: try ByteSpan(lowerBound: 17, upperBound: 19)
        ))
        XCTAssertEqual(result.diagnostics, [
            .truncatedValue(offset: 17, declaredByteCount: 5, availableByteCount: 2)
        ])
    }

    func testNonCanonicalBERWarnsButWalkContinues() {
        let data = key() + Data([0x81, 0x01, 0xaa])
        let result = inspector.inspect(data: data)

        XCTAssertTrue(result.completedWalk)
        XCTAssertEqual(result.elements.count, 1)
        XCTAssertEqual(result.elements[0].ber.value, 1)
        XCTAssertEqual(result.diagnostics, [
            .nonCanonicalBER(
                offset: 16,
                diagnostic: .nonMinimalLongForm(
                    minimumLengthOctetCount: 1,
                    actualLengthOctetCount: 1
                )
            )
        ])
    }

    func testEnforcesInputElementBERAndAllocationLimits() {
        let oneElement = key() + Data([0x01, 0xaa])

        XCTAssertEqual(
            inspector.inspect(
                data: oneElement,
                limits: limits(maximumInputBytes: 17)
            ).diagnostics,
            [.limitExceeded(limit: .inputBytes, actual: 18, maximum: 17)]
        )

        let twoElements = oneElement + oneElement
        let elementLimited = inspector.inspect(
            data: twoElements,
            limits: limits(maximumElementCount: 1)
        )
        XCTAssertEqual(elementLimited.elements.count, 1)
        XCTAssertEqual(elementLimited.diagnostics, [
            .limitExceeded(limit: .elementCount, actual: 2, maximum: 1)
        ])

        XCTAssertEqual(
            inspector.inspect(
                data: key() + Data([0x0a]),
                limits: limits(maximumBERValueLength: 9)
            ).diagnostics,
            [.limitExceeded(limit: .berValueLength, actual: 10, maximum: 9)]
        )

        XCTAssertEqual(
            inspector.inspect(
                data: key() + Data([0x05]) + Data(repeating: 0, count: 5),
                limits: limits(maximumAllocationBytes: 4)
            ).diagnostics,
            [.limitExceeded(limit: .allocationBytes, actual: 16, maximum: 4)]
        )

        XCTAssertEqual(
            inspector.inspect(
                data: key() + Data([0x11]) + Data(repeating: 0, count: 17),
                limits: limits(maximumAllocationBytes: 16)
            ).diagnostics,
            [.limitExceeded(limit: .allocationBytes, actual: 17, maximum: 16)]
        )
    }

    func testHostileValueLengthCannotWrapEndpoint() {
        let data = key() + Data([0x88]) + Data(repeating: 0xff, count: 8)
        let result = inspector.inspect(data: data, limits: limits())

        XCTAssertFalse(result.completedWalk)
        XCTAssertEqual(result.elements, [])
        XCTAssertEqual(result.diagnostics, [
            .integerOverflow(offset: 25, operation: .valueEnd)
        ])
    }

    func testCancellationUsesNamedCheckpointAndPreservesPartialResults() {
        let oneElement = key() + Data([0x01, 0xaa])
        let result = inspector.inspect(
            data: oneElement + oneElement,
            shouldCancel: { checkpoint in
                checkpoint == .beforeElement(offset: 18)
            }
        )

        XCTAssertEqual(result.elements.count, 1)
        XCTAssertEqual(result.counters.completeElementCount, 1)
        XCTAssertEqual(result.diagnostics, [
            .cancelled(checkpoint: .beforeElement(offset: 18))
        ])
    }

    func testRejectsTrustedStartBeyondEOFButAllowsEOF() {
        let invalid = inspector.inspect(data: Data([0]), trustedStartOffset: 2)
        XCTAssertEqual(invalid.diagnostics, [
            .invalidTrustedStart(offset: 2, inputByteCount: 1)
        ])

        let eof = inspector.inspect(data: Data([0]), trustedStartOffset: 1)
        XCTAssertTrue(eof.completedWalk)
        XCTAssertEqual(eof.diagnostics, [])
    }

    private func key(_ byte: UInt8 = 0x11) -> Data {
        Data(repeating: byte, count: 16)
    }

    private func limits(
        maximumInputBytes: UInt64 = .max,
        maximumElementCount: UInt64 = .max,
        maximumBERValueLength: UInt64 = .max,
        maximumAllocationBytes: UInt64 = .max
    ) -> MXFInspectionLimits {
        MXFInspectionLimits(
            maximumInputBytes: maximumInputBytes,
            maximumElementCount: maximumElementCount,
            maximumBERValueLength: maximumBERValueLength,
            maximumAllocationBytes: maximumAllocationBytes
        )
    }
}
