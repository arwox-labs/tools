# Compression

1. **Inspect the source**

Check that FFmpeg, FFprobe, and the required encoders are available.

Inspect duration, dimensions, rotation, pixel format, and audio streams:

```sh
ffprobe -v error -show_format -show_streams -of json INPUT
```

Read `avg_frame_rate`, falling back to `r_frame_rate` if invalid.
Retain rational frame rates throughout calculations.

2. **Configure the outputs**

By default, create two compressed versions of the source video:

- `video-vp9.webm`: VP9 video in a WebM container.
- `video-h265.mp4`: H.265 video in an MP4 container.

Use these CRF values by default for compression unless the user
requests different values:

- VP9: `42`.
- H.265: `30`.
- AV1: `42` (when AV1 is requested).

Honor explicitly requested codecs and apply requested CRF overrides
to the commands below.

Use this command structure, replacing placeholders:

```sh
ffmpeg -hide_banner -nostdin -n -i INPUT -map 0:v:0 \
  VIDEO_FLAGS FILTER_FLAGS AUDIO_FLAGS OUTPUT
```

Choose fresh output paths if files already exist.

**VP9/WebM — `video-vp9.webm`**

```text
-c:v libvpx-vp9 -b:v 0 -crf 42 -deadline best -pix_fmt yuv420p
```

Audio removed:

```text
-an
```

Audio kept:

```text
-map 0:a:0 -c:a libopus
```

**H.265/MP4 — `video-h265.mp4`**

```text
-c:v libx265 -crf 30 -preset veryslow -tag:v hvc1
-movflags faststart -pix_fmt yuv420p
```

Audio removed:

```text
-an
```

Audio kept:

```text
-map 0:a:0 -c:a aac
```

Apply exactly one audio branch per output. When keeping audio,
use the encoder’s default audio bitrate.

3. **Decide whether to keep audio**

Honor explicit preferences:

- Remove: use `-an`.
- Keep: retain the first audio stream, including silence.
  Report an error if no audio stream exists.

Otherwise, analyze every audio stream over its full duration.
Apply this filter separately to each stream:

```text
astats=metadata=1:reset=0,ametadata=mode=print:key=lavfi.astats.Overall.Peak_level:file=-:direct=1
```

Read the maximum reported peak across all streams:

- No audio streams, or maximum peak <= -50 dBFS: use `-an`.
- Any peak > -50 dBFS: keep the first audio stream.

Treat `-inf` as silence. Failed or incomplete analysis is an error,
not evidence of silence.

4. **Handle dimensions**

Preserve source resolution and display orientation by default.

Normalize odd dimensions:

- If width is odd, use `scale=WIDTH_MINUS_ONE:-2`.
- Otherwise, if height is odd, use `scale=-2:HEIGHT_MINUS_ONE`.
- If both dimensions are even, no normalization filter is needed.

Apply requested cropping before resizing. Preserve aspect ratio
when resizing and upscale only when explicitly requested.
Combine video filters into one `-vf` chain.

5. **Handle frame rate**

Preserve frame rate at or below 30 fps.

Above 30 fps, ask whether to preserve motion or cap the frame rate.
Recommend capping for ordinary web playback. Reuse any preference
already provided.

For a requested cap, let `f` be the source frame rate:

- If `30 < f < 50`, use `fps=30`.
- If `f >= 50`, calculate `d=max(2,floor(f/30+0.5))`.
  Use `fps=f/d` when that is <=30; otherwise use `fps=30`.

Retain exact rational rates: `60000/1001` becomes `30000/1001`.
Append the frame-rate filter after crop and scale filters.
When preserving cadence, omit the frame-rate filter.

6. **Handle optional AV1 and 10-bit output**

Add AV1 only when explicitly requested.

**AV1/WebM — `video-av1.webm`**

```text
-c:v libsvtav1 -b:v 0 -crf 42 -preset 6 -pix_fmt yuv420p
```

Use `-an` when removing audio, or
`-map 0:a:0 -c:a libopus` when keeping it.

Default to 8-bit output, including for 10-bit sources.
When explicitly asked for 10-bit, replace `yuv420p` with
`yuv420p10le` for every output and verify the result with FFprobe.
Never silently substitute 8-bit for a 10-bit request.

7. **Verify and deliver**

Wait for every encode to finish. Verify output codecs, dimensions,
frame rate, pixel format, audio presence, and successful decoding.

Report:

- Output paths.
- Original and output file sizes.
- Percentage savings for each output.
- The actual commands used.

Create an HTML snippet using relative paths. Include an explicit
`codecs` parameter only for AV1.

Derive the AV1 codec string from the encoded file’s profile, level,
tier, and bit depth. Append `,opus` only when audio is present.
For example, `av01.0.05M.08,opus` applies only when those values
match the encoded file.

```html
<video controls preload="metadata">
  <source src="./video-av1.webm" type='video/webm; codecs="AV1_CODECS"'>
  <source src="./video-vp9.webm" type="video/webm">
  <source src="./video-h265.mp4" type="video/mp4">
</video>
```

Include the AV1 source only when that output was created.
Replace `AV1_CODECS` with the actual codec declaration and adapt
filenames to the actual outputs.
