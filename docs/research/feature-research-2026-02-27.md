# Feature Research: Severity, Stacking, Seeds, Batch Processing

**Date:** 2026-02-27
**Status:** Research complete, pending implementation

---

## 1. Multi-Corruption Stacking

### Problem
Each selected corruption produces a separate output file. No way to apply 2+ corruptions to one file.

### Architecture: Phase-Based Pipeline

Corruptions declare an execution phase. Applied inner-to-outer so each phase can parse what it needs:

```
Phase 0: Bitstream   — NAL unit modifications in mdat
Phase 1: Index Table — stco, stss, stsz modifications in moov
Phase 2: Stream      — stts, ctts timing metadata
Phase 3: Container   — moov, trak, ftyp atom structure
Phase 4: File        — truncation (must be last)
```

### Conflict Rules

| Corruption | Constraint |
|---|---|
| `zeroByteFile`, `fakeExtension` | Exclusive — cannot combine with anything |
| `truncation` | Must be last; may remove moov, invalidating prior atom-based work |
| `missingVideoTrack` | Blocks all video-targeting corruptions (stco, stss, stsz, frame map) |
| `containerStructure` | May break subsequent atom parsing (moov size inflated) |
| `corruptHeader` | Cosmetic — does not affect atom parsing, freely stackable |

### Freely Stackable Groups

- All index table types (`chunkOffsetShift` + `keyframeRemoval` + `sampleSizeCorruption`) — different atoms, no overlap
- Bitstream types (`iFrameDatamosh` + `targetedFrameCorruption`) — different byte positions within frames
- Cross-layer (any bitstream + any index table) — mdat vs moov, disjoint byte ranges
- `timestampGap` + any index table — stts vs stco/stss/stsz

### Dual Mode

Keep current "individual" mode (one file per type, for test suites) and add "stacked" mode (all selected on one file, for realistic failure simulation).

```swift
enum CorruptionMode: String, CaseIterable, Sendable {
    case individual  // Current: one output file per corruption type
    case stacked     // New: all corruptions on one output file
}
```

### Implementation Pattern

```swift
func corruptStacked(source: VideoFile, types: [CorruptionType], outputURL: URL) throws {
    try FileManager.default.copyItem(at: source.url, to: outputURL)
    let sorted = types.sorted { $0.phase < $1.phase }
    for type in sorted {
        try applyMutation(type: type, to: outputURL, source: source)
    }
}
```

All current corruptions are in-place byte overwrites (no insert/delete), so offsets parsed from original data remain valid through the pipeline — except `truncation` which shortens the file (hence: last).

### Conflict Detection

```swift
static func findConflicts(in selection: Set<CorruptionType>) -> [CorruptionConflict]
```

Show warnings in UI when incompatible types are selected. Three severity levels: `.warning`, `.exclusive`, `.destructive`.

---

## 2. Severity/Intensity Controls

### Problem
All corruption parameters are hardcoded (truncation always 60%, byte flip always 1%, etc.).

### Architecture: Normalized 0-1 Intensity

Single `CorruptionSeverity` struct with normalized 0.0-1.0 intensity. Each handler maps it to its specific parameter range.

```swift
struct CorruptionSeverity: Codable, Sendable, Equatable {
    var intensity: Double  // 0.0 (minimum) to 1.0 (maximum)

    static let subtle   = CorruptionSeverity(intensity: 0.15)
    static let moderate = CorruptionSeverity(intensity: 0.40)
    static let heavy    = CorruptionSeverity(intensity: 0.70)
    static let extreme  = CorruptionSeverity(intensity: 1.0)
}
```

### Per-Type Mapping

| Type | 0.0 (Subtle) | 1.0 (Extreme) |
|---|---|---|
| Truncation | Keep 95% | Keep 1% |
| Decode Error (byte flip) | 0.1% of mdat | 50% |
| Chunk Offset Shift | 1-5 bytes | 100-500 bytes |
| Sample Size Corruption | 1% of entries | 100% |
| Targeted Frame Corruption | 0.5% of bytes | 50% |
| MXF Essence | 0.5% | 30% |
| MXF KLV Key | 5% of keys | 100% |
| MXF BER Length | 5% reduction | 80-95% reduction |

### Types Without Severity (Binary)

`zeroByteFile`, `fakeExtension`, `keyframeRemoval`, `corruptHeader`, `containerStructure`, `missingVideoTrack`, `missingAudioTrack`, `timestampGap`, `iFrameDatamosh`, `mxfPartitionBreakage`, `mxfIndexScrambling`

### Data Model

`[CorruptionType: CorruptionSeverity]` dictionary in ViewModel. No enum surgery. Types not in dict use `.default` (moderate).

### UX

- Expandable inline sliders in sidebar (disclosure via slider icon)
- Severity badge (Subtle/Moderate/Heavy/Extreme) on each selected type
- Global severity preset buttons (S/M/H/X)
- Slider shows concrete meaning per type ("Keep 60%", "0.5%", "1-5B")

---

## 3. Reproducible Seed System

### Problem
Uses `UInt8.random(in:)` etc. with no seed. Can't reproduce a specific corruption.

### Architecture: Xoshiro256** with Sub-Seed Derivation

```swift
struct SeededRNG: RandomNumberGenerator, Sendable {
    // Xoshiro256** — 256-bit state, period 2^256-1
    // Initialized from UInt64 seed via SplitMix64 expansion
}
```

### Sub-Seed Derivation

Each corruption type gets an independent PRNG, derived deterministically:

```
sub_seed = FNV-1a(master_seed XOR hash(corruption_type.rawValue))
```

This means adding/removing types doesn't change other types' output. Order doesn't matter.

### Seed UX

- **Format:** 8-character uppercase hex (UInt32 range, 4B+ possibilities)
- **Display:** Editable text field + refresh button + copy button
- **Auto-generate** on launch, display prominently
- **Include in output filename:** `video_seed-A7F3B2C1_truncation.mp4`

### Integration

All `.random(in:)` calls get `using: &rng` parameter. Data extension methods accept `inout some RandomNumberGenerator`.

```swift
// Before
let offset = Int.random(in: range)

// After
var rng = context.rng(for: type)
let offset = Int.random(in: range, using: &rng)
```

Thread-safe by design — value-type RNG, each operation owns its own copy.

---

## 4. Batch Processing

### Problem
Only one source file at a time. Can't process a folder of videos.

### Architecture: Compressor-Style Matrix

N source files × M corruption types = N×M jobs. TaskGroup with bounded concurrency.

### Input Methods

- `NSOpenPanel` with `allowsMultipleSelection = true`
- Folder drop (expand recursively for video files)
- Drag-and-drop of multiple files

### Processing

```swift
await withTaskGroup(of: Void.self) { group in
    // Bounded concurrency: 2-4 parallel based on file size
    // Cooperative cancellation via Task.checkCancellation()
}
```

| File Size | Concurrency |
|---|---|
| < 100MB | 4 parallel |
| 100-500MB | 3 parallel |
| > 500MB | 2 parallel |

### Error Handling

User-selectable: **Skip & Continue** (default) or **Stop on Error**.

### Output Organization

Per-source subfolders:

```
OutputFolder/
  sample_001.mp4/
    sample_001_truncation.mp4
    sample_001_corruptHeader.mp4
  sample_002.mov/
    sample_002_truncation.mov
  batch_manifest.json
```

### Batch Manifest (JSON)

Maps every input to every output with status, size, duration, error. Consumable by VideoAnalyzer/VCR.

### Queue UX

- Per-job row: status icon, filename, corruption type, progress bar
- Overall progress header with ETA
- Cancel/pause support
- "Reveal in Finder" on completion

---

## Files Impact Summary

### New Files

| File | Purpose |
|---|---|
| `Models/CorruptionSeverity.swift` | Severity struct with presets |
| `Models/CorruptionMode.swift` | Individual vs stacked enum |
| `Models/CorruptionConflict.swift` | Conflict detection |
| `Models/CorruptionContext.swift` | Seed + severity + mode context |
| `Models/BatchJob.swift` | Batch job model |
| `Models/BatchManifest.swift` | JSON manifest for batch output |
| `Services/SeededRNG.swift` | Xoshiro256** + SplitMix64 + derivation |
| `ViewModels/BatchViewModel.swift` | Batch queue management |
| `Views/SeveritySliderRow.swift` | Reusable slider component |
| `Views/SeedControlView.swift` | Seed display/edit/copy |
| `Views/BatchView.swift` | Batch mode UI |
| `Views/BatchJobRow.swift` | Per-job row in queue |

### Modified Files

| File | Changes |
|---|---|
| `Models/CorruptionType.swift` | Add `phase`, `hasSeverityControl`, `severityDescription(for:)`, conflict rules |
| `Models/CorruptionResult.swift` | Add `severity`, `seed` fields |
| `Models/CorruptionPreset.swift` | Add default severity per preset |
| `Services/CorruptionHandler.swift` | Add `severity` + `rng` parameters to `apply()` |
| `Services/CorruptionEngine.swift` | Add stacked mode, pass severity/seed through, conflict checking |
| `Services/Corruptors/FileCorruptor.swift` | Use severity in truncation |
| `Services/Corruptors/MP4Corruptor.swift` | Use severity in 5 methods, use seeded RNG |
| `Services/Corruptors/MXFCorruptor.swift` | Use severity in 3 methods, use seeded RNG |
| `Services/MP4Parser/Data+BigEndian.swift` | Add `using: &rng` variants for random operations |
| `ViewModels/CorruptorViewModel.swift` | Add severities dict, seed text, corruption mode |
| `Views/SidebarView.swift` | Expandable severity sliders, mode toggle |
| `Views/DetailView.swift` | Show seed, severity in results |
| `Views/ContentView.swift` | Tab/navigation for batch mode |

---

## Sources

- [Real-Time Corruptor (RTCV)](https://github.com/redscientistlabs/RTCV) — Blast Layer stacking model
- [Mosh-Pro](https://moshpro.app/) — Effect stack UX pattern
- [Datamosher-Pro](https://github.com/Akascape/Datamosher-Pro) — Sequential chaining
- [FFmpeg BSF Documentation](https://ffmpeg.org/ffmpeg-bitstream-filters.html) — Pipeline chain model
- [RTC Corruption Engines](https://corrupt.wiki/rtcv/rtc/corruption-engines) — Blast unit architecture
- [Procreate Glitch Effect](https://help.procreate.com/procreate/handbook/adjustments/adjustments-glitch) — Amount slider pattern
- [Audacity Distortion](https://manual.audacityteam.org/man/distortion.html) — Multi-parameter effects
- [Swift SE-0202](https://github.com/apple/swift-evolution/blob/main/proposals/0202-random-unification.md) — RandomNumberGenerator protocol
