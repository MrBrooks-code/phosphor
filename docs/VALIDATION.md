# Prototype validation — November 1, 2026

This is a working validation record. CodeRabbit status and final release measurements are recorded in the draft PR after the current head is reviewed.

## Environment

The inspected native machine is a Mac Studio with Apple M3 Ultra (60 GPU cores), 96 GB RAM and macOS 27.0.1. Swift 6.4 Command Line Tools are installed; full Xcode and XCTest are not. The native app reports four attached displays: LC32G7xT, BenQ GW2790T, LS32AG32x and U32J59x. Display enumeration inside the command sandbox alone did not expose the same WindowServer inventory; the launched app is the relevant evidence.

## Capture evidence

An Apple Music-only tap selecting `com.apple.Music` delivered real changing Float32 stereo at 48 kHz. During the initial run, about 6 million frames arrived with zero queue drops and no detected history gaps. Representative playing values included RMS 0.04–0.32 and changing independent bass/mid/high features. The current Music UI showed station playback, including “Lowrider” by chromagen & MIRAGE, with “Add to Library” and “Share Station” context actions. This is observed Apple Music station/catalog playback, not a local test file. No file/protection metadata was available in its File information pane; this does not establish DRM compatibility for all subscription content.

Pausing via Music's actual playback control changed it to Play and drove captured peak to zero, then RMS below 0.00002. Resuming restored live nonzero samples and band changes. Phosphor did not change the system output, install a driver or supply demo audio. A permission prompt was not observed in this run; the app still includes the usage description, retry flow and honest silence status. First-run grant/deny and recovery on a clean permission state remain owner checks. No audio recording was saved.

Synthetic tone data is used only in the core contract checks. Local audio-file playback through Music has not been tested separately. System-mix capture and output-device changes are separate checks from the proven Music-only path.

## Automated checks

`swift run CoreChecks` completed seven contract checks with zero failures. They exercise queue wrap and overflow reporting; chronological stereo history and timestamp retention; resetting history on a sequence gap; anti-phase stereo FFT energy; bass/treble separation; deliberate silence release; independent/mirrored/coordinated parameter behavior; saved-document round trips and invalid-version/duplicate-ID/range rejection; and 4K resolution-cap selection.

`swift test` was attempted first but cannot resolve XCTest on this Command Line Tools installation. The standalone check executable replaces that dependency; it does not turn a failed test invocation into a pass. Native APIs prevent these particular checks from running in a Linux container. No supporting service is used.

## Native behavior inspected so far

The app launches as an ad-hoc signed `.app`. Runtime Metal compilation was actually exercised: the first launch exposed a reserved shader parameter name, which was fixed. Scope displayed a live stereo trace and spectrum. Bloom displayed feedback ribbons and rotating filaments, then entered chrome-free fullscreen on the selected U32J59x output; Escape returned to its window. Two independent windows rendered against common Music audio. The fullscreen screenshot was portrait 2160 × 3840, consistent with the display's current rotation. This is real display assignment/fullscreen evidence, not proof of broad multi-monitor performance or synchronization.

The debug control desk showed roughly 44–60 submitted fps during active UI inspection, with about 0.1 ms GPU command duration for a windowed scope. These are short debug observations, not steady-state release benchmarks. No end-to-end latency, hardware frame lock, sustained multi-4K performance, or analog CRT compatibility is claimed.

## Remaining acceptance

Finish release-native checks for all three scenes, mirror/coordinate roles, resize/reassignment/close/reopen, and parameter persistence. Record final measured timing with its conditions. Owner acceptance still includes visual taste, motion comfort, sustained direct-output performance, clean-permission behavior, device hotplug/route changes, and any future physical vintage display path. A successful build is not proof of these behaviors.
