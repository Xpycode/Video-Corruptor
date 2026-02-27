import Foundation

/// Per-frame location info derived from MP4 index atoms.
struct FrameInfo: Sendable {
    let sampleIndex: Int       // 1-based sample number
    let fileOffset: UInt64     // Absolute byte offset in the file
    let size: UInt32           // Frame size in bytes
    let isKeyframe: Bool       // true if listed in stss
}

/// Builds a per-frame byte map by combining stco/co64 + stsc + stsz + stss atoms.
struct MP4FrameMapBuilder: Sendable {

    enum FrameMapError: Error, LocalizedError {
        case missingAtom(String)
        case malformedAtom(String)

        var errorDescription: String? {
            switch self {
            case .missingAtom(let name): "Required atom '\(name)' not found"
            case .malformedAtom(let name): "Atom '\(name)' has malformed data"
            }
        }
    }

    private let parser = MP4Parser()

    /// Build a frame map for the first video track in the file.
    func buildFrameMap(from url: URL) throws -> [FrameInfo] {
        let atoms = try parser.parse(url: url)
        let data = try Data(contentsOf: url)

        // Find the video track's stbl (sample table)
        let trakAtoms = parser.findAtoms(type: "trak", in: atoms)
        guard let videoStbl = findVideoSampleTable(in: trakAtoms) else {
            throw FrameMapError.missingAtom("video trak/stbl")
        }

        // Extract index atoms from stbl
        let chunkOffsets = try readChunkOffsets(stbl: videoStbl, data: data)
        let sampleToChunk = try readSampleToChunk(stbl: videoStbl, data: data)
        let sampleSizes = try readSampleSizes(stbl: videoStbl, data: data)
        let keyframeSamples = readSyncSamples(stbl: videoStbl, data: data)

        // Walk chunks to build per-frame info
        return try buildMap(
            chunkOffsets: chunkOffsets,
            sampleToChunk: sampleToChunk,
            sampleSizes: sampleSizes,
            keyframeSamples: keyframeSamples
        )
    }

    // MARK: - Video Track Detection

    private func findVideoSampleTable(in trakAtoms: [MP4Atom]) -> MP4Atom? {
        for trak in trakAtoms {
            let vmhd = parser.findFirst(type: "vmhd", in: trak.children)
            if vmhd != nil {
                return parser.findFirst(type: "stbl", in: trak.children)
            }
        }
        return nil
    }

    // MARK: - stco / co64 (chunk offsets)

    private func readChunkOffsets(stbl: MP4Atom, data: Data) throws -> [UInt64] {
        // Try stco (32-bit) first, fall back to co64 (64-bit)
        if let stco = parser.findFirst(type: "stco", in: [stbl]) ?? parser.findFirst(type: "stco", in: stbl.children) {
            return try readStco(atom: stco, data: data)
        }
        if let co64 = parser.findFirst(type: "co64", in: [stbl]) ?? parser.findFirst(type: "co64", in: stbl.children) {
            return try readCo64(atom: co64, data: data)
        }
        throw FrameMapError.missingAtom("stco/co64")
    }

    private func readStco(atom: MP4Atom, data: Data) throws -> [UInt64] {
        let payloadStart = Int(atom.offset + atom.headerSize)
        // version(1) + flags(3) + entryCount(4) = 8
        guard let entryCount = data.readUInt32BE(at: payloadStart + 4) else {
            throw FrameMapError.malformedAtom("stco")
        }

        var offsets: [UInt64] = []
        offsets.reserveCapacity(Int(entryCount))
        for i in 0..<Int(entryCount) {
            guard let offset = data.readUInt32BE(at: payloadStart + 8 + i * 4) else { break }
            offsets.append(UInt64(offset))
        }
        return offsets
    }

    private func readCo64(atom: MP4Atom, data: Data) throws -> [UInt64] {
        let payloadStart = Int(atom.offset + atom.headerSize)
        guard let entryCount = data.readUInt32BE(at: payloadStart + 4) else {
            throw FrameMapError.malformedAtom("co64")
        }

        var offsets: [UInt64] = []
        offsets.reserveCapacity(Int(entryCount))
        for i in 0..<Int(entryCount) {
            guard let offset = data.readUInt64BE(at: payloadStart + 8 + i * 8) else { break }
            offsets.append(offset)
        }
        return offsets
    }

    // MARK: - stsc (sample-to-chunk)

    /// Each stsc entry: (firstChunk, samplesPerChunk, sampleDescriptionIndex)
    private struct StscEntry {
        let firstChunk: UInt32       // 1-based
        let samplesPerChunk: UInt32
    }

    private func readSampleToChunk(stbl: MP4Atom, data: Data) throws -> [StscEntry] {
        guard let stsc = parser.findFirst(type: "stsc", in: [stbl]) ?? parser.findFirst(type: "stsc", in: stbl.children) else {
            throw FrameMapError.missingAtom("stsc")
        }

        let payloadStart = Int(stsc.offset + stsc.headerSize)
        guard let entryCount = data.readUInt32BE(at: payloadStart + 4) else {
            throw FrameMapError.malformedAtom("stsc")
        }

        var entries: [StscEntry] = []
        entries.reserveCapacity(Int(entryCount))
        for i in 0..<Int(entryCount) {
            let base = payloadStart + 8 + i * 12
            guard let firstChunk = data.readUInt32BE(at: base),
                  let samplesPerChunk = data.readUInt32BE(at: base + 4) else { break }
            entries.append(StscEntry(firstChunk: firstChunk, samplesPerChunk: samplesPerChunk))
        }
        return entries
    }

    // MARK: - stsz (sample sizes)

    private func readSampleSizes(stbl: MP4Atom, data: Data) throws -> [UInt32] {
        guard let stsz = parser.findFirst(type: "stsz", in: [stbl]) ?? parser.findFirst(type: "stsz", in: stbl.children) else {
            throw FrameMapError.missingAtom("stsz")
        }

        let payloadStart = Int(stsz.offset + stsz.headerSize)
        // version(1) + flags(3) + sampleSize(4) + sampleCount(4)
        guard let uniformSize = data.readUInt32BE(at: payloadStart + 4),
              let sampleCount = data.readUInt32BE(at: payloadStart + 8) else {
            throw FrameMapError.malformedAtom("stsz")
        }

        if uniformSize != 0 {
            // All samples have the same size
            return Array(repeating: uniformSize, count: Int(sampleCount))
        }

        // Variable sizes follow
        var sizes: [UInt32] = []
        sizes.reserveCapacity(Int(sampleCount))
        for i in 0..<Int(sampleCount) {
            guard let size = data.readUInt32BE(at: payloadStart + 12 + i * 4) else { break }
            sizes.append(size)
        }
        return sizes
    }

    // MARK: - stss (sync samples / keyframes)

    private func readSyncSamples(stbl: MP4Atom, data: Data) -> Set<Int> {
        guard let stss = parser.findFirst(type: "stss", in: [stbl]) ?? parser.findFirst(type: "stss", in: stbl.children) else {
            // No stss means every sample is a sync sample (e.g. MJPEG)
            return []
        }

        let payloadStart = Int(stss.offset + stss.headerSize)
        guard let entryCount = data.readUInt32BE(at: payloadStart + 4) else { return [] }

        var keyframes = Set<Int>()
        for i in 0..<Int(entryCount) {
            guard let sampleNumber = data.readUInt32BE(at: payloadStart + 8 + i * 4) else { break }
            keyframes.insert(Int(sampleNumber))
        }
        return keyframes
    }

    // MARK: - Map Assembly

    private func buildMap(
        chunkOffsets: [UInt64],
        sampleToChunk: [StscEntry],
        sampleSizes: [UInt32],
        keyframeSamples: Set<Int>
    ) throws -> [FrameInfo] {
        let allKeyframes = keyframeSamples.isEmpty // empty stss = all keyframes

        var frames: [FrameInfo] = []
        frames.reserveCapacity(sampleSizes.count)

        guard !sampleToChunk.isEmpty else {
            throw FrameMapError.malformedAtom("stsc (no entries)")
        }

        var sampleIndex = 1
        var stscIdx = 0

        for chunkIndex in 0..<chunkOffsets.count {
            let chunkNum = UInt32(chunkIndex + 1)

            // Advance stsc entry if next entry's firstChunk has been reached
            if stscIdx + 1 < sampleToChunk.count && sampleToChunk[stscIdx + 1].firstChunk <= chunkNum {
                stscIdx += 1
            }

            let samplesInChunk = Int(sampleToChunk[stscIdx].samplesPerChunk)
            var offsetInChunk: UInt64 = 0

            for _ in 0..<samplesInChunk {
                guard sampleIndex - 1 < sampleSizes.count else { break }

                let size = sampleSizes[sampleIndex - 1]
                let isKey = allKeyframes || keyframeSamples.contains(sampleIndex)

                frames.append(FrameInfo(
                    sampleIndex: sampleIndex,
                    fileOffset: chunkOffsets[chunkIndex] + offsetInChunk,
                    size: size,
                    isKeyframe: isKey
                ))

                offsetInChunk += UInt64(size)
                sampleIndex += 1
            }
        }

        return frames
    }
}
