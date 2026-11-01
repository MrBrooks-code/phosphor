# Prototype validation — November 1, 2026

The draft PR records the exact reviewed head and CodeRabbit findings disposition. Passing compilation is separate from the native observations below.

## Environment

The inspected native machine is a Mac Studio with Apple M3 Ultra (60 GPU cores), 96 GB RAM and macOS 27.0.1. Swift 6.4 Command Line Tools are installed; full Xcode and XCTest are not. The native app reports four attached displays: LC32G7xT, BenQ GW2790T, LS32AG32x and U32J59x. Display enumeration inside the command sandbox alone did not expose the same WindowServer inventory; the launched app is the relevant evidence.

## Capture evidence

An Apple Music-only tap selecting `com.apple.Music` delivered real changing Float32 stereo at 48 kHz. During the initial run, about 6 million frames arrived with zero queue drops and no detected history gaps. Representative playing values included RMS 0.04–0.32 and changing independent bass/mid/high features. The current Music UI showed station playback, including “Lowrider” by chromagen & MIRAGE, with “Add to Library” and “Share Station” context actions. This is observed Apple Music station/catalog playback, not a local test file. No file/protection metadata was available in its File information pane; this does not establish DRM compatibility for all subscription content.

Pausing via Music's actual playback control changed it to Play and drove captured peak to zero, then RMS below 0.00002. Resuming restored live nonzero samples and band changes. Phosphor did not change the system output, install a driver or supply demo audio. A permission prompt was not observed in this run; the app still includes the usage description, retry flow and honest silence status. First-run grant/deny and recovery on a clean permission state remain owner checks. No audio recording was saved.

Synthetic tone data is used only in the core contract checks. Local audio-file playback through Music has not been tested separately. System-mix capture and output-device changes are separate checks from the proven Music-only path.

## Automated checks

`swift run CoreChecks` completed seven contract checks with zero failures. They exercise queue wrap and overflow reporting; chronological stereo history and timestamp retention; resetting history on a sequence gap; anti-phase stereo FFT energy; bass/treble separation; deliberate silence release; independent/mirrored/coordinated parameter behavior; saved-document round trips and invalid-version/duplicate-ID/range rejection; and 4K resolution-cap selection.

`swift test` was attempted first but cannot resolve XCTest on this Command Line Tools installation. The standalone check executable replaces that dependency; it does not turn a failed test invocation into a pass. Native APIs prevent these particular checks from running in a Linux container. No supporting service is used.

## Native behavior

The app launches as an ad-hoc signed `.app`. Runtime Metal compilation was actually exercised: the first launch exposed a reserved shader parameter name, which was fixed. Scope displayed a live stereo trace and spectrum. Bloom displayed feedback ribbons and rotating filaments, then entered chrome-free fullscreen on the selected U32J59x output; Escape returned to its window. Two independent windows rendered against common Music audio. The fullscreen screenshot was portrait 2160 × 3840, consistent with the display's current rotation. This is real display assignment/fullscreen evidence, not proof of broad multi-monitor performance or synchronization.

Display modes were read through native system_profiler: LC32G7xT 2560 × 1440 at 120 Hz (main), BenQ GW2790T 1920 × 1080 at 100 Hz, LS32AG32x 1920 × 1080 at 144 Hz, and portrait U32J59x 2160 × 3840 at **30 Hz**. The app did not change these modes. The 4K display cannot show 60 unique frames per second in its current mode.

The final release also passed the actual Music-only sample check after a capture retry: over 4.5 million 48 kHz frames were observed with changing levels/bands and zero queue drops or history gaps. Before that retry, Core Audio blocked while creating the IOProc and then returned status **268451843** at Start capture. System Settings showed Phosphor's System Audio Recording Only permission **on**. Pressing Start capture again on the same build immediately restored usable samples. No permission toggle, driver install, route change, service restart or replacement audio was used. This intermittent startup failure remains a native robustness limitation; it is not diagnosed as a permission denial. The UI reports the pending operation/error and exposes retry after the OS call returns. The native call cannot be cancelled while it is blocked.

Native role checks exercised a mirrored window showing the leader's tunnel, closing the leader and observing both windows close, then reopening the second output in coordinated mode and observing its Bloom composition with the leader's ultraviolet palette. The stored scene/palette remained available when changing roles. Scene, palette, intensity, persistence, quality and display selections survived actual app restarts. The control-desk shortcut worked. Reassignment, close/open and fullscreen were exercised; arbitrary live resizing, unplug/replug recovery and fullscreen reassignment deferral were not fully accepted.

Initial debug/submission counters varied about 44–60 fps for a windowed scope, and the first drawable-driven loop reported near 60 presentations on the 1080p output while the 4K output tracked its 30 Hz mode. Final instrumentation uses nonzero `CAMetalDrawable.presentedTime` callbacks instead of submission counts. During automated inspection it reported highly variable rates, including low single digits, despite short GPU durations (usually about 0.03–0.3 ms, with occasional larger samples). Window visibility, active Spaces and concurrent operator interaction changed during these observations. **Steady 60 fps has not been established, and the low presentation rates must not be reported as a pass.** GPU duration alone does not measure pacing or visible motion. A controlled, unobstructed physical-display run and owner motion assessment remain required. No end-to-end latency or sustained multi-4K claim is made.

## Packaging and shader verification

Release `scripts/build.sh` completed and `codesign --verify --deep --strict build/Phosphor.app` passed. A copy of the `.app` under a temporary directory ran `--validate-resources` with the entire `.build` directory temporarily hidden. It loaded the bundled shader and compiled all Metal pipelines successfully, then `.build` was restored. This checks the portable bundle path rather than relying on an absolute build-directory fallback. The signature is ad-hoc; notarization, distribution signing and release publication were not performed.

The first CodeRabbit CLI review completed against commit `028fbc2427b3009fa51dfd35bd47d4a9d50f3dd4`, base `90a4739efcede7d738f6415ab41a2dec5844275c`, covering the full 16-file committed diff. It reported one major and five minor findings, including duplicate default/error comments. The follow-up changes explicitly load packaged resources and add the copied-artifact probe, document the macOS 26+ build SDK, select system mix by default before macOS 26, distinguish unsupported conditions from OSStatus errors, and replace descending smoothstep calls with defined ascending complements. The final PR records the follow-up review's completion and scope; this first review does not by itself cover later commits.

## Remaining owner acceptance

The prototype is launchable and demonstrates real Apple Music audio, three GPU scenes and independent presentation windows. Owner acceptance still includes visual taste, motion comfort, controlled sustained presentation performance, intermittent capture-start robustness, clean-permission grant/deny recovery, output-device/route changes, physical hotplug, and any future vintage display conversion. Local Music files and broad protected-content compatibility were not tested. The app does not claim hardware frame lock or analog CRT compatibility.
