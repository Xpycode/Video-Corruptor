import Foundation

extension Data {

    /// Read a big-endian UInt16 at the given byte offset.
    func readUInt16BE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self).bigEndian
        }
    }

    /// Read a big-endian UInt32 at the given byte offset.
    func readUInt32BE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian
        }
    }

    /// Read a big-endian UInt64 at the given byte offset.
    func readUInt64BE(at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= count else { return nil }
        return withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self).bigEndian
        }
    }

    /// Write a big-endian UInt32 at the given byte offset.
    mutating func writeUInt32BE(_ value: UInt32, at offset: Int) {
        guard offset >= 0, offset + 4 <= count else { return }
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { src in
            for i in 0..<4 {
                self[offset + i] = src[i]
            }
        }
    }

    /// Write a big-endian UInt64 at the given byte offset.
    mutating func writeUInt64BE(_ value: UInt64, at offset: Int) {
        guard offset >= 0, offset + 8 <= count else { return }
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { src in
            for i in 0..<8 {
                self[offset + i] = src[i]
            }
        }
    }
}
