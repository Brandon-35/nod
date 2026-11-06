# Nod for Mac

Control your Mac with head gestures while wearing AirPods: nod, shake, tilt left, tilt right. Each gesture maps to an action: dismiss or snooze a notification, play/pause, next or previous track, answer or decline a FaceTime call, press any shortcut key, or run a Shortcut.

> **Status: experimental, no longer developed as a product.** The app builds and its tests pass, but gesture accuracy has only been tried briefly on one real head and needs tuning (see "Known limits"). It is published as open source for anyone who wants to learn from it or take it further.

## How it works

- Head motion comes from the public `CMHeadphoneMotionManager` API. Data only arrives while the AirPods are worn. No private Bluetooth APIs.
- `NodCore` is the pure logic (no AppKit): motion samples, a sliding-window gesture classifier, a listening gate, calibration, settings, and the action dispatcher. Everything testable without AirPods lives here.
- `Nod` is the menu bar app (SwiftUI + AppKit): status item, onboarding, settings, toasts, and the real system backends (media keys, Accessibility, Shortcuts CLI).
- No account, no telemetry, no network access. Settings are a local JSON file in `~/Library/Application Support/Nod/`.

## Build and run

Requirements: macOS 14+, Apple Silicon, Swift 6 toolchain (Xcode or Command Line Tools), AirPods with motion sensors (AirPods Pro, 3rd generation, Max).

```sh
scripts/test.sh        # unit tests on synthetic and recorded motion (no AirPods needed)
scripts/bundle.sh      # builds dist/Nod.app (ad-hoc signed)
open dist/Nod.app
```

Grant **Motion & Fitness** and **Accessibility** to Nod when asked. The bundle must be a `.app` with `NSMotionUsageDescription`; a bare binary aborts in the permission check. Ad-hoc signing changes the code hash on every rebuild, so macOS forgets both grants after each rebuild. Set `NOD_SIGN_IDENTITY` to a real codesign identity to avoid that.

Useful commands (run the app through `open`, not directly):

```sh
open -n -W --stdout out.txt dist/Nod.app --args --simulate        # whole chain on fake motion
open -n -W --stdout out.txt dist/Nod.app --args --record nod 15   # record 15 s of real motion to a JSONL fixture
NOD_SIMULATED_ONLY=1 open dist/Nod.app                            # run without AirPods or permissions
scripts/smoke.sh                                                  # end-to-end smoke test
```

## Known limits

See [docs/LESSONS.md](docs/LESSONS.md) for what the live tests showed.

- Live tests on real AirPods showed the sensor streams at 50 Hz, but the default thresholds (nod: 0.25 rad pitch, shake: 0.35 rad yaw, tilt: 0.25 rad roll, all within 0.6 s) were hard to reach with a natural nod, and nods were not recognised reliably. Calibration and sensitivity settings exist but are unproven.
- Euler angles from the headphone reference frame may mix axes depending on how the AirPods sit; a head-frame transform has not been tried.
- Media actions run only while a notification is visible or audio is playing, unless the listening mode is "Always".
- Button titles for notification and FaceTime actions are matched in English only.
- Nothing here was verified across AirPods models or macOS versions.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Recorded motion fixtures from real heads (`--record`) are the most useful contribution.

## License

[MIT](LICENSE)
