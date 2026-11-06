# Lessons learned

What a short real-AirPods test taught us. Nothing here is a benchmark: it is one person, one pair of AirPods, one afternoon.

## Motion source
- Only the public `CMHeadphoneMotionManager` is used. Data arrives only while the AirPods are worn.
- The stream ran at 50 Hz (301 samples in 6 s, 751 in 15 s).
- Pitch sat frozen near -1.1 rad before the first movement of each take. Subtract a baseline instead of trusting absolute angles.
- Euler angles can mix axes depending on how the AirPods fit the ear: in a nod-only take, yaw and roll moved as much as pitch.

## Classifier
- Default thresholds: nod 0.25 rad pitch, shake 0.35 rad yaw, tilt 0.25 rad roll, in a 0.6 s window.
- They missed natural nods. In a 45 s free take the classifier fired 3 shakes, 0 nods and 0 tilts. A natural tilt reached only about 0.14 rad of roll.
- Synthetic fixtures pass every test, but that proves the code works, not that gestures work on a head.

## Untried ideas
- Per-user calibration of thresholds from a recorded session.
- Waveform matching (for example template or DTW matching) instead of range thresholds.
- Expressing motion in a head frame, using the resting attitude as the reference.
