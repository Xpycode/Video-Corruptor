import Foundation

/// Scans MXF files for KLV triplets, classifying elements by their UL key.
struct MXFParser: Sendable {

    enum ParseError: Error, LocalizedError {
        case fileNotFound
        case fileTooSmall
        case invalidBER(offset: UInt64)
        case noPartitionFound

        var errorDescription: String? {
            switch self {
            case .fileNotFound: "MXF file not found"
            case .fileTooSmall: "File too small to be a valid MXF"
            case .invalidBER(let offset): "Invalid BER length at offset \(offset)"
            case .noPartitionFound: "No partition pack found in file"
            }
        }
    }

    // MARK: - SMPTE UL Prefixes

    /// All MXF keys start with this 4-byte prefix.
    private static let smptePreamble: [UInt8] = [0x06, 0x0E, 0x2B, 0x34]

    // Partition pack: 06 0E 2B 34 02 05 01 01 0D 01 02 01 01 xx
    private static let partitionPrefix: [UInt8] = [0x06, 0x0E, 0x2B, 0x34, 0x02, 0x05, 0x01, 0x01, 0x0D, 0x01, 0x02, 0x01, 0x01]

    // Picture essence: 06 0E 2B 34 01 02 01 01 0D 01 03 01 15
    // (byte 12 = 0x15 for picture)
    private static let essencePrefix: [UInt8] = [0x06, 0x0E, 0x2B, 0x34, 0x01, 0x02, 0x01, 0x01, 0x0D, 0x01, 0x03, 0x01]

    // Index table segment: 06 0E 2B 34 02 53 01 01 0D 01 02 01 10 01
    private static let indexPrefix: [UInt8] = [0x06, 0x0E, 0x2B, 0x34, 0x02, 0x53, 0x01, 0x01, 0x0D, 0x01, 0x02, 0x01, 0x10, 0x01]

    // RIP: 06 0E 2B 34 02 05 01 01 0D 01 02 01 01 11
    private static let ripPrefix: [UInt8] = [0x06, 0x0E, 0x2B, 0x34, 0x02, 0x05, 0x01, 0x01, 0x0D, 0x01, 0x02, 0x01, 0x01, 0x11]

    // Fill item: 06 0E 2B 34 01 01 01 02 03 01 02 10 01 00
    private static let fillPrefix: [UInt8] = [0x06, 0x0E, 0x2B, 0x34, 0x01, 0x01, 0x01]

    // MARK: - Scanning

    /// Scan all KLV elements in an MXF file.
    func scan(url: URL) throws -> [MXFElement] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParseError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        guard data.count >= 32 else {
            throw ParseError.fileTooSmall
        }

        var elements: [MXFElement] = []
        var offset: UInt64 = 0
        let fileSize = UInt64(data.count)

        while offset + 20 <= fileSize {
            // Look for SMPTE preamble
            guard data[Int(offset)] == 0x06,
                  data[Int(offset) + 1] == 0x0E,
                  data[Int(offset) + 2] == 0x2B,
                  data[Int(offset) + 3] == 0x34 else {
                offset += 1
                continue
            }

            // Read 16-byte key
            let keyEnd = Int(offset) + 16
            guard keyEnd <= data.count else { break }
            let key = data[Int(offset)..<keyEnd]

            // Decode BER length
            let berOffset = offset + 16
            guard let (valueLength, berSize) = decodeBER(data: data, at: Int(berOffset)) else {
                // Skip this key if BER is malformed
                offset += 1
                continue
            }

            let valueOffset = berOffset + UInt64(berSize)
            let totalSize = 16 + UInt64(berSize) + valueLength

            // Sanity check: don't go past EOF
            guard offset + totalSize <= fileSize else {
                break
            }

            let classification = classifyKey(Data(key))

            elements.append(MXFElement(
                key: Data(key),
                keyOffset: offset,
                valueOffset: valueOffset,
                valueLength: valueLength,
                berHeaderSize: berSize,
                classification: classification
            ))

            offset += totalSize
        }

        return elements
    }

    /// Parse the header partition pack from scanned elements.
    func parseHeaderPartition(from elements: [MXFElement], data: Data) -> MXFPartitionPack? {
        guard let element = elements.first(where: {
            $0.classification == .partitionPack && $0.keyOffset == 0
        }) ?? elements.first(where: { $0.classification == .partitionPack }) else {
            return nil
        }

        return parsePartitionPack(element: element, data: data)
    }

    /// Parse a partition pack from a KLV element.
    func parsePartitionPack(element: MXFElement, data: Data) -> MXFPartitionPack? {
        let vo = Int(element.valueOffset)
        guard vo + 64 <= data.count else { return nil }

        guard let majorVersion = data.readUInt16BE(at: vo),
              let minorVersion = data.readUInt16BE(at: vo + 2),
              let kagSize = data.readUInt32BE(at: vo + 4),
              let thisPartition = data.readUInt64BE(at: vo + 8),
              let prevPartition = data.readUInt64BE(at: vo + 16),
              let footerPartition = data.readUInt64BE(at: vo + 24),
              let headerByteCount = data.readUInt64BE(at: vo + 32),
              let indexByteCount = data.readUInt64BE(at: vo + 40),
              let bodyOffset = data.readUInt64BE(at: vo + 48) else {
            return nil
        }

        return MXFPartitionPack(
            element: element,
            majorVersion: majorVersion,
            minorVersion: minorVersion,
            kagSize: kagSize,
            thisPartitionOffset: thisPartition,
            previousPartitionOffset: prevPartition,
            footerPartitionOffset: footerPartition,
            headerByteCount: headerByteCount,
            indexByteCount: indexByteCount,
            bodyOffset: bodyOffset
        )
    }

    // MARK: - BER Decoding

    /// Decode a BER-encoded length. Returns (value, bytesConsumed).
    func decodeBER(data: Data, at offset: Int) -> (UInt64, Int)? {
        guard offset < data.count else { return nil }

        let first = data[offset]

        if first < 0x80 {
            // Short form: single byte is the length
            return (UInt64(first), 1)
        }

        // Long form: lower 7 bits = number of following bytes
        let numBytes = Int(first & 0x7F)
        guard numBytes > 0, numBytes <= 8, offset + 1 + numBytes <= data.count else {
            return nil
        }

        var value: UInt64 = 0
        for i in 0..<numBytes {
            value = (value << 8) | UInt64(data[offset + 1 + i])
        }

        return (value, 1 + numBytes)
    }

    // MARK: - Key Classification

    private func classifyKey(_ key: Data) -> MXFKeyClass {
        let bytes = Array(key)
        guard bytes.count == 16 else { return .other }

        if matches(bytes: bytes, prefix: Self.ripPrefix) {
            return .rip
        }
        if matches(bytes: bytes, prefix: Self.partitionPrefix) {
            return .partitionPack
        }
        if matches(bytes: bytes, prefix: Self.indexPrefix) {
            return .indexTable
        }
        if matches(bytes: bytes, prefix: Self.essencePrefix) {
            // Byte 12 distinguishes essence type
            if bytes.count > 12 {
                switch bytes[12] {
                case 0x15: return .pictureEssence    // MPEG picture
                case 0x05, 0x06, 0x16: return .pictureEssence  // Other picture types
                case 0x06: return .soundEssence
                case 0x07: return .soundEssence
                case 0x17: return .soundEssence      // AES3 audio
                default: break
                }
            }
            return .dataEssence
        }
        if matches(bytes: bytes, prefix: Self.fillPrefix) && bytes.count > 7 && bytes[7] <= 0x05 {
            // Check further bytes for fill item pattern
            if bytes.count > 13 && bytes[8] == 0x03 && bytes[9] == 0x01 && bytes[10] == 0x02 && bytes[11] == 0x10 {
                return .fillItem
            }
        }

        return .other
    }

    private func matches(bytes: [UInt8], prefix: [UInt8]) -> Bool {
        guard bytes.count >= prefix.count else { return false }
        for i in 0..<prefix.count {
            if bytes[i] != prefix[i] { return false }
        }
        return true
    }
}
