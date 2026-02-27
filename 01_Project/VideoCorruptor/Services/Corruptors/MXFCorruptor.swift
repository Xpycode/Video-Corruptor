import Foundation

/// Handles all MXF-specific corruptions.
struct MXFCorruptor: CorruptionHandler {

    let supportedTypes: Set<CorruptionType> = [
        .mxfEssenceCorruption,
        .mxfKLVKeyCorruption,
        .mxfBERLengthManipulation,
        .mxfPartitionBreakage,
        .mxfIndexScrambling,
    ]

    private let mxfParser = MXFParser()

    func apply(_ type: CorruptionType, to url: URL, sourceFile: VideoFile) throws {
        let elements = try mxfParser.scan(url: url)
        var data = try Data(contentsOf: url)

        switch type {
        case .mxfEssenceCorruption:
            try applyEssenceCorruption(elements: elements, data: &data)
        case .mxfKLVKeyCorruption:
            applyKLVKeyCorruption(elements: elements, data: &data)
        case .mxfBERLengthManipulation:
            try applyBERLengthManipulation(elements: elements, data: &data)
        case .mxfPartitionBreakage:
            try applyPartitionBreakage(elements: elements, data: &data)
        case .mxfIndexScrambling:
            try applyIndexScrambling(elements: elements, data: &data)
        default:
            break
        }

        try data.write(to: url)
    }

    // MARK: - Essence Corruption

    /// XOR ~2% of bytes in picture essence payloads, skipping first 64-128 bytes (codec header).
    private func applyEssenceCorruption(elements: [MXFElement], data: inout Data) throws {
        let pictureElements = elements.filter { $0.classification == .pictureEssence }
        guard !pictureElements.isEmpty else {
            throw CorruptionError.atomNotFound("picture essence elements")
        }

        for element in pictureElements {
            let skipBytes = Int.random(in: 64...128)
            let valueStart = Int(element.valueOffset) + skipBytes
            let valueEnd = Int(element.valueOffset + element.valueLength)

            guard valueStart < valueEnd, valueEnd <= data.count else { continue }

            let corruptLength = valueEnd - valueStart
            let corruptCount = max(1, corruptLength / 50) // ~2%

            for _ in 0..<corruptCount {
                let idx = valueStart + Int.random(in: 0..<corruptLength)
                data[idx] = data[idx] ^ UInt8.random(in: 1...255)
            }
        }
    }

    // MARK: - KLV Key Corruption

    /// Change byte 12 (item type) in ~30% of picture essence KLV keys.
    private func applyKLVKeyCorruption(elements: [MXFElement], data: inout Data) {
        let pictureElements = elements.filter { $0.classification == .pictureEssence }
        let targetCount = max(1, pictureElements.count * 30 / 100)
        let targets = pictureElements.shuffled().prefix(targetCount)

        for element in targets {
            let byte12Offset = Int(element.keyOffset) + 12
            guard byte12Offset < data.count else { continue }
            // Change the item type byte to a different value
            data[byte12Offset] = data[byte12Offset] ^ 0xFF
        }
    }

    // MARK: - BER Length Manipulation

    /// Shorten BER-encoded value lengths by 10-50%.
    private func applyBERLengthManipulation(elements: [MXFElement], data: inout Data) throws {
        let pictureElements = elements.filter { $0.classification == .pictureEssence }
        guard !pictureElements.isEmpty else {
            throw CorruptionError.atomNotFound("picture essence elements")
        }

        for element in pictureElements {
            let berStart = Int(element.keyOffset) + 16  // BER starts after 16-byte key
            let reductionFactor = Double.random(in: 0.50...0.90)  // Keep 50-90% of length
            let newLength = UInt64(Double(element.valueLength) * reductionFactor)

            // Re-encode the BER length in-place
            encodeBER(value: newLength, into: &data, at: berStart, availableBytes: element.berHeaderSize)
        }
    }

    /// Encode a BER length value into existing space.
    private func encodeBER(value: UInt64, into data: inout Data, at offset: Int, availableBytes: Int) {
        guard offset + availableBytes <= data.count else { return }

        if availableBytes == 1 && value < 0x80 {
            data[offset] = UInt8(value)
            return
        }

        // Long form: determine minimum bytes needed
        var temp = value
        var numBytes = 0
        while temp > 0 {
            numBytes += 1
            temp >>= 8
        }
        numBytes = max(1, numBytes)

        // Clamp to available space
        let usableBytes = min(numBytes, availableBytes - 1)
        guard usableBytes > 0 else { return }

        data[offset] = 0x80 | UInt8(usableBytes)
        for i in 0..<usableBytes {
            let shift = (usableBytes - 1 - i) * 8
            data[offset + 1 + i] = UInt8((value >> shift) & 0xFF)
        }

        // Zero any remaining bytes in the BER field
        for i in (1 + usableBytes)..<availableBytes {
            data[offset + i] = 0
        }
    }

    // MARK: - Partition Breakage

    /// Zero the 8-byte FooterPartition offset in the header partition pack.
    private func applyPartitionBreakage(elements: [MXFElement], data: inout Data) throws {
        let partitions = elements.filter { $0.classification == .partitionPack }
        guard let header = partitions.first else {
            throw CorruptionError.atomNotFound("partition pack")
        }

        // FooterPartition offset is at value offset + 24 (8 bytes)
        let footerOffset = Int(header.valueOffset) + 24
        guard footerOffset + 8 <= data.count else {
            throw CorruptionError.atomTooSmall("partition pack")
        }

        // Zero the footer partition offset
        for i in 0..<8 {
            data[footerOffset + i] = 0
        }
    }

    // MARK: - Index Scrambling

    /// Swap 8-byte blocks within index table segment values.
    private func applyIndexScrambling(elements: [MXFElement], data: inout Data) throws {
        let indexElements = elements.filter { $0.classification == .indexTable }
        guard !indexElements.isEmpty else {
            throw CorruptionError.atomNotFound("index table segments")
        }

        for element in indexElements {
            let valueStart = Int(element.valueOffset)
            let valueEnd = Int(element.valueOffset + element.valueLength)
            guard valueEnd <= data.count else { continue }

            // Collect 8-byte block positions
            var blocks: [Int] = []
            var pos = valueStart
            while pos + 8 <= valueEnd {
                blocks.append(pos)
                pos += 8
            }

            guard blocks.count >= 2 else { continue }

            // Swap random pairs of 8-byte blocks
            let swapCount = max(1, blocks.count / 4)
            for _ in 0..<swapCount {
                let a = blocks.randomElement()!
                let b = blocks.randomElement()!
                guard a != b else { continue }

                for i in 0..<8 {
                    let temp = data[a + i]
                    data[a + i] = data[b + i]
                    data[b + i] = temp
                }
            }
        }
    }
}
