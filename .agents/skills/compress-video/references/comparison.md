# Compare quality

Run only when the user requests a quality or size comparison, including
when using `scan-and-optimize`.
Read [compression.md](compression.md) for source inspection and encoder settings.
For standalone comparisons, inspect the source first.

- Compare 2–8 codec/CRF pairs, for example VP9 at 36/42/48
  and H.265 at 24/30/36. Honor requested candidates.
  Include AV1 only when requested.
- Default to three 1-second samples centered at 25%, 50%, and 75%
  of the source duration, clamped to file bounds. Honor requested
  sample positions and durations.
- Create one shared lossless video-only FFV1/MKV reference reel using
  `trim`, `setpts`, and `concat`, with the requested crop, scale,
  and bit depth. Encode every candidate from this reference using
  the presets in [compression.md](compression.md) and `-an`.
- Measure SSIM against the reference with FFmpeg; add PSNR when
  requested. Align timestamps and corresponding frames.
  Save a preview video and matching still for each candidate.
- Estimate full-video bytes as
  `ceil(preview_bytes × source_duration / reference_duration)`.
  Label this a video-only estimate.
- Select a recommendation internally. On the Pareto frontier, normalize
  SSIM and size to 0–1, favoring higher SSIM and smaller size,
  then select the highest average score. Treat a zero range
  as 1; break ties by smaller size, then higher SSIM.

## Report

Show a Markdown table with exactly these columns: **Format**, **CRF**,
**Estimated size**, and **File**. Use one row per candidate, grouped by format
and ordered by increasing CRF within each group. Separate the format and CRF;
use readable sizes with consistent units.

Use this structure, replacing the example rows with the actual results:

```markdown
| Format | CRF | Estimated size | File |
| --- | ---: | ---: | --- |
| VP9 / WebM | 42 | SIZE | [Preview](VP9_PREVIEW_PATH) |
| H.265 / MP4 | 30 | SIZE | [Preview](H265_PREVIEW_PATH) |
```

Link each File cell directly to that candidate's generated preview video.
Use an absolute local path, wrapping paths containing spaces in angle brackets.
Verify the files exist before linking them. The table must include the file
links even if a separate comparison viewer is also created.

Keep SSIM, PSNR, and Pareto markers out of the default report. If the user
explicitly requests metrics, show them separately from this table.

After the table, recommend one format/CRF pair in plain language. Briefly report
sample positions and coverage, and explain that sizes estimate the full video
while the linked files are video-only sample previews. Single or clustered
samples provide weaker whole-video evidence.

For comparison-only requests, finish with these results.

These metrics measure encoding loss against the transformed reference;
inspect resizing separately at the intended display size. Short samples
provide estimates, not a guarantee of full-video quality or size.
