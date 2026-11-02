# Native prototype implementation

## Data flow

`AudioCapture` owns a private, unmuted `CATapDescription`, a private aggregate device containing that tap, and a C IOProc. Music-only mode selects `com.apple.Music` by bundle ID and enables process restore on macOS 26+. System mix uses a stereo global tap. No system output property is changed. Stop/error paths destroy the IOProc, aggregate and tap in that order. Capture startup runs off the main thread because HAL and permission work can block.

`AudioIngress.c` is a single-writer/single-reader queue with 65,536 preallocated frames. Its callback accepts validated Float32 stereo, handles interleaved and planar buffers, sanitizes non-finite samples, and copies host timestamps and a sequence number. It allocates no memory and takes no locks. Acquire/release indices publish samples to the analysis worker. Full queues drop new frames, count them, and leave a sequence gap. The worker drains up to 8192 frames per tick. Capture and analysis share a serial lifecycle queue so teardown cannot race analysis.

`SampleHistory` preserves 96,000 ordered stereo frames and their per-frame host timestamps. A sequence gap clears the usable history and increments a discontinuity counter. `AudioAnalyzer` reads the latest 2048 frames with a Hann window, performs a separate complex FFT for each channel using Accelerate, and combines channel **power**, so stereo anti-phase signals do not cancel. It supplies 64 logarithmic spectral bands, channel waveforms, stereo RMS, peak, bass (<180 Hz), mids (180–2400 Hz), highs (>2400 Hz), and positive RMS change as a transient envelope. Envelopes have about 18 ms attack and 220 ms release (120 ms for the transient). These are parameter values, not measured end-to-end latency. After capture data ages out, waveforms clear and envelopes decay.

The analysis timer is 8 ms; it publishes value snapshots behind a short `NSLock`. No render or UI work enters the capture callback. Swift array copy-on-write can allocate during snapshot publication; all real-time sample transport and FFT scratch buffers are reused. History contains only memory, and diagnostic printing is opt-in.

## Rendering and scene contract

`SceneRenderer` owns two floating-point feedback textures per independent/coordinated output, three reusable waveform/spectrum buffer slots, and a bounded three-command in-flight limit. All renderers use one Metal device. Independent renderers have separate command queues so presentation waits on one display do not queue ahead of work for another. Mirrors submit through their source renderer's queue, which orders source image writes before mirror reads. A mirror reads the leader's most recently submitted texture and performs only the presentation pass; it does not run a separate feedback simulation. Mirrors preserve the source aspect ratio with black bars. A stalled or obscured source may therefore yield an older image. Different window refreshes can still present different source frames.

Every frame receives `GPUUniforms`, the same shared audio feature snapshot source, 512 stereo points, 64 spectrum values, and the previous image. The CPU/Metal uniform layout is 64 bytes. `sceneFragment` handles background/feedback/geometry, and `presentFragment` tone maps the linear floating-point image. Scope segments are GPU-instanced quads rather than an all-segments loop at every display pixel. Three buffer slots prevent CPU writes into data still in use by the GPU.

A native `CAMetalDisplayLink` supplies available drawables on the main run loop. The app does not call blocking `nextDrawable` while servicing controls. The link requests up to 60 Hz, capped to the current screen's maximum rate, and refreshes when the window changes screens. Simulation uses the shared Core Animation target clock. Presentation callbacks measure nonzero reported presentation timestamps; hidden or occluded windows may report less than the submission rate. An active-presentation activity prevents App Nap while any output is open, while still allowing normal idle system sleep.

Time comes from one monotonic process clock. Tunnel travel integrates elapsed time and bass energy; it does not multiply the entire elapsed time by the current bass value. Feedback motion and decay use elapsed time. Elapsed steps are capped at 100 ms after stalls. Resizing, scene changes, palette changes and render-resolution changes clear feedback images. This avoids reading uninitialized textures or stretching old persistence across incompatible settings.

To add a scene:

1. Add a stable case to `Scene` in `OutputState.swift`. Saved cases use their string values, so renaming an existing case needs a migration.
2. Add its branch to `sceneFragment` in `Scenes.metal`. `Scene.shaderID` is the explicit dispatch contract; preserve existing IDs (0–2 for the original scenes). New IDs 3–7 name the five additional scenes. Enum order affects only picker order.
3. Use the shared inputs for distinct musical roles. Keep per-scene temporal state in the renderer/feedback image, outside the capture path.
4. Add parameters to `SceneSettings` with decoding defaults and a schema migration if older saves must survive. Validate their bounds in `SavedDesk.decode`, and expose a bounded control in `OutputCard`.
5. Build, launch, inspect the real shader, and exercise at least two simultaneous outputs. Swift compilation does not compile runtime Metal shader source.

There is deliberately no plugin runtime, node editor, network service, live shader loader or MilkDrop importer in this slice.

## Output and preferences ownership

`DeskModel` owns value-type `OutputState` entries; windows have a separate UUID-keyed lifetime map. An independent output cannot mutate another output's settings. Coordinated and mirror resolution happens without rewriting stored independent settings, so switching roles restores the output's own composition. The first configured output is the leader. Removing it promotes the next output and resets that output's role to independent. Closing the leader closes mirrors while retaining all configurations.

Parameters are saved as a JSON-encoded schema-version-1 `SavedDesk` in the application's preferences. Loading rejects unknown versions, duplicate output IDs, more than 16 outputs, and invalid intensity/persistence values. Screen IDs are stable Core Graphics display identifiers where macOS provides them. An unavailable screen retains its saved selection and the window falls back to the operator display. Reassignment does not recreate the renderer. Resolution changes do recreate feedback textures. The current prototype does not persist exact window frames or fullscreen state.

All app work is local. The build script performs local ad-hoc signing and does not install, publish, notarize or release the app.


## Additional scene fields

The five additional scene functions use the same 64-byte uniforms and per-output textures. Outrun has three interpolated mountain layers and an analytic perspective grid; Crystal has three faceted radial layers; Galaxy checks two layers of nine nearby polar cells rather than an unbounded particle list; Rain evaluates one glyph in each of two stream layers; Plasma sums five Gaussian sources. There are no per-frame spawns, new textures, new capture paths, or global mutable scene state. Radial scenes scale to the shorter window dimension so portrait windows keep circular geometry. Rain uses logical cells rather than screen pixels, so resizing does not stretch glyph proportions.

The existing analyzer supplies attack/release envelopes. Geometry responds to those bounded features; time does not get multiplied by the current band value. Outrun uses the existing integrated travel field. Galaxy uses the output's previous image only as a short decaying maximum, so highlights do not accumulate into a bright feedback field. Other new scenes redraw analytic geometry directly; persistence changes only Galaxy's trails among the five additions. The generic persistence control remains available for compatibility when switching scenes.

`SceneValidation` is an explicit synthetic fixture and offscreen GPU check, not an audio source. `--scene-gallery` overrides only the renderer feature snapshot and the meter display, opens five temporary configurations, disables capture, and bypasses saves. The optional development build sets this mode in its own Info.plist and uses a separate launch identity. Normal launch, capture, and saved preferences retain the prototype paths.
