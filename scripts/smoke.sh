#!/bin/bash
# Smoke test, no AirPods needed: (1) the whole gesture chain through `Nod --simulate` (fake motion, fake actions),
# (2) the menu bar app launches in NOD_SIMULATED_ONLY mode and stays up. The menu bar icon itself is not
# machine-checked. Usage: scripts/smoke.sh
set -euo pipefail
cd "$(dirname "$0")/.."
NOD_CONFIG=debug scripts/bundle.sh 0.0.0 >/dev/null

OUT="$(mktemp)"
trap '/bin/rm -f "$OUT"' EXIT
# Through `open`: a bare binary aborts in the Motion permission check.
open -n -W --stdout "$OUT" --stderr "$OUT" dist/Nod.app --args --simulate
grep -q "simulate: actions dismiss,nextTrack,playPause" "$OUT" || { echo "smoke: simulate failed:" >&2; cat "$OUT" >&2; exit 1; }
echo "smoke: simulate ok"

# Settings go to a temp dir, never the real ~/Library/Application Support/Nod. Seeded at the motion step, the simulated
# first-run flow walks motion > AirPods > calibration > assign on its own; the file records where it got to.
SETTINGS="$(mktemp -d)"
LOG="$(mktemp)"
trap '/bin/rm -f "$OUT" "$LOG"; /bin/rm -rf "$SETTINGS"' EXIT
echo '{"schemaVersion":1,"onboardingStep":1}' > "$SETTINGS/settings.json"
open -n --stderr "$LOG" --env NOD_SIMULATED_ONLY=1 --env NOD_SETTINGS_DIR="$SETTINGS" --env NOD_OPEN_SETTINGS=1 dist/Nod.app
for _ in $(seq 50); do pgrep -x Nod >/dev/null && break; sleep 0.1; done
pgrep -x Nod >/dev/null || { echo "smoke: Nod did not start" >&2; exit 1; }
sleep 7
pgrep -x Nod >/dev/null || { echo "smoke: Nod exited early" >&2; exit 1; }
grep -q '"onboardingStep" *: *4' "$SETTINGS/settings.json" || { echo "smoke: onboarding did not reach the assign step:" >&2; cat "$SETTINGS/settings.json" >&2; exit 1; }
grep -q '"calibration"' "$SETTINGS/settings.json" || { echo "smoke: simulated calibration was not saved" >&2; exit 1; }
echo "smoke: onboarding reached assign with a calibration profile"
pkill -x Nod || true
echo "smoke: ok"
