#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(python3 - <<'PY' "${BASH_SOURCE[0]}"
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

sudo "${SCRIPT_DIR}/start-killswitch.sh"
