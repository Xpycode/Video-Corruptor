# Video Corruption Research: MP4/MOV Formats

## 1. MP4/MOV File Structure

### Container Format Foundation

MP4 and MOV are both based on the ISO Base Media File Format (ISOBMFF / ISO 14496-12). Data is organized in hierarchical **boxes** (ISO term) or **atoms** (Apple/QuickTime term).

```
Bytes 0-3:  Size (32-bit unsigned big-endian, includes 8-byte header)
Bytes 4-7:  Type (4-byte ASCII FourCC: "moov", "mdat", etc.)
Bytes 8+:   Payload (children or data)
```

If size == 1, bytes 8-15 contain a 64-bit extended size. If size == 0, box extends to EOF.

### Complete Box Hierarchy

```
video.mp4
├── ftyp        (File Type - format/brands identification)
├── moov        (Movie Box - ALL metadata)
│   ├── mvhd    (Movie Header - timescale, duration)
│   ├── trak    (Track Box - one per track)
│   │   ├── tkhd    (Track Header - ID, dimensions)
│   │   ├── edts    (Edit List - timing offsets)
│   │   └── mdia    (Media Box)
│   │       ├── mdhd    (Media Header - timescale, language)
│   │       ├── hdlr    (Handler - "vide"/"soun")
│   │       └── minf    (Media Information)
│   │           ├── vmhd/smhd  (Video/Sound Header)
│   │           ├── dinf       (Data Reference)
│   │           └── stbl       (Sample Table - THE CRITICAL INDEX)
│   │               ├── stsd   (Sample Description - codec config, SPS/PPS)
│   │               ├── stts   (Time-to-Sample - frame durations)
│   │               ├── ctts   (Composition-to-Decode offset)
│   │               ├── stsc   (Sample-to-Chunk mapping)
│   │               ├── stsz   (Sample Size - byte size of every frame)
│   │               ├── stco   (Chunk Offset - byte offset per chunk)
│   │               ├── stss   (Sync Sample - keyframe list)
│   │               └── sdtp   (Sample Dependency Type)
│   └── udta    (User Data - encoder info)
├── mdat        (Media Data - raw compressed bitstream)
└── free/skip   (Padding)
```

### File Organization Variants

- **Traditional:** `[ftyp][mdat][moov]` — moov at end, must download fully first
- **Fast-start:** `[ftyp][moov][mdat]` — enables progressive playback (`-movflags +faststart`)
- **Fragmented (fMP4):** `[ftyp][moov][moof][mdat][moof][mdat]...` — DASH/HLS streaming

### Index Table Details (stbl sub-boxes)

**stco / co64 (Chunk Offset Table):**
```
Bytes 12-15: Entry count (N)
Bytes 16+:   N × 4-byte (stco) or 8-byte (co64) absolute file offsets
```
Each entry points to start of a chunk within mdat.

**stsc (Sample-to-Chunk):**
```
N entries × 12 bytes: first_chunk(4) + samples_per_chunk(4) + sample_desc_index(4)
```
Run-length pattern: "from chunk X, each chunk has Y samples."

**stsz (Sample Size):**
```
Bytes 12-15: sample_size (if nonzero, ALL samples are this size)
Bytes 16-19: sample_count (N)
Bytes 20+:   If sample_size==0, N × 4-byte per-sample sizes
```
I-frames: ~500KB+, P-frames: ~5KB. Sizes vary dramatically.

**stss (Sync Sample / Keyframes):**
```
Bytes 12-15: Entry count (N)
Bytes 16+:   N × 4-byte sample numbers (1-based) that are keyframes
```
If absent, every sample is a sync sample.

### H.264/H.265 Data Format in mdat

Uses **avcC format** (length-prefixed, NOT Annex B start codes):
```
[4-byte NAL size][NAL unit data][4-byte NAL size][NAL unit data]...
```
Length field size defined in `avcC` config via `lengthSizeMinusOne` (usually 4 bytes).

### Locating a Specific Frame

1. **stsc** → determine which chunk contains sample N
2. **stco** → get byte offset of that chunk
3. **stsz** → sum sizes of preceding samples in same chunk
4. Position = chunk_offset + sum_of_preceding_sizes

---

## 2. Types of Corruption Artifacts

### 2a. Header / moov Atom Corruption

| Target | Result |
|--------|--------|
| moov structure | **UNPLAYABLE** — "moov atom not found" |
| mvhd timescale/duration | Wrong playback speed or player refuses |
| tkhd dimensions | Wrong resolution/aspect ratio |
| stsd/avcC (SPS/PPS) | Complete decode failure or extreme garbling |

**Rule: NEVER corrupt moov if you want a playable file.**

### 2b. Index Table Corruption

**stco (Chunk Offset) shifts:**
- Small shifts (+/-1-50 bytes): decoder reads wrong position → severe block artifacts, color smearing, partial frames
- Large shifts: reads audio as video → extreme noise or crashes

**stss (Sync Sample) manipulation:**
- Remove entries: seeking broken but sequential playback may work
- Add false entries: seeking produces cascading decode errors until next real keyframe

**stsz (Sample Size) changes:**
- Too large: decoder reads into next frame → merge artifacts
- Too small: truncated frames → green/black blocks at bottom/right
- Zero: frames skipped entirely

### 2c. I-Frame vs P/B-Frame Corruption

**I-Frame (IDR) corruption** = most dramatic:
- Localized block artifacts in the corrupted frame
- **Cascading damage** through entire GOP (all P/B frames reference it)
- Foundation of **datamoshing**: corrupt/remove I-frame → decoder uses previous scene's I-frame as reference

**P-Frame corruption** = mid-range:
- Localized temporal glitches, propagate until next I-frame
- MV corruption → pixel displacement, stretching, smearing
- Residual corruption → color noise per block

**B-Frame corruption** = brief:
- Usually isolated single-frame glitches (non-reference B-frames)
- No propagation in baseline profile

**GOP length** (distance between I-frames, typically 30-250 frames) determines how long effects persist.

### 2d. Quantization Table Manipulation

QP range 0-51 in H.264, encoded as `mb_qp_delta` per macroblock.

| Change | Effect |
|--------|--------|
| Increase QP | Extreme blocking, banding, loss of detail |
| Decrease QP | Bitstream parse errors or buffer overflows |
| Randomize per-MB | Patchwork mosaic of quality levels |

### 2e. Motion Vector Corruption

MVs stored as (dx, dy) pairs in half/quarter-pel precision.

| Technique | Visual Effect |
|-----------|---------------|
| Zero all MVs | Freeze/echo — previous frame persists |
| Set all one direction | Directional smear/drag |
| Invert MVs | Mirror-like displacement |
| Scale (multiply) | Extreme stretching/warping |
| Average over N frames | Dreamy, liquid distortion |
| Swap H/V components | Diagonal displacement |
| Add noise | Vibrating/shaking per macroblock |

**MV structure (FFglitch JSON):**
```json
{
  "mv": {
    "forward": [
      [ [x0,y0], [x1,y1], ..., [xN,yN] ],  // row 0
      ...
    ],
    "backward": [ ... ]  // B-frames only
  }
}
```
Array dimensions = macroblock grid (width/16 × height/16). `null` = intra-coded MB.

### 2f. Color Space / Chroma Corruption

H.264 uses YCbCr with 4:2:0 subsampling (chroma at half resolution).

| Target | Effect |
|--------|--------|
| Y (luma) corruption | Brightness artifacts — most visually obvious |
| Cb/Cr (chroma) corruption | Classic pink/green blocks, color shifts |
| Swap Cb↔Cr | Complementary color shift (reds↔cyan) |
| Modify chroma_format_idc in SPS | Extreme color distortion (likely crashes decoder) |

### 2g. NAL Unit Structure (H.264)

```
[4-byte length][1-byte header][payload...]
Header: forbidden_zero_bit(1) | nal_ref_idc(2) | nal_unit_type(5)
Type = header & 0x1F
```

| NAL Type | Value | Header Byte | Corruption Impact |
|----------|-------|-------------|-------------------|
| Non-IDR slice | 1 | 0x61/0x41/0x01 | Localized temporal artifacts |
| IDR slice | 5 | 0x65 | Cascading through GOP |
| SEI | 6 | 0x06 | Minimal (metadata) |
| SPS | 7 | 0x67 | **Total decode failure** |
| PPS | 8 | 0x68 | **Total decode failure** |

**H.265 differences:** 2-byte NAL header, types 16-21 = keyframes, type 32 = VPS (new), CABAC only (single bit flip cascades through arithmetic state).

**Slice structure within NAL:**
```
[NAL header] → [Slice header: ~5-30 bytes] → [Slice data: macroblocks]
  per MB: [mb_type][prediction][CBP][qp_delta][residual: luma DC/AC + chroma DC/AC]
```

---

## 3. Programmatic Corruption Architecture

### Step 1: Parse MP4 Box Tree
Read sequentially: 4 bytes size + 4 bytes type per box. Record offset/size of every top-level box. Recursively parse moov children. Record byte ranges for mdat, stco, stsz, stss, stsd/avcC.

### Step 2: Build Frame Map
```
frame_map[i] = {
  byte_offset: absolute file position,
  byte_size: frame data length,
  is_keyframe: boolean (from stss),
  nal_units: [parsed from mdat]
}
```

### Step 3: Parse NAL Units per Frame
```
position = frame.byte_offset
while position < frame.byte_offset + frame.byte_size:
    nal_length = read_uint32_be(position)
    nal_header = read_byte(position + 4)
    nal_type = nal_header & 0x1F
    position += 4 + nal_length
```

### Step 4: Apply Targeted Corruption

**Datamosh effect:** Find IDR NALs (type 5), zero slice data starting ~20 bytes in, or change NAL type byte 0x65→0x61.

**Block glitch:** Select random P-frame NALs, corrupt 1-5% of bytes starting ~20 bytes in.

**Color corruption:** Target second half of MB data (chroma residual) or corrupt every Nth byte.

**Motion glitch:** Requires bitstream parser (FFglitch) or corrupt bytes near MB start (after mb_type).

### Step 5: Write Corrupted File
Copy original. Overwrite ONLY targeted bytes within mdat. Do NOT modify ftyp, moov, box sizes. File remains structurally valid.

### Alternative: Index Table Manipulation
Modify stco/stsz/stss values in-place (same entry count) rather than corrupting mdat bytes. Simpler but different artifact profile.

---

## 4. Safety Boundaries

### UNPLAYABLE (Avoid)

| Target | Why |
|--------|-----|
| ftyp box | Player can't identify format |
| moov structure/sizes | Parser can't navigate metadata |
| SPS/PPS NAL units | Total decode failure |
| stco offsets outside mdat | Reads garbage, crash |
| NAL length fields | Misidentified boundaries |
| Emulation prevention violation | Phantom start codes |
| All I-frames corrupted | No clean reference ever |

### PLAYABLE with Interesting Artifacts

| Target | Effect | Safety |
|--------|--------|--------|
| Slice data bytes (skip 10-20 byte header) | Block artifacts, color noise | HIGH |
| 1-5% random bytes in mdat | Scattered glitches | HIGH |
| IDR frames only (keep first intact) | Datamosh / pixel bleeding | MEDIUM |
| Motion vectors (via FFglitch) | Directional smearing | HIGH |
| QP values (via FFglitch) | Mosaic quality | HIGH |
| Residual coefficients | Brightness/color per block | HIGH |
| stco offsets (small +/-1-50 bytes) | Misaligned reading | MEDIUM |
| stss entries (remove some) | Seek dysfunction | HIGH |

### Golden Rules

1. NEVER corrupt moov atom
2. NEVER corrupt ftyp box
3. Preserve first IDR frame
4. Keep NAL length prefixes intact
5. Skip slice header (~20 bytes into NAL)
6. Start with 1-2% corruption, increase gradually
7. Target middle of video (beginning has critical setup)
8. Test with VLC (most fault-tolerant player)

### Player Tolerance

| Player | Tolerance |
|--------|-----------|
| VLC | Highest |
| mpv | High |
| FFplay | High |
| QuickTime Player | Low |
| AVFoundation | Low-Medium |
| Browsers | Medium (varies) |
