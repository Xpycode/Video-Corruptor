import Foundation

/// Every corruption type that VideoCorruptor can apply.
/// Mapped to VideoAnalyzer's IssueType categories.
enum CorruptionType: String, CaseIterable, Identifiable, Sendable {
    // File-level (format-agnostic)
    case truncation
    case zeroByteFile
    case fakeExtension

    // Container-level (MP4/MOV)
    case corruptHeader
    case timestampGap
    case decodeError
    case missingVideoTrack
    case missingAudioTrack
    case containerStructure

    // Index table (MP4/MOV)
    case chunkOffsetShift
    case keyframeRemoval
    case sampleSizeCorruption

    // Bitstream (MP4/MOV)
    case iFrameDatamosh
    case targetedFrameCorruption

    // MXF
    case mxfEssenceCorruption
    case mxfKLVKeyCorruption
    case mxfBERLengthManipulation
    case mxfPartitionBreakage
    case mxfIndexScrambling

    var id: String { rawValue }

    var label: String {
        switch self {
        case .truncation: "Truncation"
        case .corruptHeader: "Corrupt Header"
        case .timestampGap: "Timestamp Gap"
        case .decodeError: "Decode Error (byte flip)"
        case .missingVideoTrack: "Missing Video Track"
        case .missingAudioTrack: "Missing Audio Track"
        case .containerStructure: "Malformed Container"
        case .zeroByteFile: "Zero-Byte File"
        case .fakeExtension: "Fake Extension"
        case .chunkOffsetShift: "Chunk Offset Shift"
        case .keyframeRemoval: "Keyframe Removal"
        case .sampleSizeCorruption: "Sample Size Corruption"
        case .iFrameDatamosh: "I-Frame Datamosh"
        case .targetedFrameCorruption: "Targeted Frame Corruption"
        case .mxfEssenceCorruption: "Essence Corruption"
        case .mxfKLVKeyCorruption: "KLV Key Corruption"
        case .mxfBERLengthManipulation: "BER Length Manipulation"
        case .mxfPartitionBreakage: "Partition Breakage"
        case .mxfIndexScrambling: "Index Scrambling"
        }
    }

    var description: String {
        switch self {
        case .truncation:
            "Cuts the file at a random point, simulating incomplete download or transfer"
        case .corruptHeader:
            "Damages the moov/ftyp atoms so the container can't be parsed correctly"
        case .timestampGap:
            "Introduces discontinuities in the time-to-sample table"
        case .decodeError:
            "Flips random bytes inside frame data (mdat), causing decode failures"
        case .missingVideoTrack:
            "Removes the video trak atom from the container"
        case .missingAudioTrack:
            "Removes the audio trak atom from the container"
        case .containerStructure:
            "Corrupts atom sizes or types to create malformed container structure"
        case .zeroByteFile:
            "Creates an empty file with the original extension"
        case .fakeExtension:
            "Writes random non-video data with a .mp4/.mov extension"
        case .chunkOffsetShift:
            "Shifts stco/co64 chunk offsets by 1-50 bytes, causing block artifacts and color smearing"
        case .keyframeRemoval:
            "Sets stss sync sample count to zero, breaking random access and seeking"
        case .sampleSizeCorruption:
            "Corrupts ~10% of stsz sample size entries, causing truncated or merged frames"
        case .iFrameDatamosh:
            "Changes IDR NAL type to non-IDR, causing cascading visual decay through the GOP"
        case .targetedFrameCorruption:
            "Flips ~5% of bytes in keyframe NAL units, skipping slice headers for controlled damage"
        case .mxfEssenceCorruption:
            "XORs ~2% of bytes in picture essence payloads, skipping codec headers"
        case .mxfKLVKeyCorruption:
            "Alters the item-type byte in ~30% of picture essence KLV keys"
        case .mxfBERLengthManipulation:
            "Shortens BER-encoded value lengths by 10-50%, causing cascading parse failures"
        case .mxfPartitionBreakage:
            "Zeros the FooterPartition offset in the header partition pack"
        case .mxfIndexScrambling:
            "Swaps 8-byte blocks within index table segment values"
        }
    }

    var icon: String {
        switch self {
        case .truncation: "scissors"
        case .corruptHeader: "doc.badge.gearshape"
        case .timestampGap: "clock.badge.exclamationmark"
        case .decodeError: "film.stack.fill"
        case .missingVideoTrack: "video.slash"
        case .missingAudioTrack: "speaker.slash"
        case .containerStructure: "square.stack.3d.up.slash"
        case .zeroByteFile: "doc"
        case .fakeExtension: "doc.questionmark"
        case .chunkOffsetShift: "arrow.right.doc.on.clipboard"
        case .keyframeRemoval: "key.slash"
        case .sampleSizeCorruption: "ruler"
        case .iFrameDatamosh: "photo.artframe"
        case .targetedFrameCorruption: "target"
        case .mxfEssenceCorruption: "waveform.path.ecg"
        case .mxfKLVKeyCorruption: "key"
        case .mxfBERLengthManipulation: "textformat.size"
        case .mxfPartitionBreakage: "rectangle.split.3x1"
        case .mxfIndexScrambling: "tablecells"
        }
    }

    /// Which layer this corruption targets.
    var category: CorruptionCategory {
        switch self {
        case .truncation, .zeroByteFile, .fakeExtension:
            .file
        case .corruptHeader, .containerStructure, .missingVideoTrack, .missingAudioTrack:
            .container
        case .timestampGap, .decodeError:
            .stream
        case .chunkOffsetShift, .keyframeRemoval, .sampleSizeCorruption:
            .indexTable
        case .iFrameDatamosh, .targetedFrameCorruption:
            .bitstream
        case .mxfEssenceCorruption, .mxfKLVKeyCorruption, .mxfBERLengthManipulation,
             .mxfPartitionBreakage, .mxfIndexScrambling:
            .mxf
        }
    }

    /// Which video formats this corruption type can be applied to.
    var supportedFormats: Set<VideoFormat> {
        switch category {
        case .file:
            [.mp4, .mxf]
        case .container, .stream, .indexTable, .bitstream:
            [.mp4]
        case .mxf:
            [.mxf]
        }
    }

    /// Short description of the corruption result for display in results list.
    var resultDescription: String {
        switch self {
        case .truncation: "File truncated at 60% of original size"
        case .corruptHeader: "ftyp atom type field overwritten with random bytes"
        case .timestampGap: "stts sample durations corrupted to create timestamp discontinuity"
        case .decodeError: "~1% of mdat bytes flipped to cause decode failures"
        case .missingVideoTrack: "Video trak atom type zeroed out"
        case .missingAudioTrack: "Audio trak atom type zeroed out"
        case .containerStructure: "moov atom size inflated to create malformed structure"
        case .zeroByteFile: "Empty file created with original extension"
        case .fakeExtension: "1KB of random data written with video extension"
        case .chunkOffsetShift: "stco/co64 chunk offsets shifted by random 1-50 bytes"
        case .keyframeRemoval: "stss sync sample entry count set to zero"
        case .sampleSizeCorruption: "~10% of stsz sample size entries corrupted"
        case .iFrameDatamosh: "IDR NAL types changed to non-IDR for datamosh effect"
        case .targetedFrameCorruption: "~5% of keyframe NAL bytes flipped (headers preserved)"
        case .mxfEssenceCorruption: "~2% of picture essence payload bytes XORed"
        case .mxfKLVKeyCorruption: "Item-type byte altered in ~30% of picture essence KLV keys"
        case .mxfBERLengthManipulation: "BER value lengths shortened by 10-50%"
        case .mxfPartitionBreakage: "FooterPartition offset zeroed in header partition pack"
        case .mxfIndexScrambling: "8-byte blocks swapped within index table segment values"
        }
    }
}

enum CorruptionCategory: String, CaseIterable, Identifiable, Sendable {
    case file
    case container
    case stream
    case indexTable
    case bitstream
    case mxf

    var id: String { rawValue }

    var label: String {
        switch self {
        case .file: "File-Level"
        case .container: "Container-Level"
        case .stream: "Stream-Level"
        case .indexTable: "Index Table"
        case .bitstream: "Bitstream"
        case .mxf: "MXF"
        }
    }
}
