#!/bin/bash
set -e

cd "$(dirname "$0")/.."

./scripts/compose.sh logs --tail=300 -f kamailio | egrep "KNVOX SIP|KNVOX SECURITY|flood|scanner|blocked|403|405" || true
