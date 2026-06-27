#!/bin/bash
set -euo pipefail

if ! command -v sngrep >/dev/null 2>&1; then
  echo "sngrep non installé. Lance : make sip-tools-install"
  exit 1
fi

sngrep -d any port 5060
