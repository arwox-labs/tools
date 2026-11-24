# Audit website videos

Inspect the requested page or scope and report improvements without changing
the website. Start with its source code in the current workspace or supplied
project path; ask for repository access if unavailable. Use a live or local URL
to verify the rendered behavior. Reuse an existing development server or the
project's documented startup command when no URL is supplied.

## Find videos and originals

- Inspect source routes, components, content, and asset references. For a
  whole-project audit, combine these with the sitemap and internal links.
- Open relevant pages in a browser. Scroll and exercise video-related UI to
  reveal lazy-loaded videos, galleries, and modal players. Record `<video>`,
  `<source>`, and the selected `currentSrc`; map URLs back to project files
  or managed asset locations.
- Group alternate encodes of the same content and record every usage. Deduplicate
  repeated assets while retaining page, component, and display requirements.
- Ask once whether original recordings or highest-quality exports are available
  and where, unless already known. Continue inspection while waiting. Search the
  repository and supplied locations; verify matching content, edit, and duration.
  Prefer a confirmed original over a previously compressed derivative. File size,
  bitrate, and filenames alone do not establish source quality.
- When originals are unavailable, use the current asset and record that limitation.
  List third-party players, adaptive streams, inaccessible pages, and unresolved
  assets separately from files this workflow can re-encode and replace.

## Measure required resolution

- Check mobile, tablet, and desktop layouts, project breakpoints, and larger
  supported layouts. Record the largest rendered picture size for each usage.
  Account for both dimensions, aspect ratio, rotation, and `object-fit` cropping;
  the element's bounding box alone may not describe the displayed picture.
- Default to a maximum of **2 source pixels per rendered CSS pixel** for inline
  playback. Honor a user-specified density. Preserve aspect ratio, round output
  dimensions down to even values, and never upscale.
- **Example:** if the largest inline display width is 620 CSS pixels, the 2×
  rule gives a maximum encoded width of 1240 pixels. Verify height and cropping too.
- Check fullscreen, lightbox, picture-in-picture, download uses, and larger
  placements before reducing a shared asset. Missing controls do not prove that
  enlargement is impossible. Keep a larger version for those uses or create a
  separate inline derivative. If requirements are uncertain, flag them before
  replacing the shared source.
- For a shared output, use the largest requirement across its usages. A page-only
  audit recommends dimensions for that placement; it does not establish that
  replacing the asset globally is safe.

## Assess opportunities

Inspect each available file with:

```sh
ffprobe -v error -show_format -show_streams -of json INPUT
```

Record dimensions, duration, frame rate, codecs, pixel format, audio, and bytes.
Distinguish measured issues from potential savings that need encoding to confirm:

- **Excess resolution:** dimensions exceed the measured playback requirement.
- **Potential compression savings:** codec, bitrate, or file size alone cannot
  establish encoding efficiency. Confirm savings from actual encoded outputs.
- **Unnecessary audio:** check silence or a confirmed video-only use. A muted
  player can still allow users to enable sound.
- **Delivery issues:** inspect source ordering, preload behavior, posters, and
  below-the-fold loading in context. Keep these separate from encoding savings.

Run [comparison.md](comparison.md) only when the user requests a comparison.

## Report

Provide a table of video, pages/usages, current dimensions and bytes, maximum
display size, recommended dimensions, best available source, evidence, and action.
Mark savings as unmeasured unless tested. State inspected routes, layouts, and
interaction states, plus any gaps in coverage. Prioritize likely byte savings
and videos fetched during initial page load.
