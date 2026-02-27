# Spec: Video Corruption Engine

## Purpose
Generate intentionally corrupted video files to test VideoAnalyzer's detection and VCR's repair capabilities.

## User Flow
1. User drops a video file (MP4/MOV/M4V) or uses file picker
2. Sidebar shows corruption types grouped by category (File/Container/Stream)
3. User selects individual types or applies a preset
4. User clicks "Corrupt" and picks output directory
5. App generates one corrupted copy per selected type
6. Results show success/failure for each, with "Reveal in Finder"

## Corruption Types

### File-Level
| Type | Method | VideoAnalyzer Detection |
|------|--------|------------------------|
| Truncation | Cut file at 60% | `truncation` issue |
| Zero-Byte | Empty file with extension | File too small error |
| Fake Extension | Random 1KB data | Not valid media file |

### Container-Level
| Type | Method | VideoAnalyzer Detection |
|------|--------|------------------------|
| Corrupt Header | Overwrite ftyp type field | `corruptHeader` issue |
| Missing Video Track | Zero trak atom type (vmhd) | `missingTrack` issue |
| Missing Audio Track | Zero trak atom type (smhd) | `missingTrack` issue |
| Container Structure | Inflate moov size | `containerStructure` issue |

### Stream-Level
| Type | Method | VideoAnalyzer Detection |
|------|--------|------------------------|
| Timestamp Gap | Corrupt stts entries | `timestampGap` issue |
| Decode Error | Flip ~1% of mdat bytes | `decodeError` issue |

## Presets
- **All Types** - every corruption
- **Container Only** - headers, structure, missing tracks
- **Stream Only** - timestamps, decode errors
- **File Only** - truncation, zero-byte, fake extension
- **VCR Repair Test Suite** - corruptions that remux should fix

## Acceptance Criteria
- [ ] Each corruption type produces a file different from the original
- [ ] Original file is never modified
- [ ] VideoAnalyzer detects the expected issue type for each corruption
- [ ] VCR can attempt repair on container-level corruptions
- [ ] App handles files with no audio track gracefully
- [ ] App handles very small files (<1KB) gracefully
- [ ] Output filenames clearly indicate the corruption type applied
