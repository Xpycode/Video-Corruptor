import Foundation

/// Represents a source video file dropped into the app.
struct VideoFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let fileName: String
    let fileSize: Int64
    let fileExtension: String
    let detectedFormat: VideoFormat?

    init(url: URL) {
        self.url = url
        self.fileName = url.lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.detectedFormat = VideoFormat.detect(from: url.pathExtension)

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        self.fileSize = size
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var isSupported: Bool {
        detectedFormat != nil
    }
}
