#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

USERNAME="${1:-1001}"

echo "===================================="
echo " KNVOX SIP REGISTRATION CHECK ${USERNAME}"
echo "===================================="

OUT="$(./scripts/fs_cli.sh -x "sofia status profile internal reg" || true)"

echo "$OUT"

echo ""
if echo "$OUT" | grep -E "(${USERNAME}@|Auth-User:[[:space:]]*${USERNAME}|User:[[:space:]]*${USERNAME}|${USERNAME})" >/dev/null; then
  echo "OK: compte ${USERNAME} semble enregistré."
else
  echo "INFO: compte ${USERNAME} non visible dans les registrations."
  echo "Configure le softphone puis relance :"
  echo "SIP_USER=${USERNAME} make sip-reg-check"
fi
