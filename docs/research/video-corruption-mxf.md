

# MXF (Material Exchange Format) Corruption Research

## 1. MXF File Structure

### KLV (Key-Length-Value) Encoding

MXF is built entirely on KLV triplets — every single element in the file is a KLV packet.

**Key (16 bytes):** A SMPTE Universal Label (UL) — a 16-byte identifier registered with SMPTE. The structure is:

```
Byte 1:    Object identifier (always 0x06)
Byte 2:    Length of UL label (always 0x0E = 14)
Byte 3:    Designator (0x2B for SMPTE)
Byte 4:    Designator (0x34 for SMPTE)
Bytes 5-8: Category, Registry, Structure, Version
Bytes 9-16: Item-specific identification
```

Example keys:
- `06 0E 2B 34 02 05 01 01 0D 01 02 01 01 05 01 00` — MPEG-2 essence element
- `06 0E 2B 34 02 05 01 01 0D 01 02 01 0A 01 00 00` — JPEG2000 essence element
- `06 0E 2B 34 01 02 01 01 0D 01 03 01 04 01 01 00` — DNxHD essence element (Avid-registered)

**Length (BER encoded, 1-9 bytes):** Uses ASN.1 Basic Encoding Rules:
- If value < 128: single byte (short form)
- If value >= 128: first byte = `0x80 | number_of_length_bytes`, followed by length bytes (long form)

```
Examples:
  0x45              → length = 69 bytes (short form)
  0x82 0x01 0x00    → length = 256 bytes (long form, 2 bytes)
  0x84 0x00 0x01 0x00 0x00 → length = 65536 bytes (long form, 4 bytes)
```

**Value:** The actual payload data — could be metadata, essence (video/audio), index tables, etc.

### Partition Structure

An MXF file is divided into partitions, each beginning with a Partition Pack:

```
┌──────────────────────────────┐
│  Header Partition Pack       │  ← KLV: identifies partition type, offsets
│  Header Metadata (optional)  │  ← Structural metadata (Preface, packages, tracks)
│  Index Table (optional)      │  ← Maps edit units to byte offsets
│  Essence Container           │  ← Actual video/audio data as KLV triplets
├──────────────────────────────┤
│  Body Partition Pack         │  ← Optional, for multi-partition files
│  Index Table (optional)      │
│  Essence Container           │
├──────────────────────────────┤
│  ...more body partitions...  │
├──────────────────────────────┤
│  Footer Partition Pack       │  ← Final partition, often has complete index
│  Index Table (optional)      │  ← Complete index for random access
│  Random Index Pack (RIP)     │  ← Last item: byte offsets to all partitions
└──────────────────────────────┘
```

**Partition Pack fields (key fields for corruption):**

| Field | Size | Purpose |
|-------|------|---------|
| MajorVersion | 2 bytes | Always 0x0001 |
| MinorVersion | 2 bytes | 0x0002 or 0x0003 |
| KAGSize | 4 bytes | KLV Alignment Grid size |
| ThisPartition | 8 bytes | Byte offset of this partition |
| PreviousPartition | 8 bytes | Byte offset of previous partition |
| FooterPartition | 8 bytes | Byte offset of footer |
| HeaderByteCount | 8 bytes | Size of header metadata in this partition |
| IndexByteCount | 8 bytes | Size of index table in this partition |
| IndexSID | 4 bytes | Stream ID for index |
| BodyOffset | 8 bytes | Byte offset into essence container |
| BodySID | 4 bytes | Stream ID for essence |

### Operational Patterns

**OP1a (most common):** Single item, single package. All essence in one body partition, interleaved (video frame, then audio for that frame, repeat). This is the "simple" pattern — one file contains one complete piece of content.

**OP-Atom:** Single item, single package, but each essence track is in its own file. Used by Avid Media Composer (one .mxf for video, separate .mxf files for each audio track). The metadata file links them.

**OP1b:** Single item, multiple packages (e.g., multiple camera angles).

**OPx patterns:** More complex multi-item arrangements used in playout systems.

### Structural Metadata

The header metadata is a hierarchical set of metadata objects linked by instance UIDs:

```
Preface
├── ContentStorage
│   └── Package (Material Package)
│       └── Track (Timeline Track)
│           └── Sequence
│               └── SourceClip → references File Package
│   └── Package (File Package / Source Package)
│       └── Track (Timeline Track)
│           └── Sequence
│               └── SourceClip
│       └── EssenceContainerData → BodySID
├── Identification (application that wrote the file)
├── Dictionary (optional)
└── EssenceDescriptor
    ├── CDCIEssenceDescriptor (for compressed video)
    │   ├── StoredWidth, StoredHeight
    │   ├── FrameLayout (progressive/interlaced)
    │   ├── PictureEssenceCoding UL → identifies codec
    │   └── ComponentDepth, HorizontalSubsampling
    └── SoundDescriptor (for audio)
```

Each metadata set is itself a KLV group with a 16-byte instance UID.

---

## 2. How MXF Differs from MP4/MOV for Corruption

### Structural Differences

| Aspect | MP4/MOV | MXF |
|--------|---------|-----|
| Container model | Atom/box tree | Flat KLV sequence in partitions |
| Metadata location | moov atom (usually at end or start) | Header partition metadata + footer copy |
| Frame index | stts/stsc/stco/co64 atoms | Index Table Segments with edit unit entries |
| Essence wrapping | Raw NAL units or samples | Each frame wrapped in a KLV triplet |
| Redundancy | Single metadata copy | Header + footer metadata copies |
| Alignment | No requirement | KAG (KLV Alignment Grid) — pads to boundaries |
| Codec scope | H.264, H.265, ProRes, etc. | DNxHD, ProRes, MPEG-2, JPEG2000, uncompressed |

### Unique Corruption Opportunities in MXF

1. **KLV Key Corruption:** Changing the 16-byte UL key of an essence element makes the decoder skip it or misinterpret the data type. MP4 has nothing equivalent — its frames are just raw bytes indexed by offset tables.

2. **BER Length Manipulation:** Corrupting the BER-encoded length field causes the parser to read the wrong number of bytes, potentially swallowing the next KLV triplet or stopping mid-frame. This cascading effect is unique to KLV.

3. **Partition Chain Breakage:** MXF partitions form a linked list via `PreviousPartition`/`FooterPartition` offsets. Breaking these links causes players to lose track of the file structure. MP4 has no equivalent chain.

4. **Dual Metadata Corruption:** MXF stores metadata in both header and footer. Corrupting one but not the other creates inconsistency — some players fall back to the footer copy, others fail outright. MP4 has only one moov atom.

5. **KAG Padding Corruption:** MXF uses KLV Alignment Grid to align data to specific byte boundaries (typically 512 bytes or 1 for no alignment). Corrupting the KAGSize or the fill/padding KLVs between elements breaks alignment expectations.

6. **Index Table vs Essence Mismatch:** You can corrupt the index table to point to wrong byte offsets while leaving essence intact, or vice versa. This creates frame-skipping, repeated frames, or temporal scrambling.

7. **Operational Pattern Confusion:** Changing the OP label in the header (e.g., OP1a to OP-Atom) causes the player to look for external files that do not exist.

---

## 3. Types of Corruption Artifacts in MXF

### 3a. Partition Damage

**Header Partition Pack corruption:**

```python
# The Header Partition Pack key:
HEADER_PARTITION_KEY = bytes([
    0x06, 0x0E, 0x2B, 0x34, 0x02, 0x05, 0x01, 0x01,
    0x0D, 0x01, 0x02, 0x01, 0x01, 0x02, 0x04, 0x00
])
# Byte 14 (0-indexed 13): 0x02 = Open/Incomplete, 0x03 = Closed/Incomplete,
#                          0x04 = Open/Complete, 0x04 = Closed/Complete

# Corruption: Change Closed/Complete to Open/Incomplete
# This tells players the file was never properly finished
data[13] = 0x02  # Was 0x04

# Corruption: Zero out FooterPartition offset (bytes at offset +32 from pack start)
# Players cannot find the footer — lose redundant metadata and final index
struct.pack_into('>Q', partition_pack, 32, 0)

# Corruption: Modify ThisPartition to wrong value
# Breaks self-referencing, some players use this for validation
struct.pack_into('>Q', partition_pack, 16, 0xDEADBEEF)
```

**Effects:** Players that rely on the header partition for initialization may refuse to open the file entirely, show black frames, or play with missing audio. Some professional players (e.g., Avid, DaVinci Resolve) attempt footer fallback; consumer players (VLC, FFmpeg) may partially recover or fail.

**Body Partition corruption:**

```python
# Body partitions are optional — zeroing them out may cause the player
# to treat the entire body as one continuous essence stream
# This can cause frame boundary misalignment

# Change BodySID to 0 (no essence in this partition)
struct.pack_into('>I', body_partition_pack, 48, 0)

# Or change BodyOffset to skip frames
original_offset = struct.unpack_from('>Q', body_partition_pack, 40)[0]
struct.pack_into('>Q', body_partition_pack, 40, original_offset + 1024)
```

### 3b. Index Table Corruption

MXF Index Tables map edit units (frames) to byte offsets within the essence container. An Index Table Segment contains:

```
IndexTableSegment (KLV set):
  InstanceUID:        16 bytes
  IndexEditRate:      Rational (8 bytes)
  IndexStartPosition: int64
  IndexDuration:      int64
  EditUnitByteCount:  uint32 (0 for variable-length frames like Long-GOP MPEG-2)
  IndexSID:           uint32
  BodySID:            uint32
  SliceCount:         uint8
  DeltaEntryArray:    array of (PosTableIndex, Slice, ElementDelta)
  IndexEntryArray:    array of (TemporalOffset, KeyFrameOffset, Flags, StreamOffset)
```

**Index Entry corruption techniques:**

```python
# Each index entry (for CBE - Constant Bytes per Element):
# StreamOffset (8 bytes) — byte position of this frame in essence

# Technique 1: Swap frame offsets (temporal scrambling)
# Frame 10 plays where frame 50 should be
index_entries[10].stream_offset, index_entries[50].stream_offset = \
    index_entries[50].stream_offset, index_entries[10].stream_offset

# Technique 2: Shift all offsets by N bytes (frame boundary misalignment)
for entry in index_entries:
    entry.stream_offset += 37  # Not frame-aligned = decoder gets garbage

# Technique 3: Zero out TemporalOffset in Long-GOP MPEG-2
# TemporalOffset tells the decoder the display order vs decode order
# Zeroing it causes B-frames to display in decode order (temporal glitching)
for entry in index_entries:
    entry.temporal_offset = 0

# Technique 4: Corrupt KeyFrameOffset
# KeyFrameOffset tells the decoder how many frames back the nearest I-frame is
# Setting to 0 makes every frame look like a keyframe — P/B frames try to
# decode independently, producing heavy macroblocking
for entry in index_entries:
    entry.keyframe_offset = 0

# Technique 5: Modify Flags byte
# Bit 7: RandomAccess (keyframe)
# Setting random access flag on non-keyframes
entry.flags |= 0x80  # Mark as random access
# Clearing it from keyframes
entry.flags &= ~0x80  # Remove random access marker
```

**Effects:** Temporal scrambling produces the "glitch art" time-displacement effect. Offset shifting causes the codec to start decoding mid-frame, producing partial images or color field corruption. KeyFrameOffset corruption produces heavy blocking on inter-frames.

### 3c. Essence Data Corruption (Within KLV Triplets)

Each video frame in MXF is wrapped in a KLV triplet:

```
[16-byte Key][BER Length][Frame Data...]
```

**KLV Key corruption:**

```python
# Video essence element key pattern:
# 06 0E 2B 34 01 02 01 01 0D 01 03 01 XX YY ZZ 00
# Where XX YY ZZ identify the specific essence type

# Technique: Change essence type bytes to make decoder misidentify
# Change MPEG-2 video (15 01 XX) to data essence
essence_klv[12] = 0x05  # Was video, now "data"
# Player may skip this as unknown data → dropped frame

# Technique: Corrupt BER length to be shorter than actual frame
# Decoder reads partial frame, next KLV parse starts mid-frame data
original_length = read_ber_length(data, offset)
write_ber_length(data, offset, original_length // 2)
# Next KLV key search will find garbage → cascading parse failure

# Technique: Corrupt BER length to be longer than actual frame
# Decoder reads past frame boundary into next KLV key/length
write_ber_length(data, offset, original_length * 2)
# Decoder gets frame data + next frame's KLV header as "frame data"
```

**Essence payload corruption (the actual compressed frame bytes):**

```python
# After the KLV header, corrupt the frame data itself
frame_start = klv_key_offset + 16 + ber_length_size

# Technique: Zero out bytes at frame start (kills frame header)
data[frame_start:frame_start+64] = b'\x00' * 64

# Technique: Bit flipping within frame body
import random
for i in range(frame_start + 100, frame_start + 500):
    if random.random() < 0.01:  # 1% probability per byte
        data[i] ^= random.randint(1, 255)

# Technique: Insert sync-word patterns to confuse decoder
# For MPEG-2: insert fake start codes (0x00 0x00 0x01)
insert_pos = frame_start + len(frame_data) // 3
data[insert_pos:insert_pos+3] = b'\x00\x00\x01'
```

### 3d. Metadata Corruption (Structural Metadata Sets)

**Essence Descriptor corruption:**

```python
# The CDCIEssenceDescriptor tells the decoder what it's looking at
# Key fields and their UL tags:

# StoredWidth (UL: 06 0E 2B 34 01 01 01 01 04 01 05 02 02 00 00 00)
# Changing this makes the decoder read wrong scan line widths
stored_width_offset = find_metadata_property(data, STORED_WIDTH_UL)
struct.pack_into('>I', data, stored_width_offset, 960)  # Was 1920

# StoredHeight
stored_height_offset = find_metadata_property(data, STORED_HEIGHT_UL)
struct.pack_into('>I', data, stored_height_offset, 540)  # Was 1080

# PictureEssenceCoding — THE codec identifier
# Changing this makes the player try the wrong decoder
# DNxHD UL: 06 0E 2B 34 04 01 01 01 04 01 02 02 71 XX 00 00
# ProRes UL: 06 0E 2B 34 04 01 01 01 04 01 02 02 06 05 XX 00
# Swap DNxHD coding label with ProRes → wrong decoder = total garbage
coding_ul_offset = find_metadata_property(data, PICTURE_ESSENCE_CODING_UL)
data[coding_ul_offset + 12] = 0x06  # Change from DNxHD to ProRes family
data[coding_ul_offset + 13] = 0x05

# FrameLayout — 0x00=Full Frame, 0x01=Separate Fields, 0x03=Single Field
# Changing progressive to interlaced causes field-swap artifacts
frame_layout_offset = find_metadata_property(data, FRAME_LAYOUT_UL)
data[frame_layout_offset] = 0x01  # Was 0x00 (progressive), now interlaced

# ComponentDepth — bits per component (8, 10, 12)
# Changing 10-bit to 8-bit causes color banding and value overflow
component_depth_offset = find_metadata_property(data, COMPONENT_DEPTH_UL)
struct.pack_into('>I', data, component_depth_offset, 8)  # Was 10
```

**Effects:** Width/height changes produce skewed, striped, or tiled images as scan lines wrap at wrong boundaries. Codec mismatch produces total visual garbage or player crashes. Progressive/interlaced swaps create combed or field-doubled images. Bit depth changes cause banding, posterization, or wild color shifts.

**Package/Track metadata corruption:**

```python
# EditRate in Timeline Track — tells player the frame rate
# Changing 24000/1001 to 60000/1001 = plays at 2.5x speed
# Or changing denominator to 0 → division by zero crash
edit_rate_offset = find_metadata_property(data, EDIT_RATE_UL)
struct.pack_into('>II', data, edit_rate_offset, 60000, 1001)

# Duration in SourceClip — limits playback length
# Setting to 0 may cause infinite loop in some players
duration_offset = find_metadata_property(data, DURATION_UL)
struct.pack_into('>q', data, duration_offset, 0)
```

---

## 4. Codec-Specific Corruption in MXF Context

### 4a. DNxHD / DNxHR

DNxHD (Digital Nonlinear Extensible High Definition) is Avid's production codec, extremely common in MXF files.

**Frame structure:**

```
DNxHD Frame:
┌─────────────────────────────────┐
│ Frame Header (640 or 1664 bytes)│
│  - Signature: 0x00 0x00 0x02 80│  (at offset 0x00)
│  - Width, Height                │  (offset 0x18, 0x1A)
│  - Compressed frame size        │  (offset 0x28)
│  - Codec profile / CID          │  (offset 0x21 — Compression ID)
│  - Bit depth (8 or 10)          │  (offset 0x22)
│  - Number of macroblocks        │
│  - MB scan table offsets        │  (offset 0x170+, array of uint32)
├─────────────────────────────────┤
│ Macroblock Data                 │
│  (8x8 DCT blocks, Huffman coded)│
│  - Y blocks (4 per MB)         │
│  - Cb block (1 per MB)         │
│  - Cr block (1 per MB)         │
└─────────────────────────────────┘
```

**DNxHD Compression IDs (CID) — common values:**

| CID | Format |
|-----|--------|
| 1235 | 1080p 10-bit 220Mbps |
| 1237 | 1080p 8-bit 145Mbps |
| 1238 | 1080p 8-bit 220Mbps |
| 1241 | 1080p 10-bit 220Mbps (1080i) |
| 1243 | 1080p 8-bit 36Mbps |
| 1250 | 720p 10-bit 220Mbps |
| 1251 | 720p 8-bit 145Mbps |
| 1252 | 720p 8-bit 220Mbps |
| 1253 | 1080p 8-bit 45Mbps |
| 1256 | 1080p 10-bit 440Mbps |

**Corruption techniques:**

```python
# 1. Corrupt DNxHD signature (makes frame unrecognizable)
frame_data[0:4] = b'\x00\x00\x00\x00'  # Kill signature 0x00000280

# 2. Change CID (Compression ID) — wrong decode parameters
# At offset 0x21 (2 bytes, big-endian)
cid_offset = frame_start + 0x21
original_cid = struct.unpack_from('>H', data, cid_offset)[0]
struct.pack_into('>H', data, cid_offset, 1237)  # Was 1235 (10-bit→8-bit)
# Effect: 10-bit data decoded as 8-bit = every pixel value is wrong,
# produces washed-out or heavily banded image

# 3. Corrupt macroblock offset table
# The MB offset table starts around byte 0x170 in the frame header
# Each entry is a uint32 offset to where that MB's data starts
mb_table_offset = frame_start + 0x170
num_mbs = (width // 16) * (height // 16)  # 1920x1080 = 8160 MBs
for i in range(0, num_mbs * 4, 4):
    if random.random() < 0.05:  # 5% of MBs
        # Point this MB to another MB's data (spatial scramble)
        target_mb = random.randint(0, num_mbs - 1)
        target_offset = struct.unpack_from('>I', data, mb_table_offset + target_mb * 4)[0]
        struct.pack_into('>I', data, mb_table_offset + i, target_offset)

# 4. Corrupt DCT coefficients in macroblock data
# DNxHD uses Huffman-coded DCT coefficients
# Flipping bits in this region produces blocky artifacts
# The DC coefficient is first — corrupting it shifts entire block brightness
mb_data_start = frame_start + header_size
# Corrupt random bytes in the compressed MB data
for offset in range(mb_data_start, mb_data_start + compressed_size):
    if random.random() < 0.002:  # 0.2% of bytes
        data[offset] ^= random.randint(1, 255)

# 5. Zero out individual macroblocks (creates black rectangles)
# Read offset from MB table, zero the data between this and next MB
mb_index = 100  # Specific macroblock
this_offset = struct.unpack_from('>I', data, mb_table_offset + mb_index * 4)[0]
next_offset = struct.unpack_from('>I', data, mb_table_offset + (mb_index + 1) * 4)[0]
data[frame_start + this_offset:frame_start + next_offset] = \
    b'\x00' * (next_offset - this_offset)
```

**DNxHD-specific visual effects:**
- CID swap between 8-bit and 10-bit: severe banding, color channel offset
- MB offset table scramble: spatial displacement of 16x16 blocks — "tile shuffle" effect
- DC coefficient corruption: brightness pumping across blocks, checkerboard brightness pattern
- DNxHD is all-intra (every frame is independent) so corruption does NOT propagate between frames — each frame's corruption is self-contained

### 4b. Apple ProRes

ProRes is common in MXF files from Apple-ecosystem workflows (Final Cut Pro export to MXF).

**Frame structure:**

```
ProRes Frame:
┌──────────────────────────────────┐
│ Frame Header (variable, ~148 bytes)│
│  - Frame size (4 bytes, BE)       │  offset 0
│  - "icpf" signature (4 bytes)     │  offset 4: 0x69 0x63 0x70 0x66
│  - Header size (2 bytes)          │  offset 8
│  - Version (2 bytes)              │  offset 10
│  - Creator ID (4 bytes)           │  offset 12 (e.g., 'apl0' for Apple)
│  - Width (2 bytes)                │  offset 16
│  - Height (2 bytes)               │  offset 18
│  - Chroma format (1 byte)         │  offset 20 (2=4:2:2, 3=4:4:4)
│  - Interlaced flag (1 byte)       │  offset 21
│  - Aspect ratio (1 byte)          │  offset 22
│  - Frame rate (1 byte)            │  offset 23
│  - Color primaries (1 byte)       │  offset 24
│  - Transfer characteristic (1 byte)│ offset 25
│  - Matrix coefficients (1 byte)   │  offset 26
│  - Alpha channel info (1 byte)    │  offset 27 (ProRes 4444 only)
│  ── Quantization Matrix Tables ── │  offset 28+ (if present)
│  - Luma QM (64 bytes)             │
│  - Chroma QM (64 bytes)           │
├──────────────────────────────────┤
│ Picture Group(s)                  │
│  ┌────────────────────────────┐  │
│  │ Picture Header              │  │
│  │  - Picture size (4 bytes)   │  │
│  │  - Slice count log2         │  │
│  │  - Slice index table        │  │  ← offsets to each slice
│  ├────────────────────────────┤  │
│  │ Slice 0                     │  │
│  │  - Slice header (variable)  │  │
│  │  - Y data (DCT coefficients)│  │
│  │  - Cb data                  │  │
│  │  - Cr data                  │  │
│  ├────────────────────────────┤  │
│  │ Slice 1                     │  │
│  │  ...                        │  │
│  └────────────────────────────┘  │
│  (2nd picture for interlaced)    │
└──────────────────────────────────┘
```

**ProRes profile IDs (proxy through HQ):**

| Profile | FourCC | Typical bitrate (1080p24) |
|---------|--------|--------------------------|
| Proxy | apco | ~45 Mbps |
| LT | apcs | ~102 Mbps |
| Standard | apcn | ~147 Mbps |
| HQ | apch | ~220 Mbps |
| 4444 | ap4h | ~330 Mbps |
| 4444 XQ | ap4x | ~500 Mbps |

**Corruption techniques:**

```python
# 1. Corrupt "icpf" signature
frame_data[4:8] = b'\x00\x00\x00\x00'  # Kill magic bytes
# Effect: decoder rejects frame entirely → black frame or player error

# 2. Modify quantization matrices
# QM starts at offset 28 in frame header (if flag set in header)
# Each QM is 64 bytes (8x8), values typically 4-64
# Increasing values = more quantization = blockier image
# Decreasing values = less quantization = decoder may overflow
qm_offset = frame_start + 28
for i in range(64):
    data[qm_offset + i] = max(1, data[qm_offset + i] * 3)  # Triple quant values
# Effect: Extreme blocking, posterization, banding

# Alternatively, zero out QM (minimum quantization)
data[qm_offset:qm_offset + 64] = b'\x01' * 64
# Effect: Coefficient overflow, bright flashing, color blowout

# 3. Corrupt slice index table (scramble slice order)
# The slice index table is an array of uint16 offsets
slice_count = 1 << data[picture_header + 4]  # log2 encoding
slice_table_offset = picture_header + 6  # after picture header
slice_offsets = []
for i in range(slice_count):
    slice_offsets.append(struct.unpack_from('>H', data, slice_table_offset + i * 2)[0])
random.shuffle(slice_offsets)  # Scramble!
for i, offset in enumerate(slice_offsets):
    struct.pack_into('>H', data, slice_table_offset + i * 2, offset)
# Effect: Horizontal band scrambling — slices render in wrong positions

# 4. Corrupt individual slice data
# Each slice contains DCT coefficients for a horizontal strip of MBs
# ProRes uses Huffman + Rice coding for coefficients
slice_data_start = slice_table_offset + slice_count * 2 + slice_offsets[target_slice]
# Flip bits in slice data
for i in range(slice_data_start, slice_data_start + 200):
    if random.random() < 0.05:
        data[i] ^= random.randint(1, 255)
# Effect: Corruption confined to horizontal band, may produce:
#   - Color channel displacement within slice
#   - Block artifacts in slice region
#   - "Datamoshed" look within the band

# 5. Swap chroma format (4:2:2 → 4:4:4 or vice versa)
data[frame_start + 20] = 3  # Was 2 (4:2:2), now claims 4:4:4
# Effect: Chroma data misinterpreted, color channels shift/overlap
# Produces psychedelic color bleeding

# 6. Corrupt color matrix coefficients
data[frame_start + 26] = 0  # Change to "unspecified"
# Or change BT.709 (1) to BT.601 (6) for wrong color space
data[frame_start + 26] = 6
# Effect: Subtle but visible color shift (greens become more yellow, etc.)
```

**ProRes-specific visual effects:**
- ProRes is also all-intra — corruption is per-frame, no temporal propagation
- Slice scrambling creates distinctive horizontal band displacement
- QM corruption produces very clean blocky artifacts (professional-looking degradation)
- Chroma format misidentification produces vivid, saturated color artifacts

### 4c. MPEG-2 in MXF (XDCAM, D-10, Long-GOP)

MPEG-2 is extremely common in MXF — used by Sony XDCAM, XDCAM HD, IMX/D-10, and many broadcast systems.

**MPEG-2 stream structure within MXF:**

```
GOP (Group of Pictures):
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│  I  │  B  │  B  │  P  │  B  │  B  │  P  │  B  │  B  │  P  │  B  │  B  │
│  0  │  1  │  2  │  3  │  4  │  5  │  6  │  7  │  8  │  9  │  10 │  11 │
└─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘
Display: 0  1  2  3  4  5  6  7  8  9  10  11
Decode:  0  3  1  2  6  4  5  9  7  8      ← reordered

MPEG-2 Start Codes:
  0x000001B3 — Sequence Header
  0x000001B5 — Extension Start Code
  0x000001B8 — GOP Header
  0x00000100 — Picture Start Code (frame)
  0x000001XX — Slice Start Codes (0x01-0xAF)
```

**Key difference:** MPEG-2 Long-GOP uses inter-frame prediction (P and B frames reference other frames). Corrupting an I-frame causes cascading visual artifacts through the entire GOP until the next I-frame. This is fundamentally different from DNxHD/ProRes.

**In MXF, MPEG-2 can be wrapped two ways:**
- **Frame-wrapped:** Each KLV triplet contains one complete frame (common for XDCAM HD)
- **Clip-wrapped:** One KLV triplet contains the entire MPEG-2 stream (common for D-10/IMX)

**Corruption techniques:**

```python
# 1. Corrupt I-frame → cascading artifacts through GOP
# Find I-frame by scanning for picture start codes and checking picture type
# Picture type is in bits 3-5 of the byte at picture_start + 5
# 001 = I-frame, 010 = P-frame, 011 = B-frame

def find_i_frames(data, start, end):
    """Find all I-frame positions in MPEG-2 stream."""
    i_frames = []
    pos = start
    while pos < end - 6:
        if data[pos:pos+4] == b'\x00\x00\x01\x00':  # Picture start code
            picture_coding_type = (data[pos + 5] >> 3) & 0x07
            if picture_coding_type == 1:  # I-frame
                i_frames.append(pos)
        pos += 1
    return i_frames

# Corrupt first I-frame's slice data (leave header intact for parsing)
i_frame_pos = i_frames[0]
# Find first slice start code after picture header
slice_start = i_frame_pos + 8  # Skip picture header
while data[slice_start:slice_start+3] != b'\x00\x00\x01':
    slice_start += 1
slice_start += 4  # Skip start code

# Corrupt slice data — produces macroblocking that persists through GOP
for i in range(slice_start, slice_start + 2000):
    if random.random() < 0.03:
        data[i] ^= random.randint(1, 255)
# Effect: Corrupted macroblocks in I-frame propagate to all P/B frames
# Creates "frozen block" artifacts — blocks that stick and smear

# 2. Delete B-frames (temporal stuttering)
# Find B-frame picture start codes and zero them out
for pos in find_b_frames(data, start, end):
    next_start_code = find_next_start_code(data, pos + 4)
    data[pos:next_start_code] = b'\x00' * (next_start_code - pos)
# Effect: Missing frames → player either drops them (judder) or
# shows previous frame (freeze-frame stutter)

# 3. Corrupt motion vectors in P-frames
# Motion vectors are VLC-coded within slice data
# Flipping bits in the macroblock data region changes motion estimation
# This produces "sliding block" artifacts — parts of the image slide around
p_frame_pos = find_p_frames(data, start, end)[0]
slice_data_start = find_first_slice(data, p_frame_pos)
for i in range(slice_data_start + 50, slice_data_start + 500):
    if random.random() < 0.02:
        data[i] ^= 0x40  # Flip a middle bit
# Effect: Motion vectors point to wrong reference areas →
# blocks slide, stretch, or duplicate from wrong positions

# 4. Sequence header corruption
# The sequence header contains fundamental decoding parameters
seq_header_pos = data.find(b'\x00\x00\x01\xB3', start)
if seq_header_pos >= 0:
    # Bytes 4-5: horizontal_size (12 bits) + vertical_size (12 bits)
    # Corrupt resolution
    data[seq_header_pos + 4] = 0x2D  # Change width
    # Effect: Decoder reads wrong number of pixels per line
    # Produces diagonal striping or image tearing

    # Byte 7: bit_rate_value (upper 12 bits) + aspect ratio (4 bits)
    # Corrupting bit rate can cause buffer underflow/overflow in decoder
    data[seq_header_pos + 7] ^= 0xFF

# 5. GOP header corruption
gop_pos = data.find(b'\x00\x00\x01\xB8', start)
if gop_pos >= 0:
    # GOP header contains time_code and closed_gop/broken_link flags
    # Flipping closed_gop flag makes decoder think it can't decode
    # independently — seeks to previous GOP (which may also be corrupt)
    data[gop_pos + 7] ^= 0x40  # Toggle closed_gop bit
```

**MPEG-2-in-MXF specific effects:**
- **Cascading corruption:** I-frame damage produces "glitch trails" that persist for the entire GOP (typically 12-15 frames at 25fps, or up to 30 frames). This is the classic datamosh/glitch-art look.
- **Frame type removal:** Removing P-frames causes the image to "freeze" while B-frames create ghostly overlaps.
- **Motion vector corruption:** Produces the characteristic "block sliding" effect — rectangular regions of the image drift in wrong directions.
- **D-10/IMX (I-frame only MPEG-2):** When MPEG-2 is used in I-frame-only mode (Sony IMX), it behaves like DNxHD — corruption is per-frame only, no propagation.

### 4d. JPEG2000 in MXF

JPEG2000 is used in Digital Cinema Package (DCP) MXF files and some broadcast MXF (SMPTE 422M). It uses wavelet transforms instead of DCT.

**JPEG2000 frame structure:**

```
JPEG2000 Codestream:
┌────────────────────────────────┐
│ SOC (Start of Codestream)      │  0xFF4F
│ SIZ (Image and Tile Size)      │  0xFF51
│  - Width, Height, Tile size    │
│  - Component count & bit depth │
│ COD (Coding Style Default)     │  0xFF52
│  - Decomposition levels        │
│  - Code-block size             │
│  - Wavelet transform type      │
│ QCD (Quantization Default)     │  0xFF5C
│  - Quantization step sizes     │
│  - for each decomposition level│
├────────────────────────────────┤
│ SOT (Start of Tile-part)       │  0xFF90
│  - Tile index, tile-part length│
│ SOD (Start of Data)            │  0xFF93
│  - Compressed tile data        │
│  - (wavelet coefficients,      │
│  -  arithmetic/Huffman coded)  │
├────────────────────────────────┤
│ SOT (next tile)                │
│ SOD                            │
│ ...                            │
├────────────────────────────────┤
│ EOC (End of Codestream)        │  0xFFD9
└────────────────────────────────┘
```

**Corruption techniques:**

```python
# 1. Corrupt SIZ marker (image dimensions)
siz_pos = data.find(b'\xFF\x51', frame_start)
if siz_pos >= 0:
    # Width at offset +6 (4 bytes), Height at offset +10 (4 bytes)
    original_width = struct.unpack_from('>I', data, siz_pos + 6)[0]
    struct.pack_into('>I', data, siz_pos + 6, original_width + 128)
    # Effect: Image dimensions don't match tile layout →
    # visual tearing, offset tiles, or decoder crash

# 2. Corrupt QCD (quantization step sizes)
qcd_pos = data.find(b'\xFF\x5C', frame_start)
if qcd_pos >= 0:
    marker_length = struct.unpack_from('>H', data, qcd_pos + 2)[0]
    # Quantization values start at offset +5
    # Each is a 2-byte value (exponent + mantissa for irreversible transform)
    for i in range(qcd_pos + 5, qcd_pos + 2 + marker_length):
        if random.random() < 0.3:
            data[i] ^= random.randint(1, 31)  # Corrupt lower bits
    # Effect: Different wavelet subbands get wrong quantization →
    # produces wavelet-specific artifacts: ringing, edge haloing,
    # resolution-dependent blurring/sharpening

# 3. Corrupt decomposition levels in COD marker
cod_pos = data.find(b'\xFF\x52', frame_start)
if cod_pos >= 0:
    # Number of decomposition levels at offset +7
    original_levels = data[cod_pos + 7]
    data[cod_pos + 7] = max(1, original_levels - 2)
    # Effect: Decoder expects fewer wavelet levels than exist →
    # low-resolution base image with wrong detail overlay
    # Creates a blurry base with sharp noise superimposed

# 4. Tile corruption (spatial targeting)
# Find SOT markers (0xFF90) to locate individual tiles
tiles = []
pos = frame_start
while pos < frame_start + frame_size:
    sot_pos = data.find(b'\xFF\x90', pos)
    if sot_pos < 0 or sot_pos >= frame_start + frame_size:
        break
    tile_index = struct.unpack_from('>H', data, sot_pos + 4)[0]
    tile_length = struct.unpack_from('>I', data, sot_pos + 6)[0]
    tiles.append((sot_pos, tile_index, tile_length))
    pos = sot_pos + 2

# Corrupt specific tiles (spatial selection)
for sot_pos, tile_idx, tile_len in tiles:
    if tile_idx % 3 == 0:  # Every third tile
        sod_pos = data.find(b'\xFF\x93', sot_pos)
        if sod_pos >= 0:
            # Corrupt compressed data after SOD marker
            corrupt_start = sod_pos + 2
            corrupt_end = min(corrupt_start + tile_len, frame_start + frame_size)
            for i in range(corrupt_start, corrupt_end):
                if random.random() < 0.01:
                    data[i] ^= random.randint(1, 255)
    # Effect: Checkerboard pattern of corrupt/clean tiles
    # Corrupt tiles show wavelet "ringing" artifacts

# 5. Wavelet coefficient band corruption
# Within compressed tile data, different resolution levels are
# encoded in order: LL (lowest), HL1, LH1, HH1, HL2, LH2, HH2, ...
# Corrupting only the lowest (LL) band destroys the base image
# Corrupting only high-frequency bands (HH) adds noise/edges
# This requires parsing the tile-part data more deeply, but the
# rough approach is to corrupt the first N% for base or last N% for detail

sod_pos = data.find(b'\xFF\x93', tiles[0][0])
tile_data_start = sod_pos + 2
tile_data_size = tiles[0][2] - (tile_data_start - tiles[0][0])

# Corrupt base resolution (first ~10% of tile data)
base_end = tile_data_start + tile_data_size // 10
for i in range(tile_data_start, base_end):
    data[i] ^= random.randint(1, 255)
# Effect: Base image destroyed, detail bands intact →
# "crystalline noise" pattern, edge-only image
```

**JPEG2000-specific visual effects:**
- **Wavelet ringing:** Unlike DCT block artifacts, JPEG2000 corruption produces ringing around edges — concentric halos that echo the shape of objects. This is distinctive and immediately identifiable.
- **Resolution-layer artifacts:** Corrupting specific decomposition levels produces resolution-dependent effects — you can corrupt the low-res base while keeping high-frequency detail, or vice versa. This creates either a blurry image with sharp noise or a sharp image with wrong base colors.
- **Tile boundaries:** JPEG2000 tiles are typically larger than DCT blocks (e.g., 256x256 or 512x512 pixels vs 8x8 or 16x16). Corrupt tiles create a coarser grid pattern.
- **JPEG2000 is all-intra** in MXF (each frame independent), so no temporal propagation.

---

## 5. Programmatic Approaches — Keeping MXF Files Playable

### Strategy: Surgical Corruption

The key to keeping MXF files playable while corrupted is to maintain the container structure while corrupting the essence data:

```python
import struct
import os
import random

class MXFCorruptor:
    # SMPTE UL prefix for all MXF keys
    UL_PREFIX = b'\x06\x0E\x2B\x34'
    
    # Partition pack keys
    HEADER_PARTITION_KEY = bytes([
        0x06, 0x0E, 0x2B, 0x34, 0x02, 0x05, 0x01, 0x01,
        0x0D, 0x01, 0x02, 0x01, 0x01, 0x02, 0x00, 0x00
    ])
    BODY_PARTITION_KEY = bytes([
        0x06, 0x0E, 0x2B, 0x34, 0x02, 0x05, 0x01, 0x01,
        0x0D, 0x01, 0x02, 0x01, 0x01, 0x03, 0x00, 0x00
    ])
    FOOTER_PARTITION_KEY = bytes([
        0x06, 0x0E, 0x2B, 0x34, 0x02, 0x05, 0x01, 0x01,
        0x0D, 0x01, 0x02, 0x01, 0x01, 0x04, 0x00, 0x00
    ])
    
    # Essence element key pattern (bytes 11-12 vary by essence type)
    PICTURE_ESSENCE_PREFIX = bytes([
        0x06, 0x0E, 0x2B, 0x34, 0x01, 0x02, 0x01, 0x01,
        0x0D, 0x01, 0x03, 0x01
    ])
    
    def __init__(self, filepath):
        with open(filepath, 'rb') as f:
            self.data = bytearray(f.read())
        self.file_size = len(self.data)
        self.partitions = []
        self.essence_elements = []
        self._parse_structure()
    
    def _read_ber_length(self, offset):
        """Read BER-encoded length, return (value, num_bytes_consumed)."""
        first_byte = self.data[offset]
        if first_byte < 0x80:
            return first_byte, 1
        num_length_bytes = first_byte & 0x7F
        if num_length_bytes == 0 or num_length_bytes > 8:
            return 0, 1  # Invalid, but don't crash
        length = 0
        for i in range(num_length_bytes):
            length = (length << 8) | self.data[offset + 1 + i]
        return length, 1 + num_length_bytes
    
    def _write_ber_length(self, offset, value, num_bytes):
        """Write BER-encoded length using specified number of bytes."""
        if num_bytes == 1:
            self.data[offset] = value
        else:
            self.data[offset] = 0x80 | (num_bytes - 1)
            for i in range(num_bytes - 1, 0, -1):
                self.data[offset + i] = value & 0xFF
                value >>= 8
    
    def _is_partition_key(self, offset):
        """Check if bytes at offset match a partition pack key pattern."""
        if offset + 16 > self.file_size:
            return False
        key = bytes(self.data[offset:offset + 12])
        return key == self.HEADER_PARTITION_KEY[:12] or \
               key == self.BODY_PARTITION_KEY[:12] or \
               key == self.FOOTER_PARTITION_KEY[:12]
    
    def _is_essence_element(self, offset):
        """Check if bytes at offset are a picture essence element key."""
        if offset + 16 > self.file_size:
            return False
        return bytes(self.data[offset:offset + 12]) == self.PICTURE_ESSENCE_PREFIX
    
    def _parse_structure(self):
        """Scan file for partition packs and essence elements."""
        offset = 0
        while offset < self.file_size - 16:
            if bytes(self.data[offset:offset + 4]) == self.UL_PREFIX:
                if self._is_partition_key(offset):
                    self.partitions.append(offset)
                elif self._is_essence_element(offset):
                    ber_offset = offset + 16
                    length, ber_size = self._read_ber_length(ber_offset)
                    value_offset = ber_offset + ber_size
                    self.essence_elements.append({
                        'key_offset': offset,
                        'value_offset': value_offset,
                        'value_length': length,
                        'ber_offset': ber_offset,
                        'ber_size': ber_size,
                        'total_size': 16 + ber_size + length
                    })
                    offset = value_offset + length
                    continue
            offset += 1
    
    def corrupt_essence_random_bytes(self, frame_indices=None, intensity=0.01,
                                      skip_header_bytes=64):
        """
        Corrupt random bytes within essence frame data.
        
        frame_indices: list of frame numbers to corrupt (None = all)
        intensity: probability of corrupting each byte (0.0-1.0)
        skip_header_bytes: preserve this many bytes at start of each frame
                          (keeps codec frame header intact for parseability)
        """
        targets = frame_indices or range(len(self.essence_elements))
        for idx in targets:
            if idx >= len(self.essence_elements):
                continue
            elem = self.essence_elements[idx]
            start = elem['value_offset'] + skip_header_bytes
            end = elem['value_offset'] + elem['value_length']
            for i in range(start, min(end, self.file_size)):
                if random.random() < intensity:
                    self.data[i] ^= random.randint(1, 255)
    
    def corrupt_essence_block_zero(self, frame_indices, block_offset, block_size):
        """
        Zero out a block within specific frames.
        Creates clean rectangular black areas.
        """
        for idx in frame_indices:
            if idx >= len(self.essence_elements):
                continue
            elem = self.essence_elements[idx]
            start = elem['value_offset'] + block_offset
            end = min(start + block_size, elem['value_offset'] + elem['value_length'])
            for i in range(start, min(end, self.file_size)):
                self.data[i] = 0x00
    
    def corrupt_essence_shift_bytes(self, frame_indices, shift_amount=1):
        """
        Shift all bytes within a frame by N positions.
        Creates a "slipped" visual effect — image looks offset/skewed.
        """
        for idx in frame_indices:
            if idx >= len(self.essence_elements):
                continue
            elem = self.essence_elements[idx]
            start = elem['value_offset'] + 128  # Skip frame header
            end = elem['value_offset'] + elem['value_length']
            length = end - start
            if length <= shift_amount:
                continue
            # Shift data forward, wrapping around
            chunk = bytes(self.data[start:end])
            shifted = chunk[shift_amount:] + chunk[:shift_amount]
            self.data[start:end] = shifted
    
    def corrupt_klv_length(self, frame_indices, factor=0.5):
        """
        Corrupt BER length of essence KLV packets.
        factor < 1.0: shorten (decoder reads partial frame)
        factor > 1.0: lengthen (decoder reads into next frame)
        
        WARNING: This can make the file unplayable if too aggressive.
        """
        for idx in frame_indices:
            if idx >= len(self.essence_elements):
                continue
            elem = self.essence_elements[idx]
            new_length = int(elem['value_length'] * factor)
            if new_length < 16:
                new_length = 16
            self._write_ber_length(elem['ber_offset'], new_length, elem['ber_size'])
    
    def corrupt_every_nth_frame(self, n=10, intensity=0.02, skip_header=128):
        """Corrupt every Nth frame — creates periodic glitch pattern."""
        for idx in range(0, len(self.essence_elements), n):
            elem = self.essence_elements[idx]
            start = elem['value_offset'] + skip_header
            end = elem['value_offset'] + elem['value_length']
            for i in range(start, min(end, self.file_size)):
                if random.random() < intensity:
                    self.data[i] ^= random.randint(1, 255)
    
    def save(self, output_path):
        """Write corrupted data to file."""
        with open(output_path, 'wb') as f:
            f.write(self.data)
```

### Safe Corruption Hierarchy (most playable to least)

1. **Safest — Essence payload only, skip frame headers:**
   Corrupt bytes deep within each frame's compressed data, but leave the first 64-256 bytes (frame header) intact. The container parses correctly, the decoder initializes each frame correctly, but the decoded image has artifacts.

2. **Moderate — Index table manipulation:**
   Keep all essence intact but corrupt index entries. Players that seek or use random access see wrong frames, temporal disorder, or stuttering. Sequential playback may still work fine.

3. **Moderate — Metadata value changes:**
   Change width/height, frame rate, bit depth, color space in the essence descriptor. The decoder runs but interprets data with wrong parameters.

4. **Aggressive — KLV length corruption:**
   Changing BER lengths causes KLV parse failures. Some players recover by scanning for the next valid KLV key; others give up. Limit to a few frames.

5. **Most dangerous — Partition/structural damage:**
   Corrupting partition packs, header metadata structure, or the Random Index Pack. Many players will refuse to open the file. Only do this if you also keep the footer partition intact as a fallback.

### Keeping Footer Intact as Safety Net

```python
def corrupt_safe(self):
    """
    Corrupt strategy that maximizes playability:
    - Never touch footer partition or its metadata
    - Never touch Random Index Pack (last 4+ bytes)
    - Preserve all KLV keys (16-byte ULs)
    - Preserve all BER lengths
    - Only corrupt within essence value payloads
    """
    # Find footer partition offset
    footer_offset = self.partitions[-1] if self.partitions else self.file_size
    
    # Find RIP (Random Index Pack) — always at very end of file
    # RIP starts with key 06 0E 2B 34 02 05 01 01 0D 01 02 01 01 11 01 00
    # Last 4 bytes of file = RIP length (uint32 BE) including these 4 bytes
    rip_length = struct.unpack_from('>I', self.data, self.file_size - 4)[0]
    rip_offset = self.file_size - rip_length
    
    # Only corrupt essence elements that are before the footer
    for elem in self.essence_elements:
        if elem['key_offset'] >= footer_offset:
            continue  # Skip footer essence
        if elem['key_offset'] >= rip_offset:
            continue  # Skip RIP
        
        # Corrupt value payload only, skip first 128 bytes of frame
        start = elem['value_offset'] + 128
        end = elem['value_offset'] + elem['value_length']
        for i in range(start, min(end, self.file_size)):
            if random.random() < 0.005:
                self.data[i] ^= random.randint(1, 255)
```

---

## 6. Unique MXF Corruption Effects vs Consumer Codecs

### Effects Unique to MXF/Broadcast Codecs

**1. Clean Block Artifacts (DNxHD/ProRes):**
Because DNxHD and ProRes are all-intra codecs with relatively simple compression (DCT + Huffman, no inter-frame prediction), corruption produces clean, geometric block artifacts. There is no temporal smearing or motion-vector sliding. Each frame's corruption is self-contained and "crisp." The blocks are typically 8x8 or 16x16 pixels, very regular.

**2. Horizontal Band Corruption (ProRes):**
ProRes's slice structure means corruption can be confined to exact horizontal bands across the frame. This produces a distinctive "scan line corruption" look — clean image above and below, corrupted band in the middle. This is architecturally impossible in H.264/H.265 where slices can be arbitrary.

**3. Wavelet Ringing (JPEG2000):**
JPEG2000 corruption in DCP MXF files produces wavelet-specific artifacts: concentric ringing around edges, resolution-dependent noise, and tile-boundary effects. These look fundamentally different from DCT block artifacts — smoother, more organic, with characteristic halos.

**4. Temporal Propagation Control (MPEG-2 Long-GOP in MXF):**
MXF's index table lets you precisely target I, P, or B frames. You can:
- Corrupt only I-frames → persistent block artifacts that last exactly one GOP
- Corrupt only B-frames → intermittent glitching that appears and disappears
- Corrupt only P-frames → artifacts that build up progressively within a GOP
- Use the index table to corrupt every Nth GOP → rhythmic visual corruption

**5. KLV-Level Frame Dropping:**
By corrupting KLV keys on specific essence elements, you can make the MXF parser skip individual frames without touching the essence data at all. The result is clean frame drops — no visual artifacts, just temporal gaps. This is impossible in MP4 without modifying the sample table.

**6. Dual-Metadata Inconsistency:**
Corrupting the header metadata while leaving the footer intact (or vice versa) creates a unique situation where different players render the same file differently — a player that reads the header sees one thing, a player that falls back to the footer sees another. You could have one player decode at 1920x1080 and another at 960x540 from the same file.

**7. Partition-Boundary Glitching:**
In multi-partition MXF files (common in long-form content), corrupting the body partition packs but not the essence creates a situation where the player loses track of where it is in the file. This produces sudden jumps — the video may suddenly skip forward or backward to a different partition's content.

**8. Professional Color Space Artifacts:**
Broadcast MXF files typically use 10-bit 4:2:2 color (or even 12-bit 4:4:4 for JPEG2000/ProRes 4444). Corrupting the bit depth or chroma subsampling metadata produces different artifacts than consumer 8-bit 4:2:0:
- 10-bit→8-bit: Smooth gradients suddenly band, but shadows and highlights clip differently
- 4:2:2→4:2:0: Color resolution halves vertically, producing vertical color bleeding
- 4:4:4→4:2:2: Chroma channels suddenly subsample, producing edge color fringing

### Summary of Visual Signatures by Codec

| Codec | Artifact Style | Temporal Behavior | Distinctive Look |
|-------|---------------|-------------------|------------------|
| DNxHD | Clean 16x16 blocks | Per-frame only | Tile shuffle, brightness checkerboard |
| ProRes | Horizontal bands | Per-frame only | Scan-line corruption, color blowout |
| MPEG-2 Long-GOP | Smearing blocks | Propagates through GOP | Frozen blocks, motion trails |
| MPEG-2 I-only | Clean 16x16 blocks | Per-frame only | Similar to DNxHD but with MPEG artifacts |
| JPEG2000 | Wavelet ringing, tiles | Per-frame only | Edge halos, resolution-layer noise |

---

This research covers the structural, codec-level, and programmatic details needed to implement MXF corruption in a video corruptor application. The key implementation files that would need this information are the MXF parser (KLV scanning, partition detection, essence element enumeration) and the codec-specific corruption modules (one per codec family: DNxHD, ProRes, MPEG-2, JPEG2000).