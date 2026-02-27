# Glitch Art & Video Corruption Techniques

## 1. Datamoshing

### 1a. I-Frame Removal ("Melt" / Transition Effect)

Remove I-frame at scene cut → decoder applies new scene's motion vectors to old scene's pixels.

**Workflow:**
```bash
ffmpeg -i input.mp4 -c:v mpeg4 -vtag xvid -qscale:v 4 -g 9999 -bf 0 -an output.avi
```
Then delete I-frames via Avidemux or programmatic AVI editing. Save without re-encoding.

**Parameters:** Which I-frames to remove, how many, preserve first I-frame.

### 1b. P-Frame Duplication ("Bloom" / Pixel Drift)

Duplicate a P-frame with strong motion 20-50+ times → motion vectors applied repeatedly → pixels streak and bloom.

**Parameters:** Which P-frame (by motion intensity), number of duplicates.

### 1c. Frame Reordering

| Technique | Result |
|-----------|--------|
| Shuffle | Chaotic jumps with moshing at boundaries |
| Reverse | Backward motion + GOP boundary artifacts |
| Sort by size | Unusual temporal progressions |
| Jiggle | Stuttering, vibrating instability |
| Overlap | Deja-vu repetition with drift |

---

## 2. FFglitch (Bitstream-Level Manipulation)

### Supported Codecs & Features

**MPEG-2 (9 features):**
- `q_dct` / `q_dct_delta`: Quantized DCT coefficients (DC + 63 AC per 8x8 block)
- `q_dc` / `q_dc_delta`: DC-only (gross brightness/color)
- `mv` / `mv_delta`: Motion vectors (absolute / delta)
- `qscale`: Quantization scale per slice/MB
- `mb`: Raw macroblock bytestream

**MPEG-4 (5 features):**
- `mv` / `mv_delta`: Motion vectors with overflow control
- `mb`: Raw MB bytestream with bit-size metadata
- `gmc`: Global Motion Compensation (frame-level warping)

**MJPEG/JPEG:**
- `dqt`: Quantization tables (64-value arrays)
- `q_dct`: DCT coefficients per 8x8 block

**PNG/APNG:**
- `filter_row`: Per-row filter type and pixel data

### FFglitch Workflow

```bash
# Prepare source
ffgac -i input.mp4 -an -mpv_flags +nopimb+forcemv -qscale:v 0 -g max -sc_threshold max -vcodec mpeg2video -f rawvideo -y temp.mpg

# Apply script
ffedit -i temp.mpg -f mv -s script.js -o output.mpg
```

Key flags:
- `+forcemv`: Force encoding zero MVs (so they exist to modify)
- `+nopimb`: No I-type MBs in P-frames (prevents self-healing)
- `-g max -sc_threshold max`: No keyframe limits (glitches persist)

### Script API

```javascript
function glitch_frame(frame) {
    let mvs = frame["mv"];
    if (!mvs) return;
    let fwd = mvs["forward"];
    // fwd[row][col] = [x, y] per macroblock
    // null = intra-coded MB
}
```

MV objects support: `add()`, `sub()`, `mul()`, `div()`, `assign()`.

### FFglitch Effect Types

| Effect | Technique | Visual |
|--------|-----------|--------|
| Sink/Rise | Zero one MV component | Pixels drift one direction |
| Average MV | Rolling buffer over N frames | Smooth liquid distortion |
| Random MV | Random values | Chaotic displacement |
| Scaled MV | Multiply by constant | Exaggerated motion |
| Rotated MV | Swap H/V components | Diagonal/spiral drift |
| Frozen MV | Copy one frame's MVs forward | Persistent smear |
| DCT zeroing | Zero AC coefficients | Posterization/blockiness |
| QScale manipulation | Vary per macroblock | Selective quality |
| MB swap | Reorder raw bytestreams | Spatial scrambling |

---

## 3. Pixel Sorting

### Algorithm
1. Define brightness/hue threshold range (e.g., 0.25-0.8)
2. Scan each row/column, find contiguous runs within threshold
3. Sort pixels within each run by chosen property
4. Write sorted pixels back

### Parameters

| Parameter | Range | Effect |
|-----------|-------|--------|
| Direction | Rows / Columns / Both | Horizontal vs vertical streaks |
| Sort key | Brightness / Hue / Sat / R / G / B | What determines order |
| Trigger channel | Same options | What defines run boundaries |
| Lower threshold | 0.0-1.0 | Blacks excluded below |
| Upper threshold | 0.0-1.0 | Whites excluded above |
| Mode | Threshold / Random | Deterministic vs random runs |

### FFgac Native Pixel Sort

```javascript
ffgac.pixelsort(data, [y_range], [x_range], {
    mode: "threshold",
    colorspace: "yuv",
    order: "columns",
    trigger_by: "y",
    sort_by: "y",
    threshold: [0.25, 0.8],
    clength: 0.5
});
```

---

## 4. Channel Shifting / Color Corruption

### YUV Plane Manipulation

| Technique | Implementation | Result |
|-----------|----------------|--------|
| Plane swap | Exchange U↔V data | Color inversion |
| Plane offset | Shift U/V by N pixels | Chromatic aberration |
| Y-only corruption | Corrupt Y, keep U/V | Brightness glitches |
| Chroma-only | Corrupt U/V, keep Y | Psychedelic color |
| Plane deletion | Zero one chroma plane | Partial desaturation |

### Color Space Conversion Errors

```bash
# Treat YUV as RGB
ffmpeg -i input.mp4 -vf "format=rgb24,format=yuv420p" output.mp4

# Wrong matrix coefficients
ffmpeg -i input.mp4 -vf "colorspace=bt709:iall=bt601" output.mp4
```

---

## 5. FFmpeg Corruption Tricks

### Bitstream Noise (Direct Corruption)
```bash
ffmpeg -i input.mp4 -bsf:v noise=amount=0.01 -c:v copy output.mp4
# amount: 0.001-0.05 for interesting results
```

### Temporal Blend / Trails
```bash
ffmpeg -i input.mp4 -vf "tblend=all_mode=difference128" output.mp4
# Modes: addition, multiply, screen, xor, difference128, pinlight
```

### Pixel Persistence (Lagfun)
```bash
ffmpeg -i input.mp4 -vf "lagfun=decay=0.97" output.mp4
```

### Displacement Map
```bash
ffmpeg -i base.mp4 -i displacement.mp4 \
  -filter_complex "[1]scale=iw:ih[d]; [0][d]displace=edge=wrap" output.mp4
```

### Extreme Compression
```bash
ffmpeg -i input.mp4 -c:v libx264 -crf 51 -preset ultrafast output.mp4
```

### Bitplane Extraction
```bash
ffmpeg -i input.mp4 -vf "lutyuv=y='bitand(val,128)*2'" output.mp4
# Change 128 to 64/32/16/8/4/2/1 for different planes
```

### Generation Loss (Re-encode Loop)
```bash
for i in $(seq 1 20); do
  ffmpeg -i pass_$((i-1)).mp4 -c:v libx264 -crf 40 pass_$i.mp4
done
```

---

## 6. Existing Tools

| Tool | Platform | Approach | Strengths |
|------|----------|----------|-----------|
| **FFglitch** | CLI | Bitstream JavaScript scripting | Most precise, valid output |
| **Avidemux** | GUI | Manual I-frame deletion in AVI | Intuitive for beginners |
| **moshpit** | CLI (Go) | Scene detection + I-frame removal | Automated detection |
| **moshy** | CLI (Ruby) | AVI frame manipulation | Scripted workflows |
| **Datamosher-Pro** | GUI (Python) | 35+ algorithms | Widest variety |
| **Datamosh 2** | AE/Premiere plugin | 60+ algorithms | NLE integration, ~$60-80 |
| **Pixel Sorter 3** | AE/Premiere plugin | Pro pixel sorting | Masking support, ~$60 |

---

## 7. Master Effect Classification

### By Controllability

**Tier 1 — Fully Deterministic:** Pixel sorting, channel offset/swap, color space conversion, bitplane extraction, temporal blend, generation loss

**Tier 2 — Parameterized:** MV manipulation, DCT/QP manipulation, lagfun, displacement, bitstream noise (seeded), I-frame removal, P-frame duplication

**Tier 3 — Semi-Random:** Hex corruption, frame shuffle, MB reorder

**Tier 4 — Chaotic:** Large-region hex corruption, random MV assignment, SPS/PPS corruption

### By Playability Risk

**Safe:** All pixel-level ops, FFglitch MV/DCT/QP, FFmpeg filters

**Low Risk:** I-frame removal in AVI, P-frame duplication, frame reordering, bitstream noise <0.05

**Medium Risk:** Hex corruption of mdat, bitstream noise 0.05-0.2, MB manipulation, slice header corruption

**High Risk:** SPS/PPS corruption, large hex corruption, container atom modification, noise >0.2

---

## 8. Recommended App Mode Taxonomy

### Category 1: Datamosh (Interframe)
- I-Frame Removal (Melt)
- P-Frame Bloom (Drift)
- Frame Shuffle
- Motion Transfer (from another video)

### Category 2: Motion Vector (Codec-Level)
- MV Drift (zero one axis)
- MV Scale (exaggerate motion)
- MV Smooth (temporal averaging)
- MV Randomize (chaos)

### Category 3: Frequency Domain
- DCT Zeroing (posterize/blockify)
- Quantization Shift (selective quality)
- Generation Loss (re-encode cycling)

### Category 4: Pixel Operations
- Pixel Sort (rows/columns, threshold)
- Channel Offset (chromatic aberration)
- Channel Swap
- Color Space Misinterpret

### Category 5: Byte-Level
- Bitstream Noise (controlled random)
- Hex Scatter (targeted byte corruption)
- NAL Shuffle (copy between units)

### Category 6: Temporal
- Temporal Blend (XOR, difference, screen, etc.)
- Pixel Persistence (lagfun decay)
- Echo / Ghost Trail

### Category 7: Spatial
- Displacement Map (video-driven warping)
- Macroblock Scramble
- Bitplane Extraction
