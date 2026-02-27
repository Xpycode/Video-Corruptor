import Foundation

/// Defines the execution order for stacked corruptions.
/// Lower raw value = applied first (inner layers first, file-level last).
enum CorruptionPhase: Int, Comparable, Sendable {
    case bitstream = 0
    case indexTable = 1
    case stream = 2
    case container = 3
    case file = 4

    static func < (lhs: CorruptionPhase, rhs: CorruptionPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .bitstream: "Bitstream"
        case .indexTable: "Index Table"
        case .stream: "Stream"
        case .container: "Container"
        case .file: "File"
        }
    }
}
