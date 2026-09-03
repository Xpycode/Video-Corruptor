import Foundation

struct MXFLocalSetItem: Equatable, Sendable {
    let tag: UInt16
    let resolvedUniversalLabel: Data?
    let tagSpan: ByteSpan
    let ber: MXFBERDecodedLength
    /// Nil represents a valid zero-length value.
    let valueSpan: ByteSpan?
    let physicalSpan: ByteSpan
}

enum MXFLocalSetError: Error, Equatable, Sendable {
    case enclosingSpanOutsideInput(span: ByteSpan, inputByteCount: UInt64)
    case truncatedTag(offset: UInt64, availableByteCount: UInt64)
    case malformedBER(offset: UInt64, error: MXFBERError)
    case itemExceedsEnclosingValue(
        tag: UInt16,
        valueOffset: UInt64,
        declaredByteCount: UInt64,
        availableByteCount: UInt64
    )
    case integerOverflow(offset: UInt64)
    case itemLimitExceeded(actual: UInt64, maximum: UInt64)
}

struct MXFLocalSetInspection: Equatable, Sendable {
    let enclosingSpan: ByteSpan
    let items: [MXFLocalSetItem]
    let error: MXFLocalSetError?
    let completedWalk: Bool
}

struct MXFLocalSetInspector: Sendable {
    static let defaultMaximumItemCount: UInt64 = 100_000

    func inspect(
        data: Data,
        enclosingSpan: ByteSpan,
        primerMap: MXFPrimerMap = MXFPrimerMap(),
        maximumItemCount: UInt64 = Self.defaultMaximumItemCount
    ) -> MXFLocalSetInspection {
        let inputByteCount: UInt64
        do {
            inputByteCount = try CheckedBinaryArithmetic.uint64(exactly: data.count)
        } catch {
            return result(enclosingSpan, [], .integerOverflow(offset: enclosingSpan.lowerBound))
        }
        guard enclosingSpan.upperBound <= inputByteCount else {
            return result(enclosingSpan, [], .enclosingSpanOutsideInput(
                span: enclosingSpan,
                inputByteCount: inputByteCount
            ))
        }

        var items: [MXFLocalSetItem] = []
        var cursor = enclosingSpan.lowerBound
        var itemCount: UInt64 = 0

        while cursor < enclosingSpan.upperBound {
            let nextCount: UInt64
            do {
                nextCount = try CheckedBinaryArithmetic.add(itemCount, 1)
            } catch {
                return result(enclosingSpan, items, .integerOverflow(offset: cursor))
            }
            guard nextCount <= maximumItemCount else {
                return result(enclosingSpan, items, .itemLimitExceeded(
                    actual: nextCount,
                    maximum: maximumItemCount
                ))
            }

            let availableForTag = enclosingSpan.upperBound - cursor
            guard availableForTag >= 2 else {
                return result(enclosingSpan, items, .truncatedTag(
                    offset: cursor,
                    availableByteCount: availableForTag
                ))
            }

            let tag: UInt16
            let tagSpan: ByteSpan
            let berOffset: UInt64
            do {
                tag = try data.checkedUInt16BE(at: cursor)
                tagSpan = try ByteSpan(offset: cursor, length: 2)
                berOffset = try CheckedBinaryArithmetic.add(cursor, 2)
            } catch {
                return result(enclosingSpan, items, .integerOverflow(offset: cursor))
            }

            let ber: MXFBERDecodedLength
            do {
                ber = try decodeBER(data: data, at: berOffset, end: enclosingSpan.upperBound)
            } catch let error as MXFBERError {
                return result(enclosingSpan, items, .malformedBER(offset: berOffset, error: error))
            } catch {
                return result(enclosingSpan, items, .integerOverflow(offset: berOffset))
            }

            let valueOffset: UInt64
            let valueEnd: UInt64
            do {
                valueOffset = try CheckedBinaryArithmetic.add(berOffset, ber.encodedWidth)
                valueEnd = try CheckedBinaryArithmetic.add(valueOffset, ber.value)
            } catch {
                return result(enclosingSpan, items, .integerOverflow(offset: berOffset))
            }
            guard valueEnd <= enclosingSpan.upperBound else {
                return result(enclosingSpan, items, .itemExceedsEnclosingValue(
                    tag: tag,
                    valueOffset: valueOffset,
                    declaredByteCount: ber.value,
                    availableByteCount: enclosingSpan.upperBound - valueOffset
                ))
            }

            do {
                let physicalSpan = try ByteSpan(lowerBound: cursor, upperBound: valueEnd)
                let valueSpan = ber.value == 0
                    ? nil
                    : try ByteSpan(lowerBound: valueOffset, upperBound: valueEnd)
                items.append(MXFLocalSetItem(
                    tag: tag,
                    resolvedUniversalLabel: primerMap.universalLabel(for: tag),
                    tagSpan: tagSpan,
                    ber: ber,
                    valueSpan: valueSpan,
                    physicalSpan: physicalSpan
                ))
            } catch {
                return result(enclosingSpan, items, .integerOverflow(offset: cursor))
            }
            itemCount = nextCount
            cursor = valueEnd
        }

        return MXFLocalSetInspection(
            enclosingSpan: enclosingSpan,
            items: items,
            error: nil,
            completedWalk: true
        )
    }

    private func decodeBER(data: Data, at offset: UInt64, end: UInt64) throws -> MXFBERDecodedLength {
        let available = end - offset
        guard available > 0 else {
            throw MXFBERError.truncatedHeader(offset: offset, requiredWidth: 1, availableWidth: 0)
        }
        let firstIndex = try CheckedBinaryArithmetic.int(exactly: offset)
        let first = data[firstIndex]
        let requiredWidth = first < 0x80 ? UInt64(1) : UInt64(first & 0x7f) + 1
        let boundedWidth = min(available, min(requiredWidth, 9))
        let headerSpan = try ByteSpan(offset: offset, length: boundedWidth)
        let header = try data.checkedBytes(in: headerSpan)
        return try MXFBER.decodeHeader(header, atPhysicalOffset: offset)
    }

    private func result(
        _ span: ByteSpan,
        _ items: [MXFLocalSetItem],
        _ error: MXFLocalSetError
    ) -> MXFLocalSetInspection {
        MXFLocalSetInspection(
            enclosingSpan: span,
            items: items,
            error: error,
            completedWalk: false
        )
    }
}
