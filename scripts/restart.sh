#!/bin/bash
set -e
cd "$(dirname "$0")/.."
./scripts/compose.sh restart
