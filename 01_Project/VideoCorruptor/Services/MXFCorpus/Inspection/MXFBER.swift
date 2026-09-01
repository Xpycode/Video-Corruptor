import Foundation

enum MXFBERForm: Equatable, Sendable {
    case short
    case long(lengthOctetCount: UInt8)
}

enum MXFBERCanonicality: Equatable, Sendable {
    case canonical
    case nonCanonical
}

enum MXFBERDiagnostic: Equatable, Sendable {
    case leadingZeroLengthOctet
    case nonMinimalLongForm(minimumLengthOctetCount: UInt8, actualLengthOctetCount: UInt8)
}

enum MXFBERError: Error, Equatable, Sendable {
    case reservedIndefiniteForm(offset: UInt64)
    case excessiveLengthOfLength(offset: UInt64, lengthOctetCount: UInt8, maximum: UInt8)
    case truncatedHeader(offset: UInt64, requiredWidth: UInt64, availableWidth: UInt64)
    case valueOverflow(offset: UInt64)
    case lengthLimitExceeded(value: UInt64, limit: UInt64)
}

struct MXFBERDecodedLength: Equatable, Sendable {
    let value: UInt64
    let encodedWidth: UInt64
    let physicalSpan: ByteSpan
    let form: MXFBERForm
    let canonicality: MXFBERCanonicality
    let diagnostics: [MXFBERDiagnostic]
}

enum MXFBER {
    static let maximumLengthOctetCount: UInt8 = 8

    static func decodeLength(
        from data: Data,
        at offset: UInt64,
        maximumValue: UInt64 = .max
    ) throws -> MXFBERDecodedLength {
        let availableByteCount = try CheckedBinaryArithmetic.uint64(exactly: data.count)
        guard offset < availableByteCount else {
            throw MXFBERError.truncatedHeader(
                offset: offset,
                requiredWidth: 1,
                availableWidth: 0
            )
        }

        let offsetIndex = try CheckedBinaryArithmetic.int(exactly: offset)
        let first = data[offsetIndex]

        if first < 0x80 {
            let value = UInt64(first)
            guard value <= maximumValue else {
                throw MXFBERError.lengthLimitExceeded(value: value, limit: maximumValue)
            }
            return MXFBERDecodedLength(
                value: value,
                encodedWidth: 1,
                physicalSpan: try ByteSpan(offset: offset, length: 1),
                form: .short,
                canonicality: .canonical,
                diagnostics: []
            )
        }

        let lengthOctetCount = first & 0x7f
        guard lengthOctetCount != 0 else {
            throw MXFBERError.reservedIndefiniteForm(offset: offset)
        }
        guard lengthOctetCount <= maximumLengthOctetCount else {
            throw MXFBERError.excessiveLengthOfLength(
                offset: offset,
                lengthOctetCount: lengthOctetCount,
                maximum: maximumLengthOctetCount
            )
        }

        let encodedWidth = try checkedWidth(offset: offset, lengthOctetCount: lengthOctetCount)
        let availableWidth = availableByteCount - offset
        guard encodedWidth <= availableWidth else {
            throw MXFBERError.truncatedHeader(
                offset: offset,
                requiredWidth: encodedWidth,
                availableWidth: availableWidth
            )
        }

        var value: UInt64 = 0
        for index in 0..<Int(lengthOctetCount) {
            let relativeIndex = try CheckedBinaryArithmetic.uint64(exactly: index)
            let contentOffset = try CheckedBinaryArithmetic.add(
                offset,
                CheckedBinaryArithmetic.add(1, relativeIndex)
            )
            let contentIndex = try CheckedBinaryArithmetic.int(exactly: contentOffset)
            let byte = UInt64(data[contentIndex])
            do {
                value = try CheckedBinaryArithmetic.add(
                    CheckedBinaryArithmetic.multiply(value, 256),
                    byte
                )
            } catch {
                throw MXFBERError.valueOverflow(offset: offset)
            }
        }

        guard value <= maximumValue else {
            throw MXFBERError.lengthLimitExceeded(value: value, limit: maximumValue)
        }

        var diagnostics: [MXFBERDiagnostic] = []
        let firstContentOffset = try CheckedBinaryArithmetic.add(offset, 1)
        let firstContentIndex = try CheckedBinaryArithmetic.int(exactly: firstContentOffset)
        if data[firstContentIndex] == 0 {
            diagnostics.append(.leadingZeroLengthOctet)
        }
        let minimumCount = minimumLongFormOctetCount(for: value)
        if value < 0x80 || lengthOctetCount > minimumCount {
            diagnostics.append(.nonMinimalLongForm(
                minimumLengthOctetCount: minimumCount,
                actualLengthOctetCount: lengthOctetCount
            ))
        }

        return MXFBERDecodedLength(
            value: value,
            encodedWidth: encodedWidth,
            physicalSpan: try ByteSpan(offset: offset, length: encodedWidth),
            form: .long(lengthOctetCount: lengthOctetCount),
            canonicality: diagnostics.isEmpty ? .canonical : .nonCanonical,
            diagnostics: diagnostics
        )
    }

    private static func checkedWidth(offset: UInt64, lengthOctetCount: UInt8) throws -> UInt64 {
        do {
            return try CheckedBinaryArithmetic.add(1, UInt64(lengthOctetCount))
        } catch {
            throw MXFBERError.valueOverflow(offset: offset)
        }
    }

    private static func minimumLongFormOctetCount(for value: UInt64) -> UInt8 {
        guard value > 0 else { return 1 }
        var remaining = value
        var count: UInt8 = 0
        while remaining > 0 {
            count += 1
            remaining >>= 8
        }
        return count
    }
}
