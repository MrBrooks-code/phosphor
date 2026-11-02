# Phosphor

**Sound takes shape.**

Phosphor is a native macOS music visualizer built with SwiftUI, AppKit, Core Audio process taps, and Metal. The prototype includes eight live GPU scenes and a separate control desk for multiple presentation outputs.

- **Phosphor Scope** draws the actual stereo X/Y trace with phosphor persistence and a logarithmic spectrum.
- **Feedback Bloom** feeds its previous image through rotation, flow and decay. Bass changes its shape, mids drive its ribbons, upper frequencies add filaments, and transients light the center.
- **Vector Tunnel** uses perspective rings, a moving vanishing point, treble spokes and rhythmic accents.

- **Outrun Horizon** places a striped sun above mountain silhouettes, a frequency skyline, and an advancing perspective grid.
- **Crystal Mandala** builds three counter-rotating faceted crowns with separate bass, mid, and air detail.
- **Spiral Galaxy** lights four particle arms around a breathing core, with short controlled trails.
- **Digital Rain** drops procedural glyph streams through two depth layers, with bright heads and spectrum-mapped columns.
- **Plasma Drift** blends five moving energy sources into calm colored fields and luminous contours.

See [scene notes and preview checks](docs/SCENES.md) for the artistic choices, reference sources, and validation limits.

## Build and run

Use a Mac with Metal and Swift 6 Command Line Tools or Xcode with the macOS 26 SDK or later. System-mix capture requires macOS 14.2 or later; Apple Music-only selection uses the bundle-ID tap API in macOS 26 or later. The inspected build machine runs macOS 27.0.1 on Apple M3 Ultra.

```sh
scripts/build.sh
open build/Phosphor.app
```

The script builds a release executable, bundles the shader resource and usage description, and applies an **ad-hoc local signature**. This is a local prototype, not a notarized release. No package dependencies or virtual audio drivers are required. Native audio, windowing, Metal, and the Core Audio/Accelerate contract checks run on macOS. There is no supporting service or web component to run in Docker.

For the narrow automated checks:

```sh
swift run CoreChecks
swift run CaptureChecks
```

The capture checks inject native failures and verify resource ownership, cleanup order, and recovery from incomplete cleanup. These run without XCTest, which is absent from the inspected Command Line Tools installation. They test queue overflow/wrap, timestamped stereo history, anti-phase spectral energy, frequency separation, silence release, output independence/roles, saved-state validation, and resolution caps. A build or these synthetic checks does not prove Apple Music capture or physical display behavior; see [validation notes](docs/VALIDATION.md).

## Use the control desk

Start Music playback, choose **Apple Music only** or **System mix**, and press **Start capture**. Grant System Audio Recording if macOS requests it. If capture remains silent, inspect System Settings → Privacy & Security → Screen & System Audio Recording, allow Phosphor, relaunch if macOS requires it, and retry. The app reports live samples separately from an active but silent tap. It does not infer that silence means permission was granted or protected audio was captured.

The tap is private and unmuted. It does not change your default output, install a driver, or reroute playback. Samples remain in a short in-memory history; Phosphor does not persist recordings or upload audio. Protected content may still be unavailable on other tracks, devices, or OS versions.

Each output card has a scene, palette, intensity, persistence, display, quality and role. **Open** creates its window; **Fullscreen** presents without controls; **Escape** leaves fullscreen. **Close** keeps the saved configuration, while the trash button removes it. Use **Window → Control desk** (⇧⌘D) to return to the controls. A display change while fullscreen is saved and applied when fullscreen ends. Unavailable screens fall back to the operator display.

The first output is the leader. **Independent** outputs keep their own scene state and settings. **Mirrored** outputs sample the leader's rendered image, including feedback; their source render quality comes from the leader. Aspect ratio is preserved with black bars when needed. Closing the leader also closes its mirrors. **Coordinated** outputs share the leader's palette/intensity plus common audio and clock, while keeping their own scene, phase, persistence and quality. Each display presents on its own refresh clock; this is not hardware frame lock.

The default quality caps the longest rendered dimension at 1920 pixels. Half resolution and native pixels are also available. Resizing or changing render resolution clears feedback textures; scene settings survive. Desk parameters use a validated, versioned local preferences document. Window placement/fullscreen state and audio permission are not saved as scene parameters. Capture never starts automatically during a normal launch.

For an explicit diagnostic launch with two configured windows and Music capture:

```sh
build/Phosphor.app/Contents/MacOS/Phosphor --stage-outputs --capture-music --diagnostics
```

Quit any existing Phosphor instance before this diagnostic launch; direct executable launches can create duplicates. Quit waits for capture teardown before exiting. This prints native capture operation durations, setup/first-frame/first-signal times, numeric audio features and renderer timing, not raw samples. It is an opt-in diagnostic command; normal launches use captured audio only. The explicit scene gallery below uses labeled synthetic features.

Read [implementation notes](docs/IMPLEMENTATION.md) to add a shader scene or understand capture, timing and saved state. The Windows [Llamascope reference](https://github.com/MrBrooks-code/llamascope) is a separate repository and remains unchanged. Physical vintage display conversion has not been tested.

To verify a copied app's bundled shader and all Metal pipelines without starting capture or opening output windows:

```sh
build/Phosphor.app/Contents/MacOS/Phosphor --validate-resources
```


To build an isolated scene gallery beside the regular app:

```sh
scripts/build.sh release --scene-development
open "build/Phosphor Scenes.app"
```

This development artifact uses its own bundle ID and preferences. It opens all five new scenes with **labeled synthetic features**, disables capture, and does not save gallery changes. It does not replace or stop a running Phosphor. The normal build keeps the existing capture and saved-desk behavior. You can also opt into the temporary gallery with `--scene-gallery` on the normal executable.

To exercise the actual packaged Metal shaders and export repeatable synthetic previews:

```sh
"build/Phosphor Scenes.app/Contents/MacOS/Phosphor" --validate-scenes "$PWD/build/scene-previews"
```

This checks finite pixels, response to isolated bands, palettes and zero intensity, exports landscape and portrait PNGs, and measures bounded offscreen GPU work at windowed, 1080p and 4K sizes. It does not establish capture correctness, display pacing, or musical feel.
