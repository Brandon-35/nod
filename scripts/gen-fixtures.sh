#!/bin/bash
# Regenerates the committed synthetic fixtures (one seed per kind). Synthetic data, not device data.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product Nod >/dev/null
"$(swift build --show-bin-path)/Nod" --gen-fixtures Tests/NodCoreTests/Fixtures/synthetic
