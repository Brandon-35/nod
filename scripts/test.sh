#!/bin/bash
# Unit tests; add --smoke to also run the end-to-end smoke test (needs a logged-in session).
set -euo pipefail
cd "$(dirname "$0")/.."

# Command Line Tools ship Swift Testing as a framework, but SwiftPM hands its folder to the
# generated test runner with -I instead of -F. The runner then cannot import Testing and exits 0
# without running a single test. Xcode toolchains need none of this.
ARGS=()
CLT=/Library/Developer/CommandLineTools
if [[ "$(xcode-select -p 2>/dev/null)" == "$CLT" ]]; then
    FW="$CLT/Library/Developer/Frameworks"
    ARGS=(-Xswiftc -F -Xswiftc "$FW"
          -Xlinker -rpath -Xlinker "$FW"
          -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib")
fi

LOG="$(mktemp)"
trap '/bin/rm -f "$LOG"' EXIT
swift test ${ARGS[@]+"${ARGS[@]}"} 2>&1 | tee "$LOG"
if ! grep -qE "Test run with [1-9][0-9]* tests? .*passed" "$LOG"; then
    echo "test.sh: no passing Swift Testing run found" >&2
    exit 1
fi

if [[ "${1:-}" == "--smoke" ]]; then
    scripts/smoke.sh
fi
