import Foundation

enum MXFPartitionLinkKind: Equatable, Sendable {
    case previous
    case footer
}

enum MXFPartitionLinkResolution: Equatable, Sendable {
    case absent
    case partition(physicalOffset: UInt64)
    case endOfFile
    case beyondEndOfFile
    case insideElement(elementOffset: UInt64)
    case nonPartitionElement(elementOffset: UInt64)
    case unknownBoundary
}

struct MXFPartitionGraphLink: Equatable, Sendable {
    let kind: MXFPartitionLinkKind
    let sourcePhysicalOffset: UInt64
    let targetOffset: UInt64
    let fieldSpan: ByteSpan
    let resolution: MXFPartitionLinkResolution
}

struct MXFPartitionGraphNode: Equatable, Sendable {
    let physicalOffset: UInt64
    let pack: MXFPartitionPackInspection
    let previous: MXFPartitionGraphLink
    let footer: MXFPartitionGraphLink
}

struct MXFPartitionGraphLimits: Equatable, Sendable {
    let maximumPartitionHops: UInt64
    let maximumVisitedOffsets: UInt64

    init(maximumPartitionHops: UInt64 = 128, maximumVisitedOffsets: UInt64 = 128) {
        self.maximumPartitionHops = maximumPartitionHops
        self.maximumVisitedOffsets = maximumVisitedOffsets
    }
}

enum MXFPartitionGraphLimit: Equatable, Sendable {
    case partitionHops
    case visitedOffsets
}

enum MXFPartitionGraphDiagnostic: Equatable, Sendable {
    case invalidPartition(offset: UInt64, error: MXFPartitionInspectionError)
    case thisPartitionMismatch(physicalOffset: UInt64, declaredOffset: UInt64, fieldSpan: ByteSpan)
    case invalidLink(MXFPartitionGraphLink)
    case invalidTraversalStart(offset: UInt64)
    case cycle(kind: MXFPartitionLinkKind, offsets: [UInt64])
    case limitExceeded(limit: MXFPartitionGraphLimit, attempted: UInt64, maximum: UInt64)
    case integerOverflow
}

struct MXFPartitionGraphTraversal: Equatable, Sendable {
    let linkKind: MXFPartitionLinkKind
    let path: [UInt64]
    let visitedPhysicalOffsets: Set<UInt64>
    let hopCount: UInt64
    let terminatedAt: MXFPartitionLinkResolution?
}

struct MXFPartitionGraph: Equatable, Sendable {
    let inputByteCount: UInt64
    let nodesByPhysicalOffset: [UInt64: MXFPartitionGraphNode]
    let traversal: MXFPartitionGraphTraversal
    let diagnostics: [MXFPartitionGraphDiagnostic]
}

struct MXFPartitionGraphInspector: Sendable {
    private let partitionInspector = MXFPartitionInspector()

    func inspect(
        fileAt url: URL,
        structuralFile: MXFInspectedFile,
        traversalStartOffset: UInt64,
        following linkKind: MXFPartitionLinkKind = .previous,
        limits: MXFPartitionGraphLimits = MXFPartitionGraphLimits()
    ) throws -> MXFPartitionGraph {
        var parsedPacks: [UInt64: MXFPartitionPackInspection] = [:]
        var diagnostics: [MXFPartitionGraphDiagnostic] = []

        for element in structuralFile.elements {
            guard partitionInspector.classify(key: element.key) != nil else { continue }
            guard let valueSpan = element.valueSpan else { continue }
            let result = try partitionInspector.inspect(
                fileAt: url,
                key: element.key,
                keySpan: element.keySpan,
                valueOffset: valueSpan.lowerBound,
                declaredValueLength: valueSpan.length
            )
            switch result {
            case .partitionPack(let pack):
                let physicalOffset = element.keySpan.lowerBound
                parsedPacks[physicalOffset] = pack
                if pack.thisPartition.value != physicalOffset {
                    diagnostics.append(.thisPartitionMismatch(
                        physicalOffset: physicalOffset,
                        declaredOffset: pack.thisPartition.value,
                        fieldSpan: pack.thisPartition.span
                    ))
                }
            case .invalid(let error):
                diagnostics.append(.invalidPartition(offset: element.keySpan.lowerBound, error: error))
            case .notPartitionPack:
                break
            }
        }

        var nodes: [UInt64: MXFPartitionGraphNode] = [:]
        for physicalOffset in parsedPacks.keys.sorted() {
            guard let pack = parsedPacks[physicalOffset] else { continue }
            let previous = link(
                kind: .previous, source: physicalOffset, target: pack.previousPartition.value,
                fieldSpan: pack.previousPartition.span, fileSize: structuralFile.inputByteCount,
                elements: structuralFile.elements, partitions: parsedPacks
            )
            let footer = link(
                kind: .footer, source: physicalOffset, target: pack.footerPartition.value,
                fieldSpan: pack.footerPartition.span, fileSize: structuralFile.inputByteCount,
                elements: structuralFile.elements, partitions: parsedPacks
            )
            let node = MXFPartitionGraphNode(
                physicalOffset: physicalOffset, pack: pack, previous: previous, footer: footer
            )
            nodes[physicalOffset] = node
            if isInvalid(previous.resolution) { diagnostics.append(.invalidLink(previous)) }
            if isInvalid(footer.resolution) { diagnostics.append(.invalidLink(footer)) }
        }

        let traversalResult = traverse(
            nodes: nodes, start: traversalStartOffset, linkKind: linkKind, limits: limits
        )
        diagnostics.append(contentsOf: traversalResult.diagnostics)
        return MXFPartitionGraph(
            inputByteCount: structuralFile.inputByteCount,
            nodesByPhysicalOffset: nodes,
            traversal: traversalResult.traversal,
            diagnostics: diagnostics
        )
    }

    private func link(
        kind: MXFPartitionLinkKind,
        source: UInt64,
        target: UInt64,
        fieldSpan: ByteSpan,
        fileSize: UInt64,
        elements: [MXFInspectedElement],
        partitions: [UInt64: MXFPartitionPackInspection]
    ) -> MXFPartitionGraphLink {
        let resolution: MXFPartitionLinkResolution
        if target == 0 {
            resolution = .absent
        } else if partitions[target] != nil {
            resolution = .partition(physicalOffset: target)
        } else if target == fileSize {
            resolution = .endOfFile
        } else if target > fileSize {
            resolution = .beyondEndOfFile
        } else if let exact = elements.first(where: { $0.keySpan.lowerBound == target }) {
            resolution = partitionInspector.classify(key: exact.key) == nil
                ? .nonPartitionElement(elementOffset: target)
                : .unknownBoundary
        } else if let containing = elements.first(where: { $0.physicalSpan.contains(target) }) {
            resolution = .insideElement(elementOffset: containing.keySpan.lowerBound)
        } else {
            resolution = .unknownBoundary
        }
        return MXFPartitionGraphLink(
            kind: kind, sourcePhysicalOffset: source, targetOffset: target,
            fieldSpan: fieldSpan, resolution: resolution
        )
    }

    private func traverse(
        nodes: [UInt64: MXFPartitionGraphNode],
        start: UInt64,
        linkKind: MXFPartitionLinkKind,
        limits: MXFPartitionGraphLimits
    ) -> (traversal: MXFPartitionGraphTraversal, diagnostics: [MXFPartitionGraphDiagnostic]) {
        guard nodes[start] != nil else {
            return (
                MXFPartitionGraphTraversal(linkKind: linkKind, path: [],
                                           visitedPhysicalOffsets: [], hopCount: 0,
                                           terminatedAt: nil),
                [.invalidTraversalStart(offset: start)]
            )
        }
        guard limits.maximumVisitedOffsets > 0 else {
            return (
                MXFPartitionGraphTraversal(linkKind: linkKind, path: [],
                                           visitedPhysicalOffsets: [], hopCount: 0,
                                           terminatedAt: nil),
                [.limitExceeded(limit: .visitedOffsets, attempted: 1, maximum: 0)]
            )
        }

        var current = start
        var path = [start]
        var visited: Set<UInt64> = [start]
        var hops: UInt64 = 0
        var diagnostics: [MXFPartitionGraphDiagnostic] = []
        var terminatedAt: MXFPartitionLinkResolution?

        while let node = nodes[current] {
            let edge = linkKind == .previous ? node.previous : node.footer
            if case .absent = edge.resolution {
                terminatedAt = .absent
                break
            }
            let attemptedHop: UInt64
            do { attemptedHop = try CheckedBinaryArithmetic.add(hops, 1) }
            catch {
                diagnostics.append(.integerOverflow)
                break
            }
            guard attemptedHop <= limits.maximumPartitionHops else {
                diagnostics.append(.limitExceeded(
                    limit: .partitionHops, attempted: attemptedHop,
                    maximum: limits.maximumPartitionHops
                ))
                break
            }
            hops = attemptedHop

            guard case .partition(let target) = edge.resolution else {
                terminatedAt = edge.resolution
                break
            }
            if visited.contains(target) {
                path.append(target)
                let cycleStart = path.firstIndex(of: target) ?? 0
                diagnostics.append(.cycle(kind: linkKind, offsets: Array(path[cycleStart...])))
                break
            }
            let attemptedVisited: UInt64
            do { attemptedVisited = try CheckedBinaryArithmetic.add(UInt64(visited.count), 1) }
            catch {
                diagnostics.append(.integerOverflow)
                break
            }
            guard attemptedVisited <= limits.maximumVisitedOffsets else {
                diagnostics.append(.limitExceeded(
                    limit: .visitedOffsets, attempted: attemptedVisited,
                    maximum: limits.maximumVisitedOffsets
                ))
                break
            }
            visited.insert(target)
            path.append(target)
            current = target
        }
        return (
            MXFPartitionGraphTraversal(linkKind: linkKind, path: path,
                                       visitedPhysicalOffsets: visited, hopCount: hops,
                                       terminatedAt: terminatedAt),
            diagnostics
        )
    }

    private func isInvalid(_ resolution: MXFPartitionLinkResolution) -> Bool {
        switch resolution {
        case .absent, .partition:
            return false
        case .endOfFile, .beyondEndOfFile, .insideElement,
             .nonPartitionElement, .unknownBoundary:
            return true
        }
    }
}
