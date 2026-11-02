# Five Llamascope scenes

These additions extend the native prototype introduced by PR #2. The scene expansion keeps capture-start and AGENTS.md policy work separate.

## Composition and musical roles

All five use the existing intensity default of 1 and persistence default of 0.72. The silhouette and field defaults remain composed at silence. Suggested palettes are Ultraviolet for Outrun and Crystal, Ice for Galaxy, Mint for Rain, and Ember for Plasma; the gallery applies these presets. Normal scene selection preserves the output's existing palette and sliders.

Outrun Horizon keeps a fixed horizon, steady forward grid travel, layered dark mountain silhouettes, and a striped sun. Spectrum bands set individual distant building heights, bass accents the grid, and highs reveal stars. Bass does not pump the entire sky. This translates the layering in [outrun.go](https://github.com/MrBrooks-code/llamascope/blob/main/visualizers/outrun.go).

Crystal Mandala combines the faceted crowns of [kaleidoscope_crystalline.go](https://github.com/MrBrooks-code/llamascope/blob/main/visualizers/kaleidoscope_crystalline.go) with the layered diamonds of [kaleidoscope_mandala.go](https://github.com/MrBrooks-code/llamascope/blob/main/visualizers/kaleidoscope_mandala.go). Three slowly counter-rotating crowns separate high, mid, and bass structure; spectral detail varies their tips. A transient briefly lights selected faces. Dark gaps and two-tone faces make solid geometry, with no feedback bloom.

Spiral Galaxy retains four band-sensitive arms and a bass-lit core from [spiral_galaxy.go](https://github.com/MrBrooks-code/llamascope/blob/main/visualizers/spiral_galaxy.go). A tilted disc, two particle depths, local streaks, and short previous-image decay give orbital depth. Transients briefly reveal selected stars. Neighbor-cell sampling bounds GPU work independently of particle count; no frame-dependent spawn or sort is used.

Digital Rain translates [matrix_rain.go](https://github.com/MrBrooks-code/llamascope/blob/main/visualizers/matrix_rain.go) into legible procedural 5 × 7 glyphs, rather than the reference's rectangular strokes. Two depths have separate cell sizes, stable varied speeds, lengths, spacing, and bright heads. Spectrum-mapped columns brighten and activate; hits activate clustered eligible columns, and highs sparkle glyphs. Every palette works through the existing ink function.

Plasma Drift carries forward the slow moving Gaussian sources of [plasma.go](https://github.com/MrBrooks-code/llamascope/blob/main/visualizers/plasma.go). Five continuous sources merge and separate under restrained warp. Bass changes their radius, mids shape the flow, highs lift the contours, and hits briefly highlight one energy boundary. It uses no radial folding or recursive image warp.

The original repository was read only. Existing Phosphor scenes, saved names, IDs 0–2, capture, mirrored texture ownership, and coordinated setting resolution remain intact. New IDs are explicit 3–7; the saved document remains version 1.

## Repeatable native checks

Build the separate gallery and run the commands in README. `--validate-scenes` compiles the same bundled Metal source, renders the five scenes at 640 × 360, 1920 × 1080, 3840 × 2160, and 2160 × 3840, and exports 1080p and both 4K orientations. Its inputs are deterministic synthetic features at a fixed clock and phase. It compares isolated bass/mid/high/hit fixtures, all four palettes, zero intensity, time changes, and output phase changes. Outrun deliberately has no hit flash. Floating-point pixel checks reject non-finite or negative fields. The timing report measures scene plus presentation passes and an input-texture clear, with ten warm command samples per size. This is a short GPU workload check, not a sustained performance or display-pacing claim.

## Native observations — November 1, 2026

The release `Phosphor Scenes.app` launched as its own application beside the running capture-worktree app. The original app was neither quit nor replaced, and Music playback was not changed. All five new compositions were inspected in actual presentation windows. Five independent outputs were open together; the window menu listed all five. Native checks exercised Galaxy fullscreen/Escape, display selections, native and half-resolution quality, a live Crystal-to-Plasma switch, and an Ice palette change that visibly reached that window. Galaxy was switched through Coordinated, Mirrored, and Independent. The desk showed the coordinated Galaxy/Ultraviolet resolution, the mirrored window visibly showed Outrun's rendered image, and Independent restored Galaxy/Ice and its own quality/persistence. Gallery relaunch resets these temporary changes.

The native desk enumerated four physical displays. Selections for BenQ GW2790T, LC32G7xT, and U32J59x were exercised, but this task does not claim a controlled simultaneous fullscreen run on all three. Fullscreen transition resized the real drawable and returned to a window with Escape. A freeform corner-drag attempt did not reach the window, so arbitrary drag-resize is not accepted. The shader checker separately exercises both 4K orientations; its aspect checks are visual inspection, not a physical 4K pacing test.

The eight CoreChecks pass with zero failures, including stable original scene IDs/names, all five new saved outputs, role restoration, and independent settings. The release build and ad-hoc signature check pass. The native packaged shader checker completes with finite, nonnegative fields, isolated band/hit responses, all four palettes, zero-intensity black output, time changes, and phase changes. Outrun's hit-only fixture correctly leaves the image unchanged. See [the recorded GPU/check output](SCENE_GPU_CHECKS.txt).

At 3840 × 2160 the final short-run GPU medians were 0.533 ms Outrun, 0.498 ms Crystal, 2.452 ms Galaxy, 0.333 ms Rain, and 0.241 ms Plasma on Apple M3 Ultra. These are ten warm offscreen command samples per scene, with textures reused, and include a clear plus scene/presentation passes. They are not sustained or simultaneous multi-4K measurements. The native desk reported variable presentation rates during focus, overlap, and display changes, from 0–1 fps on a moved/obscured Galaxy to roughly 12–41 fps on the other windows. Those counters do not establish smooth 60 fps; visible pacing, sustained memory, multi-display performance, and owner musical-feel acceptance remain open. No refresh-rate or frame-lock claim is made.

Capture was stopped in the existing app when first inspected, and this task deliberately leaves capture startup to its separate chat. Every preview and response fixture here is synthetic. No new actual-audio or Apple Music capture acceptance is claimed. The normal build retains capture; the development gallery disables it and labels both the desk and window names. During the original scene validation, no release, merge, or notarization occurred.

## Local artifacts

The launchable separate development app is `/Users/brooks/.codex/worktrees/de8f/llamascope/build/Phosphor Scenes.app`. Its gallery is temporary and synthetic. The normal app is built with `scripts/build.sh` when actual capture is desired.

Previews are real native Metal renders with deterministic synthetic inputs, not concept images or captured-audio screenshots. All are under `/Users/brooks/.codex/worktrees/de8f/llamascope/build/scene-previews/`:

| Scene | 1080p preview |
| --- | --- |
| Outrun Horizon | `3-Outrun-Horizon.png` |
| Crystal Mandala | `4-Crystal-Mandala.png` |
| Spiral Galaxy | `5-Spiral-Galaxy.png` |
| Digital Rain | `6-Digital-Rain.png` |
| Plasma Drift | `7-Plasma-Drift.png` |

Each also has a `-4k.png` landscape export and a `-portrait.png` 2160 × 3840 export. `shader-checks.txt` contains the raw check/timing report. Build artifacts are deliberately untracked and can be reproduced with README commands.
