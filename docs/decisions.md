# Decisions Log

This file tracks the WHY behind technical and design decisions.

---

## Decisions

### 2026-02-26 - Custom MP4 Parser Over ffmpeg
**Context:** Need to surgically corrupt specific atoms in MP4/MOV containers for test file generation.
**Options Considered:**
1. **ffmpeg** - Shell out to ffmpeg for track removal, timestamp manipulation
   - Pros: Proven, handles many formats
   - Cons: External dependency, overkill for corruption, less byte-level control
2. **AVFoundation** - Use Apple's media framework
   - Pros: Native, no deps
   - Cons: Great for reading, not for surgical byte-level corruption
3. **Custom Swift MP4 parser + binary manipulation**
   - Pros: Full control, no deps, precise atom targeting
   - Cons: Limited to MP4/MOV (acceptable for this tool)

**Decision:** Custom Swift MP4 parser + binary manipulation
**Rationale:** MP4 atoms are simple (size + type + payload). A lightweight parser gives surgical control over exactly what gets corrupted. No encoding/decoding needed - just structural manipulation.
**Consequences:** Adding MKV/WebM support would need a separate parser. Acceptable since VideoAnalyzer and VCR primarily target MP4/MOV.

### 2026-02-26 - Copy-Only File Operations
**Context:** Tool corrupts files - need safety guarantees.
**Decision:** Always work on copies. Never modify the original file.
**Rationale:** This is a testing tool. Accidentally destroying a source file would defeat its purpose.

### 2026-02-26 - XcodeGen for Project Management
**Context:** Starting a new Xcode project alongside VideoAnalyzer and VCR.
**Decision:** Use XcodeGen with project.yml, consistent with sibling projects.
**Rationale:** Keeps xcodeproj out of version control, same tooling as VideoAnalyzer.

---
*Add decisions as they are made. Future-you will thank present-you.*
