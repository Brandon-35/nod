<div align="center">

# Nod for Mac

**Control your Mac with head gestures while wearing AirPods.**

Nod · Shake · Tilt left · Tilt right

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)
![Status: experimental](https://img.shields.io/badge/status-experimental-orange)

</div>

> [!WARNING]
> **Experimental, no longer developed as a product.** The app builds and its tests pass, but gesture accuracy was only tried briefly on one real head and needs tuning. See [docs/LESSONS.md](docs/LESSONS.md). It is published so others can learn from it or take it further.

## What it does

Each of the four head gestures runs one action you choose:

| Action | Example use |
|---|---|
| Dismiss or snooze a notification | Nod to clear a banner |
| Play / pause, next track, previous track | Tilt right for next track |
| Answer or decline a FaceTime call | Nod to answer |
| Press any shortcut key | Shake to send a hotkey |
| Run a Shortcut | Tilt left to run your own automation |

## How it works

- **Motion source:** the public `CMHeadphoneMotionManager` API. Data only arrives while the AirPods are worn. No private Bluetooth APIs.
- **`NodCore`:** pure logic with no AppKit: motion samples, a sliding-window gesture classifier, a listening gate, calibration, settings, and the action dispatcher. Everything here is testable without AirPods.
- **`Nod`:** the menu bar app (SwiftUI + AppKit): status item, onboarding, settings, toasts, and the real system backends (media keys, Accessibility, Shortcuts CLI).
- **Privacy:** no account, no telemetry, no network access. Settings are a local JSON file in `~/Library/Application Support/Nod/`.

## Build and run

**Requirements:** macOS 14+, Apple Silicon, a Swift 6 toolchain (Xcode or Command Line Tools), and AirPods with motion sensors (AirPods Pro, 3rd generation, Max).

```sh
scripts/test.sh        # unit tests on synthetic and recorded motion (no AirPods needed)
scripts/bundle.sh      # builds dist/Nod.app (ad-hoc signed)
open dist/Nod.app
```

Grant **Motion & Fitness** and **Accessibility** to Nod when asked.

> [!NOTE]
> The app must be a `.app` bundle with `NSMotionUsageDescription`; a bare binary aborts in the permission check. Ad-hoc signing changes the code hash on every rebuild, so macOS forgets both grants after each rebuild. Set `NOD_SIGN_IDENTITY` to a real codesign identity to avoid that.

### Useful commands

Run the app through `open`, not directly.

```sh
open -n -W --stdout out.txt dist/Nod.app --args --simulate        # whole chain on fake motion
open -n -W --stdout out.txt dist/Nod.app --args --record nod 15   # record 15 s of real motion to a JSONL fixture
NOD_SIMULATED_ONLY=1 open dist/Nod.app                            # run without AirPods or permissions
scripts/smoke.sh                                                  # end-to-end smoke test
```

## Known limits

Details in [docs/LESSONS.md](docs/LESSONS.md).

- The default thresholds (nod 0.25 rad pitch, shake 0.35 rad yaw, tilt 0.25 rad roll, within 0.6 s) were hard to reach with a natural nod, and nods were not recognised reliably. Calibration and sensitivity settings exist but are unproven.
- Euler angles from the headphone reference frame may mix axes depending on how the AirPods sit; a head-frame transform has not been tried.
- Media actions run only while a notification is visible or audio is playing, unless the listening mode is "Always".
- Button titles for notification and FaceTime actions are matched in English only.
- Nothing was verified across AirPods models or macOS versions.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Recordings of real head motion (`--record`) are the most useful contribution.

## License

[MIT](LICENSE) © 2026 Brandon Ta
