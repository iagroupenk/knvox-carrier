#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

docker run --rm --network host "${CGRATES_CONSOLE_IMAGE}" "$@"
