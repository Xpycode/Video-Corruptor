import Foundation

struct MXFBatchField: Equatable, Sendable {
    let value: UInt64
    let span: ByteSpan
}

struct MXFBatchHeader: Equatable, Sendable {
    let count: MXFBatchField
    let itemSize: MXFBatchField
    let span: ByteSpan

    init(count: MXFBatchField, itemSize: MXFBatchField) throws {
        let expectedItemSizeOffset = try CheckedBinaryArithmetic.add(count.span.lowerBound, 4)
        guard count.span.length == 4,
              itemSize.span.length == 4,
              itemSize.span.lowerBound == expectedItemSizeOffset else {
            throw MXFBatchHeaderError.noncontiguousFields
        }
        self.count = count
        self.itemSize = itemSize
        self.span = try ByteSpan(lowerBound: count.span.lowerBound, upperBound: itemSize.span.upperBound)
    }
}

enum MXFBatchHeaderError: Error, Equatable, Sendable {
    case noncontiguousFields
}

struct MXFBatchInspection: Equatable, Sendable {
    let header: MXFBatchHeader
    let payloadSpan: ByteSpan?
    let payloadByteCount: UInt64
}

enum MXFBatchInspectionError: Error, Equatable, Sendable {
    case truncatedHeader(requiredSpan: ByteSpan, availableSpan: ByteSpan?)
    case zeroItemSizeWithNonzeroCount(header: MXFBatchHeader)
    case multiplicationOverflow(header: MXFBatchHeader)
    case limitExceeded(
        header: MXFBatchHeader,
        limit: MXFInspectionLimit,
        actual: UInt64,
        maximum: UInt64
    )
    case payloadExceedsEnclosingSpan(
        header: MXFBatchHeader,
        declaredByteCount: UInt64,
        availableByteCount: UInt64,
        availableSpan: ByteSpan?
    )
}

enum MXFBatchInspectionResult: Equatable, Sendable {
    case batch(MXFBatchInspection)
    case invalid(MXFBatchInspectionError)
}

struct MXFBatchInspector: Sendable {
    static let headerByteCount: UInt64 = 8

    /// Inspects an MXF batch encoded as a UInt32 count followed by a UInt32 item size.
    /// `batchSpan` is the enclosing local-item value, including the batch header.
    func inspect(
        batchSpan: ByteSpan,
        in data: Data,
        limits: MXFInspectionLimits = MXFInspectionLimits()
    ) -> MXFBatchInspectionResult {
        let physicalByteCount: UInt64
        do {
            physicalByteCount = try CheckedBinaryArithmetic.uint64(exactly: data.count)
        } catch {
            return .invalid(.truncatedHeader(requiredSpan: batchSpan, availableSpan: nil))
        }

        let availableEnd = min(batchSpan.upperBound, physicalByteCount)
        let availableHeaderBytes = availableEnd > batchSpan.lowerBound
            ? min(Self.headerByteCount, availableEnd - batchSpan.lowerBound)
            : 0

        let requiredHeaderSpan: ByteSpan
        do {
            requiredHeaderSpan = try ByteSpan(offset: batchSpan.lowerBound, length: Self.headerByteCount)
        } catch {
            // A header beginning this close to UInt64.max cannot be represented.
            return .invalid(.truncatedHeader(requiredSpan: batchSpan, availableSpan: nil))
        }
        guard batchSpan.length >= Self.headerByteCount, availableHeaderBytes == Self.headerByteCount else {
            return .invalid(.truncatedHeader(
                requiredSpan: requiredHeaderSpan,
                availableSpan: makeSpan(offset: batchSpan.lowerBound, length: availableHeaderBytes)
            ))
        }

        do {
            let countSpan = try ByteSpan(offset: batchSpan.lowerBound, length: 4)
            let itemSizeSpan = try ByteSpan(
                offset: CheckedBinaryArithmetic.add(batchSpan.lowerBound, 4),
                length: 4
            )
            let header = try MXFBatchHeader(
                count: .init(value: UInt64(try data.checkedUInt32BE(at: countSpan.lowerBound)), span: countSpan),
                itemSize: .init(value: UInt64(try data.checkedUInt32BE(at: itemSizeSpan.lowerBound)), span: itemSizeSpan)
            )
            return validate(
                header: header,
                enclosingPayloadByteCount: batchSpan.length - Self.headerByteCount,
                physicalPayloadByteCount: availableEnd - requiredHeaderSpan.upperBound,
                limits: limits
            )
        } catch {
            return .invalid(.truncatedHeader(requiredSpan: requiredHeaderSpan, availableSpan: nil))
        }
    }

    /// Validates already-decoded fields. This also keeps the overflow path directly testable
    /// even though two UInt32 MXF header fields cannot themselves overflow UInt64.
    func validate(
        header: MXFBatchHeader,
        enclosingPayloadByteCount: UInt64,
        physicalPayloadByteCount: UInt64,
        limits: MXFInspectionLimits = MXFInspectionLimits()
    ) -> MXFBatchInspectionResult {
        if header.count.value != 0, header.itemSize.value == 0 {
            return .invalid(.zeroItemSizeWithNonzeroCount(header: header))
        }

        let payloadByteCount: UInt64
        do {
            payloadByteCount = try CheckedBinaryArithmetic.multiply(
                header.count.value,
                header.itemSize.value
            )
        } catch {
            return .invalid(.multiplicationOverflow(header: header))
        }

        guard header.count.value <= limits.maximumElementCount else {
            return .invalid(.limitExceeded(
                header: header, limit: .elementCount, actual: header.count.value,
                maximum: limits.maximumElementCount
            ))
        }
        guard payloadByteCount <= limits.maximumAllocationBytes else {
            return .invalid(.limitExceeded(
                header: header, limit: .allocationBytes, actual: payloadByteCount,
                maximum: limits.maximumAllocationBytes
            ))
        }

        let availableByteCount = min(enclosingPayloadByteCount, physicalPayloadByteCount)
        guard payloadByteCount <= availableByteCount else {
            return .invalid(.payloadExceedsEnclosingSpan(
                header: header,
                declaredByteCount: payloadByteCount,
                availableByteCount: availableByteCount,
                availableSpan: makeSpan(offset: header.span.upperBound, length: availableByteCount)
            ))
        }

        return .batch(MXFBatchInspection(
            header: header,
            payloadSpan: makeSpan(offset: header.span.upperBound, length: payloadByteCount),
            payloadByteCount: payloadByteCount
        ))
    }

    private func makeSpan(offset: UInt64, length: UInt64) -> ByteSpan? {
        guard length > 0 else { return nil }
        return try? ByteSpan(offset: offset, length: length)
    }
}
