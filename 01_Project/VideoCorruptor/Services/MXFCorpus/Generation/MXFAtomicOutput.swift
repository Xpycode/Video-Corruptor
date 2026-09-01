import Foundation

enum MXFAtomicOutputError: Error, Equatable, Sendable {
    case invalidDestination
    case destinationAlreadyExists
    case parentIsNotDirectory
    case unableToCreateStagingDirectory
}

struct MXFAtomicOutput: Sendable {
    let destinationURL: URL
    let stagingURL: URL

    init(destinationURL: URL, fileManager: FileManager = .default) throws {
        let destination = destinationURL.standardizedFileURL
        guard destination.isFileURL,
              !destination.lastPathComponent.isEmpty,
              destination.path != "/" else {
            throw MXFAtomicOutputError.invalidDestination
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw MXFAtomicOutputError.destinationAlreadyExists
        }

        let parent = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MXFAtomicOutputError.parentIsNotDirectory
        }

        let staging = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).staging-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        } catch {
            throw MXFAtomicOutputError.unableToCreateStagingDirectory
        }
        self.destinationURL = destination
        self.stagingURL = staging
    }

    func publish(fileManager: FileManager = .default) throws {
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw MXFAtomicOutputError.destinationAlreadyExists
        }
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
    }

    func discard(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: stagingURL)
    }
}
