import Foundation

enum CheckedDataAccessError: Error, Equatable, Sendable {
    case outOfBounds(requested: ByteSpan, availableByteCount: UInt64)
    case replacementLengthMismatch(expected: UInt64, actual: UInt64)
}

extension Data {
    func checkedUInt16BE(at offset: UInt64) throws -> UInt16 {
        let index = try checkedIndex(offset: offset, byteCount: 2)
        return withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: index, as: UInt16.self).bigEndian
        }
    }

    func checkedUInt32BE(at offset: UInt64) throws -> UInt32 {
        let index = try checkedIndex(offset: offset, byteCount: 4)
        return withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: index, as: UInt32.self).bigEndian
        }
    }

    func checkedUInt64BE(at offset: UInt64) throws -> UInt64 {
        let index = try checkedIndex(offset: offset, byteCount: 8)
        return withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: index, as: UInt64.self).bigEndian
        }
    }

    func checkedBytes(in span: ByteSpan) throws -> Data {
        let range = try checkedRange(for: span)
        return withUnsafeBytes { buffer in
            Data(buffer[range])
        }
    }

    mutating func checkedWriteUInt16BE(_ value: UInt16, at offset: UInt64) throws {
        let index = try checkedIndex(offset: offset, byteCount: 2)
        withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: value.bigEndian, toByteOffset: index, as: UInt16.self)
        }
    }

    mutating func checkedWriteUInt32BE(_ value: UInt32, at offset: UInt64) throws {
        let index = try checkedIndex(offset: offset, byteCount: 4)
        withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: value.bigEndian, toByteOffset: index, as: UInt32.self)
        }
    }

    mutating func checkedWriteUInt64BE(_ value: UInt64, at offset: UInt64) throws {
        let index = try checkedIndex(offset: offset, byteCount: 8)
        withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: value.bigEndian, toByteOffset: index, as: UInt64.self)
        }
    }

    mutating func checkedWriteBytes(_ replacement: Data, in span: ByteSpan) throws {
        let replacementLength = try CheckedBinaryArithmetic.uint64(exactly: replacement.count)
        guard replacementLength == span.length else {
            throw CheckedDataAccessError.replacementLengthMismatch(
                expected: span.length,
                actual: replacementLength
            )
        }

        let range = try checkedRange(for: span)
        replacement.withUnsafeBytes { source in
            withUnsafeMutableBytes { destination in
                destination[range].copyBytes(from: source)
            }
        }
    }

    private func checkedIndex(offset: UInt64, byteCount: UInt64) throws -> Int {
        let span = try ByteSpan(offset: offset, length: byteCount)
        return try checkedRange(for: span).lowerBound
    }

    private func checkedRange(for span: ByteSpan) throws -> Range<Int> {
        let availableByteCount = try CheckedBinaryArithmetic.uint64(exactly: count)
        guard span.upperBound <= availableByteCount else {
            throw CheckedDataAccessError.outOfBounds(
                requested: span,
                availableByteCount: availableByteCount
            )
        }

        let lowerBound = try CheckedBinaryArithmetic.int(exactly: span.lowerBound)
        let upperBound = try CheckedBinaryArithmetic.int(exactly: span.upperBound)
        return lowerBound..<upperBound
    }
}
