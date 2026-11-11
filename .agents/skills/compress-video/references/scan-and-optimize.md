# Scan and optimize project videos

Discover and optimize videos used across the website's source project, then
update their references and verify the result. Require access to the source
code in the current workspace or supplied project path. Cover the whole source
project by default; a live or local URL is used to verify rendered behavior.
Honor explicit scope limits.

## Inspect

Follow [audit.md](audit.md) to discover usages, locate originals, measure display
requirements, and identify candidates. Continue into optimization without
requiring a separate audit invocation or approval of the audit report.

Create a working inventory linking each logical video to its sources, usages,
target dimensions, and replacement paths. Resolve shared and fullscreen usages
before choosing a target. Do not treat files merely present in an asset folder
as proof that the site uses them.

## Configure outputs

- Read [compression.md](compression.md) for encoder flags and default codec/CRF
  pairs. Start with those defaults unless overridden; AV1 remains opt-in.
  Use the best available source and the audit's target dimensions. Ask about
  frame-rate reduction once for affected videos and reuse the answer.
- Run [comparison.md](comparison.md) only when the user requests a comparison.
  Otherwise, proceed directly to full encoding without trial encodes or SSIM.
- Apply the compression workflow's audio rules. Preserve audio users can play;
  remove audible audio only for a confirmed video-only use or explicit request.

## Encode and integrate

- Encode full outputs directly from the best available source with the selected
  transforms and settings. Process each unique source/settings combination once.
- Verify successful decoding, dimensions, duration, frame rate, pixel format,
  and required audio. Compare actual sizes with the delivered versions they would
  replace. Apply only improvements supported by the full outputs; identify
  replacements driven by a separate user requirement.
- Inspect playback at the intended display size, including text and motion.
  Honor user quality and savings targets. Try a lower CRF or keep the current
  asset if the result visibly degrades or offers no worthwhile improvement.
- Update source components, templates, content, or asset manifests using the
  project's conventions. Retain required browser fallbacks and any larger source
  needed for fullscreen or other placements. Preserve captions, poster behavior,
  controls, autoplay, looping, and layout.
- Keep URLs and MIME types consistent with the generated containers. Use the
  compression reference's AV1 codec declaration rules when AV1 is requested.
  Change loading behavior only where the audit found a concrete issue.
- Treat CMS uploads, managed storage updates, and deployment as separate actions;
  identify what remains when repository edits alone cannot publish a replacement.

## Verify and report

Run the project's relevant checks and revisit affected pages at the inspected
layouts. Verify the selected sources, playback, audio, captions, and any enlarged
player. Check browser compatibility against the project's supported targets;
retain a fallback when compatibility has not been established.

Report changed files, per-video before/after sizes and dimensions, source choices,
settings and commands, skipped assets with reasons, and inspected route coverage.
Count shared assets once in storage totals. Distinguish storage changes from
playback transfer savings: browsers usually fetch one selected source, so adding
two fallback formats does not mean both are downloaded for each playback.
State verification gaps and any remaining publishing steps.
