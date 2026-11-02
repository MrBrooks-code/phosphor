# Music-driven response

Reactivity is a per-output 0–2 control. Zero keeps calm composition and idle motion; 1 is the balanced default; 2 gives stronger deformation and local accents. Features saturate at 1.5 after scaling, so stronger settings remain bounded. Scope retains 35% of its actual stereo trace excursion at zero. Intensity remains 0–2 brightness/exposure. There is no whole-frame audio gain. Existing version-1 desks decode missing Reactivity as 1 and preserve their other values. Explicit null and out-of-range values fail loading. Independent settings remain isolated; coordinated outputs share leader Reactivity with Intensity and palette; mirrors read the leader's rendered texture.

## Analysis and gestures

The analyzer combines stereo channel power and leaves raw RMS/peak unnormalized. An RMS gate ramps from 0.0008 to 0.003 (about −62 to −50 dBFS). Only active input trains the 3-second upward / 8-second downward level reference. A square-root sensitivity adjustment stays between 0.75 and 3, so quiet passages gain detail without learning from silence. Bass/mid/high attack is 18 ms, with releases of 180/220/130 ms. Spectral detail releases over 160 ms. These are filter constants, not end-to-end latency measurements.

Hits combine positive spectral change and positive RMS change. A 400 ms spectral-change reference rejects the routine changes in a dense sustained passage. The hit envelope attacks in 6 ms and releases in 90 ms. Startup and sequence gaps prime one full FFT window before hits can fire; stale capture clears usable history and resets sensitivity/onset history while envelopes release. New capture sessions get a new analyzer. No sample callback, allocation/locking contract, or capture ownership code changed.

Outrun keeps its horizon, sun, mountains and negative space while bass changes terrain perspective, travel and skyline height, hits accent grid/windows, and highs light stars. Crystal's three crowns expand with their respective bands and light facet edges on hits. Galaxy uses radial breathing, core expansion, arm deformation and an orbital accent with slower idle rotation. Rain keeps its legible glyphs and two depths, adding bass displacement/tail length, hit clusters of adjacent columns, and treble sparkle. Plasma has slower idle flow, stronger source spread/warp/contour shaping, and a quickly released local boundary accent. Scope, Bloom and Tunnel use the same bounded Reactivity; their compositions and shader IDs remain stable.

## Primary preview: actual audio

The launchable local app is:

`build/Phosphor Response.app`

Build and opt-in diagnostic launch:

```sh
scripts/build.sh release --response-development
"build/Phosphor Response.app/Contents/MacOS/Phosphor" --stage-response --capture-music --diagnostics
```

The bundle ID is `com.mrbrooks.phosphor.response-2d5d`, with isolated preferences and no `PhosphorSyntheticGallery` flag. `--stage-response` seeds five scene configurations only without a saved desk, then opens configured outputs. It does not supply features. The real tap is the sole audio source. Finder launch opens the desk with capture stopped; use Start capture. A failed or silent tap never falls back to synthetic animation. The de8f `Phosphor Scenes.app` remains an explicitly synthetic gallery and is not the primary preview.

On November 1, 2026, the final response artifact captured changing Apple Music-only Float32 stereo at 48 kHz while all five new independent outputs were open. At the recorded checkpoint, 80 one-second diagnostic samples reached 4,374,016 frames, with zero queue drops; the desk also reported zero history gaps. Sampled RMS ranged 0.0117–0.1362, bass 0.0117–0.9894, mids 0.0483–0.3248, air 0.0018–0.3330, and hits 0.0271–0.9587. These are sampled ranges, not beat accuracy or latency measurements. Logs contain numeric features and renderer timings, never raw audio. They are in `build/live-response-final.log`. The earlier implementation checkpoint accumulated over 30 million frames; it informed the spectral-reference correction and is superseded for calibration by the final run.

Native inspection observed changing meters and real scene images, exercised Reactivity changes, coordinated inheritance, a true mirrored Outrun image in the Crystal window, restoration to Independent, an Ice palette change, half-resolution selection, a Crystal-to-Plasma switch and return, and native zoom/unzoom resizing from a 960×540 window to 2560×1336. The same source keeps all eight selectors and role behavior. Control values survived the development-app relaunch. Screenshots in the implementation chat show actual live windows; PNG fixtures below are synthetic. Music playback, the running capture-worktree app, its files, and the old gallery app were not changed or quit. Only this task's preview was stopped and quit for rebuilding.

The first live spectral detector stayed too active during dense music. The final recent-change reference was added in response to that actual input, and its live hit values now include both low between-event levels and strong accents. This is useful calibration evidence, not owner acceptance of musical feel across a track library.

## Focused checks and measurements

`swift run CoreChecks` passes 11 checks with zero failures. Added cases exercise old-desk migration without changing other values, invalid/null/non-finite values, role resolution and restoration, low-level tone and pseudonoise gating, gradual sensitivity adaptation, a spectral onset under nearly constant RMS, sustained-tone rejection, release, startup/gap priming, bounded feature ranges, elapsed-time release and frame-rate-independent bounded travel. Native macOS Accelerate/Core Audio require these checks on the Mac; no supporting service is needed. Sandbox module-cache restrictions required approved native execution with the installed toolchain; the subsequent checks passed.

The release build, strict ad-hoc signature check, and packaged Metal pipeline check pass. The final `--validate-scenes` runner executes all eight fields plus Scope's actual instanced trace pipeline. It checks finite nonnegative pixels, isolated bass/mid/high/hit fixtures, four palettes, time/phase, zero and half Intensity, and zero/strong Reactivity. A fitted scalar exposure cannot explain the Reactivity change. At a fixed clock, zero Reactivity makes the seven analytic fields identical for audio and silence. Scope deliberately retains the actual trace. Intensity halves linear RGB within half-float tolerance; zero Intensity produces black. Feedback is cleared per fixture, so this does not test long accumulated trails.

Synthetic fixture outputs are under `build/response-previews-final/`: 24 PNGs cover all eight scenes at 1080p, landscape 4K and portrait 4K. [RESPONSE_GPU_CHECKS.txt](RESPONSE_GPU_CHECKS.txt) records the full checks and timings on Apple M3 Ultra / macOS 27.0.1. Ten warm offscreen 3840×2160 command medians were 0.248 ms Scope, 0.247 ms Bloom, 0.523 ms Tunnel, 0.372 ms Outrun, 0.501 ms Crystal, 2.262 ms Galaxy, 0.396 ms Rain, and 0.231 ms Plasma. The 640×360 fixtures have 14 warm samples; other sizes have 10. Commands include the input clear, scene and presentation passes, and Scope trace where applicable. This is a short single-scene GPU workload, not display pacing or simultaneous multi-4K evidence.

During final live window overlap, focus, resizing and control changes, diagnostic presentation counters ranged 0–55 fps, including low single digits. GPU work was usually short; it does not prove smooth visible presentation. Steady 60 fps, controlled simultaneous multi-display/multi-4K pacing, sustained RSS, end-to-end latency, first-run grant/deny, route changes, older non-Apple managed-texture hardware, arbitrary corner-drag resizing and owner musical-feel acceptance remain unverified. Silence/release and clean restart behavior are exercised by deterministic sample fixtures; this task did not pause or resume Music to create a controlled live silence trial.

Capture PR #4 remains a separate unmerged draft at `c1d3a42c0a7b70aef00a16b778d0924e0819901c`. This app uses merged main's capture implementation, not that branch's ownership/startup fixes. Both response-preview starts delivered samples, but that does not retire the known main-branch startup limitation. No merge, release, notarization or broad protected-content claim is made.
