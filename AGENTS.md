# VideoCorruptor — Codex Instructions

VideoCorruptor is a macOS developer tool that creates controlled corruptions for VideoAnalyzer and
VCR test media.

## Stack and architecture

- macOS 15+, SwiftUI, Swift 6 strict concurrency.
- XcodeGen specification: `01_Project/project.yml`; no external dependencies.
- MVVM with `@Observable`, custom MP4/MOV atom parsing, direct bounded binary mutation.
- Hardened runtime with App Sandbox disabled.

## Build and verification

```bash
xcodegen generate --spec 01_Project/project.yml
xcodebuild -project 01_Project/VideoCorruptor.xcodeproj \
  -scheme VideoCorruptor -configuration Debug build
xcodebuild test -project 01_Project/VideoCorruptor.xcodeproj \
  -scheme VideoCorruptor
```

Operations are copy-only: never modify original media. Preserve deterministic seeds, validate paths
and offsets, and report unsupported/not-applicable cases explicitly. Prove shared contracts against
the consuming VideoAnalyzer and VCR projects when they change.

## Directions

Use the globally installed `directions` skill and the master `commands/*.md` procedures. Read
`docs/PROJECT_STATE.md`, `docs/decisions.md`, and `docs/sessions/` for current evidence and handoffs.
Do not copy universal Directions docs into this repository.
