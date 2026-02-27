# VideoCorruptor

A macOS developer tool that intentionally corrupts video files in specific, controlled ways to generate test files for VideoAnalyzer and VCR.

## Tech Stack

- **Platform:** macOS 15+ (Sequoia)
- **UI:** SwiftUI
- **Language:** Swift 6, strict concurrency
- **Project:** XcodeGen (`01_Project/project.yml`)
- **Dependencies:** None (pure Apple frameworks)
- **Sandbox:** Disabled (hardened runtime for file access)

## Architecture

- **MVVM** with `@Observable` view model
- **Custom MP4 Parser** - lightweight atom tree reader for surgical corruption
- **Binary Mutation** - direct byte manipulation for file-level corruption
- **Copy-only** - never modifies original files

## Key Files

| File | Purpose |
|------|---------|
| `01_Project/VideoCorruptor/Services/MP4Parser/` | MP4/MOV atom tree parser |
| `01_Project/VideoCorruptor/Services/CorruptionEngine.swift` | Orchestrates all corruption types |
| `01_Project/VideoCorruptor/Models/CorruptionType.swift` | Enum of all corruption types |
| `01_Project/VideoCorruptor/ViewModels/CorruptorViewModel.swift` | Main app state |

## Sibling Projects

- **VideoAnalyzer** (`../VideoAnalyzer/`) - Detects corruption (test target)
- **VCR** (`../VCR/`) - Repairs corruption (test target)

## Directions

Full documentation system in `docs/00_base.md`.
