# Phosphor V2: light inside dark space

The owner accepted this direction on November 3, 2026 and authorized making it the main version. The five V2 fields are now the default in normal Phosphor builds. Saved names/IDs, output roles, preferences, Reactivity/Intensity semantics and capture code remain compatible. The original isolated preview started from main `a80474a` (PR #5); the validation history below distinguishes that preview from its later production-default promotion. The capture-startup and repository-policy branches remain separate.

## Collection critique

The delivered fields have useful restraint and readable silhouettes. Their weakness is a common pictorial construction: bright outlines over nearly flat procedural layers. More exposure would exaggerate that limitation. V2 should give light something to describe: mass, gaps, surface direction, depth and events with a location.

| Scene | Keep | Limitation | Proposed artistic step |
| --- | --- | --- | --- |
| Phosphor Scope | Actual stereo trace, persistence and spectrum | Trace and spectrum compete with a very quiet instrument frame | Refine graticule, trace weight and spectrum placement around the actual signal. Keep silence honest; never add invented trace motion. |
| Feedback Bloom | Recursive motion and organic memory | Petal injection and peripheral filaments readily become a generic radial glow | Give the injection a directional, calligraphic shape and reserve dark intervals. Distinguish freshly written light from old memory. |
| Vector Tunnel | Immediate depth cue and integrated travel | Uniform nested hexagons have little architecture or surprise | Break the symmetry with solid ribs, hidden sections and long dark intervals; use treble as sparse guide lights. |
| Outrun Horizon | Strong distant silhouette and legible forward motion | Familiar grid and striped-sun postcard; buildings look like a spectrum display | Make a designed curving route through layered terrain, with a small skyline, reflected light and an eclipsed source. |
| Crystal Mandala | Facets, symmetry and separate band roles | Three necklaces of flat diamonds rotate without convincing occlusion | Replace them with a solid mechanical iris whose prisms overlap and unfold in depth around negative space. |
| Spiral Galaxy | Inclined disc and orbital movement | Uniform arms and a bright disk core flatten the space | Add irregular arm branches, three star depths, dark dust and a compact central bulge with a crossing dust lane. |
| Digital Rain | Legible 5×7 glyphs and clear heads | Unrelated columns fill similar visual roles | Group streams into shared wave fronts; retain empty lanes, depth and selective signal events. |
| Plasma Drift | Continuous movement and restrained palette | Soft scalar contours resemble a heat map | Define a material: thin flowing glass ribbons, with surface shading, cut edges, internal lines and overlap. |

The five derived scenes receive the substantive treatments in this preview. Scope, Bloom and Tunnel remain the delivered implementation so that polishing all eight does not dilute the experiment. The baseline was inspected through native synthetic windows and the existing native GPU fixtures. A synthetic Scope gallery has no waveform; its empty trace is correct. The fixture checker separately draws known stereo test points. These are distinct from captured-audio evidence.

## Shared identity, different motion

Darkness is structural space. One dominant silhouette or field should read before its details. Colors remain within the existing four palettes; pale highlights describe material rather than adding a second color cycle. Camera movement stays slow and small. Fast onsets have a local address, sustained energy changes a structural part, and elapsed time carries continuity. Reactivity still scales bounded features; Intensity still controls linear exposure.

Outrun uses an analytic perspective road with a smooth, designed bend and tapering rails. Multiple dark ridges and a compact city sit below an eclipsed light source. Integrated bass-sensitive travel advances road markers; bass also changes the narrow reflected light and shoulder markers. Spectrum shapes distant towers, mids light windows, treble reveals their caps, and hits pick out passing rail markers. The sky does not pulse. The route remains readable at silence. Portrait framing scales the source radius and horizontal placement to keep its silhouette inside the viewport.

Crystal intersects camera rays with eight convex prisms. Each prism has eight clipping planes; the nearest hit owns the pixel. Face normals produce directional shading and specular light, and local coordinates identify narrow bevels. Slow tilt and hinge movement reveal overlapping facets and the central opening. Bass adjusts the hub spacing, mids articulate the hinges, spectral bands adjust individual prism length, air picks out bevels and hits select a few faces. There is no stack of extra luminous rings.

Galaxy evaluates three inclined star sheets with different cell scales and parallax. Three principal arms have secondary branches; dust breaks their continuity and the sheets have different band roles. Nearby-cell evaluation bounds the work to 27 star candidates per pixel. The central bulge has a dark crossing lane and a compact highlight; a hit lights selected star clusters instead of drawing a whole orbital ring. Short per-output feedback remains available.

Rain retains the existing glyph alphabet, adds a third depth and groups five neighboring columns under a shared head phase. A slow wave front organizes the field. Band energy opens eligible lanes and extends their tails; hits briefly reveal streams near the current crest. Bass displaces the field by a small depth-dependent amount, and air selects sparse glyphs. Quiet passages retain designed gaps instead of filling the frame.

Plasma becomes flowing glass. Three continuous shear steps warp the domain, then five ribbons overlap with curved cross-section shading, thin pale edges and internal filaments. This is an analytic advection-like construction, not a fluid simulation. Bass changes ribbon tension, mids change shear, air reveals surface lines and hits catch a short portion of an edge. The dark gaps and overlap distinguish it from Feedback Bloom.

## Run the accepted scenes

```sh
scripts/build.sh
open build/Phosphor.app
```

The normal bundle remains `com.mrbrooks.phosphor` with its existing preferences and ordinary Phosphor branding. Finder launch opens the desk with capture stopped. No saved desk is replaced or migrated.

The separate review app remains available with the same accepted scenes:

```sh
scripts/build.sh release --v2-development
open 'build/Phosphor V2.app'
```

The bundle identifier is `com.mrbrooks.phosphor.v2-ae8b`. It has separate preferences and clear V2 labeling. Finder launch opens the desk with capture stopped. Use the existing capture controls. The explicit command below seeds the five V2 output configurations only when this development app has no saved desk, opens them and starts the real Music tap. It never changes Music playback or audio routing:

```sh
'build/Phosphor V2.app/Contents/MacOS/Phosphor' --stage-v2 --capture-music --diagnostics
```

Do not start a second copy of the V2 app while it is already running. Production Phosphor can remain open. Normal `scripts/build.sh` selects the accepted V2 fields. The review app differs only in labeling, bundle identity and preferences. One renderer, uniform layout and packaged shader source support the accepted fields plus an explicitly selected V1 comparison baseline through a Metal compilation macro. No production preference schema changes are needed.

The synthetic gallery is an explicit separate launch mode. It disables capture and saves, labels the desk and windows, and never becomes a fallback when real capture is silent:

```sh
'build/Phosphor V2.app/Contents/MacOS/Phosphor' --scene-gallery
```

## Matched visual evidence

```sh
'build/Phosphor V2.app/Contents/MacOS/Phosphor' --validate-resources
'build/Phosphor V2.app/Contents/MacOS/Phosphor' --validate-scenes build/v2-previews
'build/Phosphor V2.app/Contents/MacOS/Phosphor' --export-motion build/v2-motion
```

The motion exporter compiles baseline and V2 separately and uses one shared offscreen fixture encoder. Each labeled pair shares clock, inputs, phase, palette, size and settings. The 10-second sequence moves through silence, quiet, loud/hits and release. Feedback is retained within each clip. It resets between scenes and at the loop boundary. GIFs show motion; four lossless PNG pairs per scene show the rendered exposure without GIF quantization. This evidence is deterministic and synthetic. It cannot establish musical feel, capture reliability or smooth native presentation. The runtime does not read these files.

The existing resource and pixel checker still runs all eight scenes, the Scope trace, isolated bands/hits, palette/time/phase changes, zero and half Intensity, and zero/strong Reactivity. It checks finite nonnegative fields, exposure linearity and response beyond an exposure-only change at 640×360, 1080p, landscape 4K and portrait 4K. Native checks need macOS and Metal; there is no containerizable service or supporting server.

## Initial isolated-preview validation — November 3, 2026

The inspected machine is Apple M3 Ultra / 96 GB / macOS 27.0.1. Release builds of the ordinary app and the separate V2 bundle pass. V2's packaged resource/pipeline validation and strict ad-hoc signature verification pass. The 11 existing CoreChecks pass with zero failures. The final V2 checker completes for all eight scenes and all four sizes; [raw GPU and pixel-check output](V2_GPU_CHECKS.txt) records the checks. Before promotion, the ordinary build's 24 exported PNGs were byte-identical to the untouched V1 baseline, including both 4K orientations. That checked preview isolation at that checkpoint; the normal build now intentionally selects V2.

Final warm offscreen 3840×2160 medians are 0.560 ms Outrun, 1.879 ms Crystal, 4.728 ms Galaxy, 0.547 ms Rain and 0.657 ms Plasma (10 warm samples each). These commands include the feedback clear, scene and presentation passes. The final timing run took place after the other GPU validation process and this task's native preview were stopped. The bounds are fixed: eight eight-plane prism intersections for Crystal and 27 nearby star candidates for Galaxy. There is no per-frame particle allocation, global feedback or unbounded ray march. Galaxy is materially more expensive than the delivered version; these measurements do not establish simultaneous multi-4K capacity or smooth presentation.

The implementation preview captured actual Apple Music-only stereo at 48 kHz with all five V2 independent outputs open. There were 173 one-second diagnostic entries explicitly reporting live samples. Their sampled RMS ranged 0.0057–0.1860, bass 0.0037–0.9833, mids 0.0438–0.7477, air 0.0009–0.4296 and hit 0.0204–0.9079, with zero reported queue drops. The desk showed zero history gaps. Input later ceased without this task controlling Music, and the status changed to the existing active-but-unverified-silence message while envelopes settled to zero. This is real capture and release observation, not a controlled track-selection or end-to-end latency test. Numeric logs are local in `build/v2-live.log`; no audio was recorded.

Native inspection covered all five V2 fields, a Crystal Ice palette change, unchanged other output settings, Galaxy's Coordinated inheritance, actual Outrun texture mirroring in the Galaxy window, restoration to Independent/Galaxy/Ice, switching Crystal through the delivered Bloom and Tunnel and back, and Rain fullscreen/Escape. Outrun was also switched through half-resolution, native pixels and balanced quality, then restored to balanced. Scope was inspected in the baseline synthetic gallery, which correctly has no invented waveform. The separate fixture checker executes its actual trace pipeline with explicit test points. All eight compositions were inspected before or during development; the final terrain and differential-orbit refinements were inspected natively after relaunch and are represented in the regenerated final GPU fixtures. The portrait fixture caught a cropped Outrun source; its framing was corrected and the full native checker and motion exports were regenerated. The final app was left with capture stopped, and its scene settings retained the balanced review defaults.

Native presentation counters during overlap, focus changes and controls ranged from low single digits into the 20–30 fps range, with occasional higher readings. These are not steady visible frame-rate measurements. First-run permission grant/deny, route changes, older non-Apple managed-texture GPUs, arbitrary drag resizing, sustained multi-display pacing/RSS, latency and broad musical-feel acceptance across varied tracks remain open. The known main-branch capture-startup limitation also remains; this preview does not include the separate capture-startup branch. The owner separately authorized merging this direction after trying it; these checks do not establish a notarized release or retire the listed measurement limits.

Final local artifacts are `build/Phosphor V2.app`, `build/v2-previews-final/` (24 PNGs plus raw checks), and `build/v2-motion-final/` (five labeled GIFs, twenty matched PNG pairs and the fixture manifest). Build artifacts remain untracked and reproducible. The app is a local ad-hoc-signed development build, not a notarized release. CodeRabbit's complete-diff review record belongs in the PR so that it can name the immutable reviewed head without changing that head.

## Production-default promotion — November 3, 2026

After the owner tried all five scenes with live Apple Music, they authorized making V2 the main version and merging PR #6. Normal live rendering and the native checker now use the same default V2 compilation path. The review-bundle flag controls only its label; the old fields require an explicit V1 comparison request. The standard bundle keeps its existing identity and preferences, and the shader geometry is unchanged from the accepted preview.

The normal release build, packaged Metal resource/pipeline check, strict ad-hoc signature verification and all 11 CoreChecks pass. All eight scenes pass the existing native checks at 640×360, 1080p, landscape 4K and portrait 4K. The ordinary app's 24 exported PNGs are byte-identical to the accepted final V2 fixtures, directly exercising the promoted default rather than inferring it from a successful build. Its Info.plist retains `com.mrbrooks.phosphor` / `Phosphor` and has no development flag. The running V2 tryout was left intact. Review evidence for the final integration head is recorded in PR #6.
