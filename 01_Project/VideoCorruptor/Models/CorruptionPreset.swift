import Foundation

/// Quick-select presets for batch corruption.
enum CorruptionPreset: String, CaseIterable, Identifiable, Sendable {
    case allTypes
    case containerOnly
    case streamOnly
    case fileOnly
    case indexTableOnly
    case bitstreamOnly
    case mxfOnly
    case repairTestSuite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allTypes: "All Types"
        case .containerOnly: "Container Only"
        case .streamOnly: "Stream Only"
        case .fileOnly: "File Only"
        case .indexTableOnly: "Index Table Only"
        case .bitstreamOnly: "Bitstream Only"
        case .mxfOnly: "MXF Only"
        case .repairTestSuite: "VCR Repair Test Suite"
        }
    }

    var description: String {
        switch self {
        case .allTypes:
            "Generate one corrupted file for every corruption type available for this format"
        case .containerOnly:
            "Container-level corruptions: headers, structure, missing tracks"
        case .streamOnly:
            "Stream-level corruptions: timestamp gaps, decode errors"
        case .fileOnly:
            "File-level corruptions: truncation, zero-byte, fake extension"
        case .indexTableOnly:
            "Index table corruptions: chunk offsets, keyframes, sample sizes"
        case .bitstreamOnly:
            "Bitstream corruptions: I-frame datamosh, targeted frame damage"
        case .mxfOnly:
            "MXF corruptions: essence, KLV keys, BER lengths, partitions, index"
        case .repairTestSuite:
            "Corruptions that VCR's remux should be able to fix"
        }
    }

    /// Return the corruption types for a given format.
    func types(for format: VideoFormat?) -> [CorruptionType] {
        let base: [CorruptionType] = switch self {
        case .allTypes:
            CorruptionType.allCases
        case .containerOnly:
            CorruptionType.allCases.filter { $0.category == .container }
        case .streamOnly:
            CorruptionType.allCases.filter { $0.category == .stream }
        case .fileOnly:
            CorruptionType.allCases.filter { $0.category == .file }
        case .indexTableOnly:
            CorruptionType.allCases.filter { $0.category == .indexTable }
        case .bitstreamOnly:
            CorruptionType.allCases.filter { $0.category == .bitstream }
        case .mxfOnly:
            CorruptionType.allCases.filter { $0.category == .mxf }
        case .repairTestSuite:
            [.truncation, .corruptHeader, .missingAudioTrack, .containerStructure]
        }

        guard let format else { return base }
        return base.filter { $0.supportedFormats.contains(format) }
    }

    /// Whether this preset has any applicable types for a given format.
    func isAvailable(for format: VideoFormat?) -> Bool {
        !types(for: format).isEmpty
    }
}
