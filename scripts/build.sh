#!/bin/bash
# Build Nod with SwiftPM. Usage: scripts/build.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
swift build -c "$CONFIG" --product Nod -Xswiftc -warnings-as-errors 2>&1 | tee "${TMPDIR:-/tmp}/nod-build.$$.log"
if grep -q "warning:" "${TMPDIR:-/tmp}/nod-build.$$.log"; then
    echo "build.sh: warnings found" >&2
    /bin/rm -f "${TMPDIR:-/tmp}/nod-build.$$.log"
    exit 1
fi
/bin/rm -f "${TMPDIR:-/tmp}/nod-build.$$.log"
echo "$(swift build -c "$CONFIG" --show-bin-path)/Nod"
