import Foundation

/// Supported video container formats.
enum VideoFormat: String, Sendable {
    case mp4
    case mxf

    /// All file extensions this format covers.
    var extensions: Set<String> {
        switch self {
        case .mp4: ["mp4", "mov", "m4v"]
        case .mxf: ["mxf"]
        }
    }

    var label: String {
        switch self {
        case .mp4: "MP4/MOV"
        case .mxf: "MXF"
        }
    }

    /// All extensions across every format.
    static var allExtensions: Set<String> {
        var result = Set<String>()
        for format in [VideoFormat.mp4, .mxf] {
            result.formUnion(format.extensions)
        }
        return result
    }

    /// Detect the format from a file extension.
    static func detect(from extension: String) -> VideoFormat? {
        let ext = `extension`.lowercased()
        if VideoFormat.mp4.extensions.contains(ext) { return .mp4 }
        if VideoFormat.mxf.extensions.contains(ext) { return .mxf }
        return nil
    }
}
