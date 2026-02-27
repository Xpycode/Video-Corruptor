import Foundation

/// Describes a conflict between selected corruption types when stacking.
struct CorruptionConflict: Identifiable, Sendable {
    let id = UUID()
    let types: [CorruptionType]
    let message: String
    let severity: ConflictSeverity

    enum ConflictSeverity: Sendable {
        case blocker    // Cannot stack these at all
        case warning    // Can stack, but results may be unexpected
    }

    /// Detect all conflicts in a set of selected types.
    static func detect(in selected: Set<CorruptionType>) -> [CorruptionConflict] {
        var conflicts: [CorruptionConflict] = []

        // zeroByteFile or fakeExtension with anything else
        let exclusiveTypes: Set<CorruptionType> = [.zeroByteFile, .fakeExtension]
        let hasExclusive = !selected.intersection(exclusiveTypes).isEmpty
        let hasOthers = !selected.subtracting(exclusiveTypes).isEmpty
        if hasExclusive && hasOthers {
            let exclusive = selected.intersection(exclusiveTypes)
            conflicts.append(CorruptionConflict(
                types: Array(exclusive),
                message: "\(exclusive.map(\.label).joined(separator: "/")) replaces entire file — other corruptions have no effect",
                severity: .blocker
            ))
        }

        // missingVideoTrack with video-targeting types
        let videoTargeting: Set<CorruptionType> = [
            .iFrameDatamosh, .targetedFrameCorruption, .decodeError,
            .chunkOffsetShift, .keyframeRemoval, .sampleSizeCorruption, .timestampGap
        ]
        if selected.contains(.missingVideoTrack) {
            let affected = selected.intersection(videoTargeting)
            if !affected.isEmpty {
                conflicts.append(CorruptionConflict(
                    types: [.missingVideoTrack] + Array(affected),
                    message: "Missing Video Track removes the track that \(affected.map(\.label).joined(separator: ", ")) targets",
                    severity: .blocker
                ))
            }
        }

        // truncation with atom-based types
        let atomBased: Set<CorruptionType> = [
            .corruptHeader, .containerStructure, .missingVideoTrack, .missingAudioTrack,
            .timestampGap, .decodeError, .chunkOffsetShift, .keyframeRemoval,
            .sampleSizeCorruption, .iFrameDatamosh, .targetedFrameCorruption
        ]
        if selected.contains(.truncation) {
            let affected = selected.intersection(atomBased)
            if !affected.isEmpty {
                conflicts.append(CorruptionConflict(
                    types: [.truncation] + Array(affected),
                    message: "Truncation may remove atoms needed by \(affected.map(\.label).joined(separator: ", "))",
                    severity: .warning
                ))
            }
        }

        // containerStructure with subsequent parsing-dependent types
        if selected.contains(.containerStructure) {
            let parsingDependent: Set<CorruptionType> = [
                .timestampGap, .decodeError, .chunkOffsetShift, .keyframeRemoval,
                .sampleSizeCorruption, .iFrameDatamosh, .targetedFrameCorruption
            ]
            let affected = selected.intersection(parsingDependent)
            if !affected.isEmpty {
                conflicts.append(CorruptionConflict(
                    types: [.containerStructure] + Array(affected),
                    message: "Malformed container may prevent parsing needed by \(affected.map(\.label).joined(separator: ", "))",
                    severity: .warning
                ))
            }
        }

        return conflicts
    }
}
