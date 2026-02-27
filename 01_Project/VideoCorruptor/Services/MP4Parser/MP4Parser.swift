import Foundation

/// Lightweight MP4/MOV container parser.
/// Reads the atom tree structure without decoding media data.
struct MP4Parser: Sendable {

    enum ParseError: Error, LocalizedError {
        case fileNotFound
        case fileTooSmall
        case invalidAtomSize(offset: UInt64)
        case readError(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound: "File not found"
            case .fileTooSmall: "File too small to be a valid MP4/MOV"
            case .invalidAtomSize(let offset): "Invalid atom size at offset \(offset)"
            case .readError(let msg): "Read error: \(msg)"
            }
        }
    }

    /// Parse top-level atoms from a file.
    func parse(url: URL) throws -> [MP4Atom] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParseError.fileNotFound
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize >= 8 else {
            throw ParseError.fileTooSmall
        }

        handle.seek(toFileOffset: 0)
        return try parseAtoms(handle: handle, rangeStart: 0, rangeEnd: fileSize)
    }

    /// Parse atoms within a byte range, recursing into container atoms.
    private func parseAtoms(handle: FileHandle, rangeStart: UInt64, rangeEnd: UInt64) throws -> [MP4Atom] {
        var atoms: [MP4Atom] = []
        var offset = rangeStart

        while offset < rangeEnd {
            handle.seek(toFileOffset: offset)

            // Read size (4 bytes) + type (4 bytes)
            let headerData = handle.readData(ofLength: 8)
            guard headerData.count == 8 else { break }

            let rawSize = UInt64(headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            let typeBytes = headerData.subdata(in: 4..<8)
            let type = String(data: typeBytes, encoding: .ascii) ?? "????"

            var atomSize: UInt64
            var headerSize: UInt64 = 8

            if rawSize == 1 {
                // Extended size: next 8 bytes
                let extData = handle.readData(ofLength: 8)
                guard extData.count == 8 else { break }
                atomSize = extData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                headerSize = 16
            } else if rawSize == 0 {
                // Atom extends to end of file
                atomSize = rangeEnd - offset
            } else {
                atomSize = rawSize
            }

            guard atomSize >= headerSize else {
                throw ParseError.invalidAtomSize(offset: offset)
            }

            var children: [MP4Atom] = []
            if MP4Atom.containerTypes.contains(type) {
                let childStart = offset + headerSize
                let childEnd = offset + atomSize
                if childEnd <= rangeEnd {
                    children = try parseAtoms(handle: handle, rangeStart: childStart, rangeEnd: childEnd)
                }
            }

            let atom = MP4Atom(
                type: type,
                offset: offset,
                size: atomSize,
                headerSize: headerSize,
                children: children
            )
            atoms.append(atom)

            offset += atomSize
        }

        return atoms
    }

    /// Find all atoms of a given type in the tree.
    func findAtoms(type: String, in atoms: [MP4Atom]) -> [MP4Atom] {
        var results: [MP4Atom] = []
        for atom in atoms {
            if atom.type == type {
                results.append(atom)
            }
            results.append(contentsOf: findAtoms(type: type, in: atom.children))
        }
        return results
    }

    /// Find the first atom of a given type.
    func findFirst(type: String, in atoms: [MP4Atom]) -> MP4Atom? {
        findAtoms(type: type, in: atoms).first
    }
}
