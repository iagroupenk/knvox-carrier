#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

FAIL=0
ok(){ echo "OK   - $*"; }
fail(){ echo "FAIL - $*"; FAIL=$((FAIL+1)); }

psqlq(){
  ./scripts/compose.sh exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1" | tr -d '\r'
}

echo "===================================="
echo " KNVOX ADMIN CONSOLE PREFLIGHT"
echo "===================================="
echo "Mode: READ-ONLY PREFLIGHT"
echo ""

for F in apps/admin-console/server.js apps/admin-console/public/admin.css apps/admin-console/README.md ops/admin-console.env.example ops/systemd/knvox-admin-console.service.example; do
  if [ -s "$F" ]; then ok "$F present"; else fail "$F missing"; fi
done

if command -v node >/dev/null 2>&1; then
  node --check apps/admin-console/server.js >/dev/null && ok "admin JS syntax OK" || fail "admin JS syntax KO"
else
  fail "node missing"
fi

if git ls-files .env secrets exports 2>/dev/null | grep -q .; then
  fail ".env secrets exports tracked by Git"
else
  ok ".env secrets exports not tracked"
fi

PSTN="$(psqlq "SELECT value FROM billing.system_settings WHERE key='pstn_enabled';" | tr -d '[:space:]')"
ACTIVE="$(psqlq "SELECT count(*) FROM billing.active_calls;" | tr -d '[:space:]')"
BAD="$(psqlq "SELECT count(*) FROM billing.provider_trunks WHERE enabled=true OR sandbox_only=false;" | tr -d '[:space:]')"
DRY="$(psqlq "SELECT count(*) FROM billing.external_call_dry_run_events;" | tr -d '[:space:]')"

[ "$PSTN" = "false" ] && ok "pstn_enabled=false" || fail "pstn_enabled=$PSTN"
[ "$ACTIVE" = "0" ] && ok "active_calls=0" || fail "active_calls=$ACTIVE"
[ "$BAD" = "0" ] && ok "providers sandbox/off" || fail "unsafe_provider_trunks=$BAD"
ok "dry_run_events=$DRY"

ACTIVE_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml"
ACTIVE_VAULT_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.vault.generated.xml"
if [ ! -f "$ACTIVE_XML" ] && [ ! -f "$ACTIVE_VAULT_XML" ]; then
  ok "no active provider gateway XML"
else
  fail "active provider gateway XML detected"
fi

BUNDLE="$(ls -t exports/dr-bundles/knvox-v2-post-release-dr-bundle-*.tar.gz.enc 2>/dev/null | head -n1 || true)"
if [ -n "$BUNDLE" ] && [ -s "$BUNDLE" ] && [ -s "${BUNDLE}.sha256" ]; then
  ok "DR bundle present"
else
  fail "DR bundle missing"
fi

OFFDIR="$(ls -dt exports/offsite-ready/knvox-v2-offsite-* 2>/dev/null | head -n1 || true)"
if [ -n "$OFFDIR" ] && [ -d "$OFFDIR" ]; then
  ok "offsite-ready present"
else
  fail "offsite-ready missing"
fi

echo ""
echo "Failures: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "PREFLIGHT PASSED"
  exit 0
fi

echo "PREFLIGHT FAILED"
exit 1
