import Foundation

/// Handles all MP4/MOV-specific corruptions: container, stream, index table, and bitstream.
struct MP4Corruptor: CorruptionHandler {

    let supportedTypes: Set<CorruptionType> = [
        // Container
        .corruptHeader, .containerStructure, .missingVideoTrack, .missingAudioTrack,
        // Stream
        .timestampGap, .decodeError,
        // Index table
        .chunkOffsetShift, .keyframeRemoval, .sampleSizeCorruption,
        // Bitstream
        .iFrameDatamosh, .targetedFrameCorruption,
    ]

    private let parser = MP4Parser()
    private let frameMapBuilder = MP4FrameMapBuilder()

    func apply(_ type: CorruptionType, to url: URL, sourceFile: VideoFile) throws {
        switch type {
        // Container
        case .corruptHeader:
            try applyHeaderCorruption(to: url)
        case .containerStructure:
            try applyContainerCorruption(to: url)
        case .missingVideoTrack:
            try applyTrackRemoval(to: url, removeVideo: true)
        case .missingAudioTrack:
            try applyTrackRemoval(to: url, removeVideo: false)
        // Stream
        case .timestampGap:
            try applyTimestampCorruption(to: url)
        case .decodeError:
            try applyByteFlip(to: url)
        // Index table
        case .chunkOffsetShift:
            try applyChunkOffsetShift(to: url)
        case .keyframeRemoval:
            try applyKeyframeRemoval(to: url)
        case .sampleSizeCorruption:
            try applySampleSizeCorruption(to: url)
        // Bitstream
        case .iFrameDatamosh:
            try applyIFrameDatamosh(to: url)
        case .targetedFrameCorruption:
            try applyTargetedFrameCorruption(to: url)
        default:
            break
        }
    }

    // MARK: - Container Corruptions

    /// Overwrite bytes in the ftyp atom header area.
    private func applyHeaderCorruption(to url: URL) throws {
        var data = try Data(contentsOf: url)

        if data.count > 12 {
            for i in 4..<min(8, data.count) {
                data[i] = UInt8.random(in: 0...255)
            }
        }

        try data.write(to: url)
    }

    /// Corrupt the moov atom size to create malformed structure.
    private func applyContainerCorruption(to url: URL) throws {
        let atoms = try parser.parse(url: url)

        guard let moov = parser.findFirst(type: "moov", in: atoms) else {
            throw CorruptionError.atomNotFound("moov")
        }

        var data = try Data(contentsOf: url)
        let sizeOffset = Int(moov.offset)

        if sizeOffset + 4 <= data.count {
            let corruptSize = UInt32(moov.size + 1000).bigEndian
            withUnsafeBytes(of: corruptSize) { bytes in
                data.replaceSubrange(sizeOffset..<(sizeOffset + 4), with: bytes)
            }
        }

        try data.write(to: url)
    }

    /// Zero out a trak atom to simulate missing track.
    private func applyTrackRemoval(to url: URL, removeVideo: Bool) throws {
        let atoms = try parser.parse(url: url)
        let trakAtoms = parser.findAtoms(type: "trak", in: atoms)

        guard !trakAtoms.isEmpty else {
            throw CorruptionError.atomNotFound("trak")
        }

        var data = try Data(contentsOf: url)
        let targetType = removeVideo ? "vmhd" : "smhd"

        for trak in trakAtoms {
            let hasTarget = !parser.findAtoms(type: targetType, in: trak.children).isEmpty
            if hasTarget {
                let typeOffset = Int(trak.offset + 4)
                if typeOffset + 4 <= data.count {
                    data[typeOffset] = 0
                    data[typeOffset + 1] = 0
                    data[typeOffset + 2] = 0
                    data[typeOffset + 3] = 0
                }
                break
            }
        }

        try data.write(to: url)
    }

    // MARK: - Stream Corruptions

    /// Corrupt the stts atom to create timestamp discontinuities.
    private func applyTimestampCorruption(to url: URL) throws {
        let atoms = try parser.parse(url: url)
        let sttsAtoms = parser.findAtoms(type: "stts", in: atoms)

        guard let stts = sttsAtoms.first else {
            throw CorruptionError.atomNotFound("stts")
        }

        var data = try Data(contentsOf: url)
        let payloadStart = Int(stts.offset + stts.headerSize)
        let payloadEnd = Int(stts.offset + stts.size)

        guard payloadEnd <= data.count, payloadEnd - payloadStart > 8 else {
            throw CorruptionError.atomTooSmall("stts")
        }

        let entriesStart = payloadStart + 8
        if entriesStart + 8 <= payloadEnd {
            for i in (entriesStart + 4)..<min(entriesStart + 8, payloadEnd) {
                data[i] = UInt8.random(in: 100...255)
            }
        }

        try data.write(to: url)
    }

    /// Flip random bytes inside the mdat atom.
    private func applyByteFlip(to url: URL) throws {
        let atoms = try parser.parse(url: url)
        let mdatAtoms = parser.findAtoms(type: "mdat", in: atoms)

        guard let mdat = mdatAtoms.first else {
            throw CorruptionError.atomNotFound("mdat")
        }

        var data = try Data(contentsOf: url)
        let payloadStart = Int(mdat.offset + mdat.headerSize)
        let payloadEnd = min(Int(mdat.offset + mdat.size), data.count)
        let payloadLength = payloadEnd - payloadStart

        guard payloadLength > 0 else {
            throw CorruptionError.atomTooSmall("mdat")
        }

        let flipCount = max(10, payloadLength / 100)
        for _ in 0..<flipCount {
            let idx = payloadStart + Int.random(in: 0..<payloadLength)
            data[idx] = data[idx] ^ 0xFF
        }

        try data.write(to: url)
    }

    // MARK: - Index Table Corruptions

    /// Shift all stco/co64 chunk offsets by 1-50 bytes.
    private func applyChunkOffsetShift(to url: URL) throws {
        let atoms = try parser.parse(url: url)
        var data = try Data(contentsOf: url)

        let shift = UInt32.random(in: 1...50)

        // Try stco first
        let stcoAtoms = parser.findAtoms(type: "stco", in: atoms)
        if let stco = stcoAtoms.first {
            let payloadStart = Int(stco.offset + stco.headerSize)
            guard let entryCount = data.readUInt32BE(at: payloadStart + 4) else {
                throw CorruptionError.atomTooSmall("stco")
            }

            for i in 0..<Int(entryCount) {
                let entryOffset = payloadStart + 8 + i * 4
                guard let original = data.readUInt32BE(at: entryOffset) else { continue }
                data.writeUInt32BE(original &+ shift, at: entryOffset)
            }

            try data.write(to: url)
            return
        }

        // Fallback to co64
        let co64Atoms = parser.findAtoms(type: "co64", in: atoms)
        if let co64 = co64Atoms.first {
            let payloadStart = Int(co64.offset + co64.headerSize)
            guard let entryCount = data.readUInt32BE(at: payloadStart + 4) else {
                throw CorruptionError.atomTooSmall("co64")
            }

            for i in 0..<Int(entryCount) {
                let entryOffset = payloadStart + 8 + i * 8
                guard let original = data.readUInt64BE(at: entryOffset) else { continue }
                data.writeUInt64BE(original &+ UInt64(shift), at: entryOffset)
            }

            try data.write(to: url)
            return
        }

        throw CorruptionError.atomNotFound("stco/co64")
    }

    /// Set stss entry count to 0 to break seeking.
    private func applyKeyframeRemoval(to url: URL) throws {
        let atoms = try parser.parse(url: url)
        let stssAtoms = parser.findAtoms(type: "stss", in: atoms)

        guard let stss = stssAtoms.first else {
            throw CorruptionError.atomNotFound("stss")
        }

        var data = try Data(contentsOf: url)
        let payloadStart = Int(stss.offset + stss.headerSize)

        // Set entry count (offset +4 in payload) to 0
        data.writeUInt32BE(0, at: payloadStart + 4)

        try data.write(to: url)
    }

    /// Corrupt ~10% of stsz sample size entries.
    private func applySampleSizeCorruption(to url: URL) throws {
        let atoms = try parser.parse(url: url)
        let stszAtoms = parser.findAtoms(type: "stsz", in: atoms)

        guard let stsz = stszAtoms.first else {
            throw CorruptionError.atomNotFound("stsz")
        }

        var data = try Data(contentsOf: url)
        let payloadStart = Int(stsz.offset + stsz.headerSize)

        guard let uniformSize = data.readUInt32BE(at: payloadStart + 4),
              let sampleCount = data.readUInt32BE(at: payloadStart + 8) else {
            throw CorruptionError.atomTooSmall("stsz")
        }

        // Only corrupt if variable-size entries exist
        guard uniformSize == 0, sampleCount > 0 else {
            // Uniform size: corrupt the uniform value
            let corruptedSize = UInt32.random(in: 1...100)
            data.writeUInt32BE(corruptedSize, at: payloadStart + 4)
            try data.write(to: url)
            return
        }

        // Corrupt ~10% of entries
        let corruptCount = max(1, Int(sampleCount) / 10)
        let indices = (0..<Int(sampleCount)).shuffled().prefix(corruptCount)

        for i in indices {
            let entryOffset = payloadStart + 12 + i * 4
            guard let original = data.readUInt32BE(at: entryOffset) else { continue }
            // Randomly double or halve the size
            let corrupted = Bool.random() ? original &* 2 : original / 2
            data.writeUInt32BE(max(1, corrupted), at: entryOffset)
        }

        try data.write(to: url)
    }

    // MARK: - Bitstream Corruptions

    /// Change IDR NAL type (0x65) to non-IDR (0x61) for datamosh effect.
    private func applyIFrameDatamosh(to url: URL) throws {
        let frames = try frameMapBuilder.buildFrameMap(from: url)
        var data = try Data(contentsOf: url)

        let keyframes = frames.filter(\.isKeyframe)
        guard !keyframes.isEmpty else {
            throw CorruptionError.atomNotFound("keyframes (stss)")
        }

        // Skip the very first keyframe to keep the video decodable initially
        let targets = keyframes.count > 1 ? Array(keyframes.dropFirst()) : keyframes

        for frame in targets {
            let frameStart = Int(frame.fileOffset)
            let frameEnd = frameStart + Int(frame.size)
            guard frameEnd <= data.count else { continue }

            // Walk length-prefixed NAL units within this frame
            var pos = frameStart
            while pos + 4 < frameEnd {
                guard let nalLength = data.readUInt32BE(at: pos) else { break }
                let nalStart = pos + 4
                let nalEnd = nalStart + Int(nalLength)
                guard nalEnd <= frameEnd, nalLength > 0 else { break }

                // Check NAL type (lower 5 bits of first byte)
                let nalType = data[nalStart] & 0x1F
                if nalType == 5 {
                    // IDR slice → change to non-IDR (type 1)
                    data[nalStart] = (data[nalStart] & 0xE0) | 0x01
                }

                pos = nalEnd
            }
        }

        try data.write(to: url)
    }

    /// Flip ~5% of bytes in keyframe NALs, skipping first 20 bytes (slice header).
    private func applyTargetedFrameCorruption(to url: URL) throws {
        let frames = try frameMapBuilder.buildFrameMap(from: url)
        var data = try Data(contentsOf: url)

        let keyframes = frames.filter(\.isKeyframe)
        guard !keyframes.isEmpty else {
            throw CorruptionError.atomNotFound("keyframes (stss)")
        }

        for frame in keyframes {
            let frameStart = Int(frame.fileOffset)
            let frameEnd = frameStart + Int(frame.size)
            guard frameEnd <= data.count else { continue }

            // Walk NAL units
            var pos = frameStart
            while pos + 4 < frameEnd {
                guard let nalLength = data.readUInt32BE(at: pos) else { break }
                let nalStart = pos + 4
                let nalEnd = nalStart + Int(nalLength)
                guard nalEnd <= frameEnd, nalLength > 20 else { break }

                let nalType = data[nalStart] & 0x1F
                // Target IDR (5) and non-IDR (1) slices
                if nalType == 5 || nalType == 1 {
                    let corruptStart = nalStart + 20  // Skip slice header
                    let corruptLength = nalEnd - corruptStart
                    if corruptLength > 0 {
                        let flipCount = max(1, corruptLength / 20) // ~5%
                        for _ in 0..<flipCount {
                            let idx = corruptStart + Int.random(in: 0..<corruptLength)
                            data[idx] = data[idx] ^ UInt8.random(in: 1...255)
                        }
                    }
                }

                pos = nalEnd
            }
        }

        try data.write(to: url)
    }
}
