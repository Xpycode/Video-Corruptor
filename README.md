# VideoCorruptor

A macOS developer tool that intentionally corrupts video files in specific, controlled ways. Built to generate test files for [Video-Analyzer](https://github.com/Xpycode/Video-Analyzer) and [VCR](https://github.com/Xpycode/VCR).

## Why

Testing video analysis and repair tools requires corrupted files that break in predictable, well-understood ways. VideoCorruptor creates these files surgically — from subtle timestamp shifts to catastrophic container damage — so you can verify that your tools detect and handle each failure mode correctly.

**Never modifies originals.** All operations work on copies.

## Corruption Types

19 corruption types across 6 categories:

### File-Level (MP4 + MXF)

| Type | What it does |
|------|-------------|
| **Truncation** | Cuts the file at a random point, simulating incomplete transfer |
| **Zero-Byte File** | Creates an empty file with the original extension |
| **Fake Extension** | Writes random non-video data with a .mp4/.mov extension |

### Container-Level (MP4/MOV)

| Type | What it does |
|------|-------------|
| **Corrupt Header** | Damages moov/ftyp atoms so the container can't be parsed |
| **Timestamp Gap** | Introduces discontinuities in the time-to-sample table |
| **Decode Error** | Flips random bytes inside mdat, causing decode failures |
| **Missing Video Track** | Removes the video trak atom |
| **Missing Audio Track** | Removes the audio trak atom |
| **Malformed Container** | Corrupts atom sizes/types to break container structure |

### Index Table (MP4/MOV)

| Type | What it does |
|------|-------------|
| **Chunk Offset Shift** | Shifts stco/co64 offsets, causing block artifacts and color smearing |
| **Keyframe Removal** | Sets sync sample count to zero, breaking seeking |
| **Sample Size Corruption** | Corrupts stsz entries, causing truncated or merged frames |

### Bitstream (MP4/MOV)

| Type | What it does |
|------|-------------|
| **I-Frame Datamosh** | Changes IDR NAL types to non-IDR, causing cascading visual decay |
| **Targeted Frame Corruption** | Flips bytes in keyframe NAL units while preserving slice headers |

### MXF

| Type | What it does |
|------|-------------|
| **Essence Corruption** | XORs bytes in picture essence payloads, skipping codec headers |
| **KLV Key Corruption** | Alters the item-type byte in picture essence KLV keys |
| **BER Length Manipulation** | Shortens BER-encoded value lengths, causing cascading parse failures |
| **Partition Breakage** | Zeros the FooterPartition offset in the header partition pack |
| **Index Scrambling** | Swaps 8-byte blocks within index table segment values |

## Severity Control

Many corruption types support a severity slider (subtle to extreme) that controls the intensity of the corruption. Binary types (like missing track or zero-byte file) are simply on/off.

## Tech Stack

- **Platform:** macOS 15+ (Sequoia)
- **Language:** Swift 6, strict concurrency
- **UI:** SwiftUI
- **Parser:** Custom MP4/MOV atom tree parser (no external dependencies)
- **Project:** XcodeGen

## Architecture

- **MVVM** with `@Observable` view model
- **Protocol-based engine** — `CorruptionHandler` protocol dispatches to `FileCorruptor`, `MP4Corruptor`, and `MXFCorruptor`
- **Enum-driven UI** — adding a new corruption type only requires editing `CorruptionType.swift` and the handler; no view changes needed

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd 01_Project
xcodegen generate
open VideoCorruptor.xcodeproj
```

## License

This project is not currently open source. For inquiries, please open an issue.
