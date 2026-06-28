#!/usr/bin/env bash
set -euo pipefail
cd /opt/knvox-carrier
set -a
source .env
set +a
[ -f /root/knvox-web-domain.env ] && source /root/knvox-web-domain.env || true
ADMIN_DOMAIN="${ADMIN_DOMAIN:-portal.knvox.enaes.net}"
DOC="docs/V2.5.1_PRODUCTION_CORE_READINESS_INVENTORY.md"
REPORT="exports/audits/v2_5_1_production_core_readiness_inventory_$(date +%Y%m%d-%H%M%S).txt"
psqlq(){ ./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1" | tr -d "\r"; }
table_count(){ T="$1"; E="$(psqlq "SELECT CASE WHEN to_regclass(\$\$$T\$\$) IS NULL THEN 0 ELSE 1 END;" | tr -d "[:space:]")"; if [ "$E" = "1" ]; then psqlq "SELECT count(*) FROM $T;" | tr -d "[:space:]"; else echo 0; fi; }
make pstn-force-off >/tmp/knvox-v251-pstn-force-off.txt
PSTN="$(psqlq "SELECT value FROM billing.system_settings WHERE key=\$\$pstn_enabled\$\$;" | tr -d "[:space:]")"
ACTIVE="$(psqlq "SELECT count(*) FROM billing.active_calls;" | tr -d "[:space:]")"
BAD="$(psqlq "SELECT count(*) FROM billing.provider_trunks WHERE enabled=true OR sandbox_only=false;" | tr -d "[:space:]")"
PROVIDERS="$(table_count billing.provider_trunks)"
SIP="$(table_count billing.sip_accounts)"
CLIENTS="$(table_count billing.clients)"
CUSTOMERS="$(table_count billing.customers)"
ROUTES="$(table_count billing.routes)"
ROUTING_RULES="$(table_count billing.routing_rules)"
RATES="$(table_count billing.rates)"
RATE_CARDS="$(table_count billing.rate_cards)"
FRAUD_LIMITS="$(table_count billing.fraud_limits)"
DEST_BLOCKS="$(table_count billing.destination_blocks)"
CDR="$(table_count billing.cdr)"
CDR2="$(table_count billing.call_detail_records)"
DRY="$(table_count billing.external_call_dry_run_events)"
WEB_CODE="$(curl -k -sS -o /tmp/knvox-v251-web-admin.html -w "%{http_code}" https://$ADMIN_DOMAIN/admin/login || true)"
BUNDLE="$(ls -t exports/dr-bundles/knvox-v2-post-release-dr-bundle-*.tar.gz.enc 2>/dev/null | head -n1 || true)"
DR_STATUS=MISSING
[ -s "$BUNDLE" ] && [ -s "${BUNDLE}.sha256" ] && sha256sum -c "${BUNDLE}.sha256" >/tmp/knvox-v251-dr-check.txt 2>&1 && DR_STATUS=READY
ADMIN_SERVICE=$(systemctl is-active knvox-admin-console 2>/dev/null || true)
BRIDGE_SERVICE=$(systemctl is-active knvox-admin-local-bridge 2>/dev/null || true)
PROXY_RUNNING=$(docker ps --format "{{.Names}}" | grep -qx knvox-admin-web-proxy && echo active || echo inactive)
CLIENT_TOTAL=$((CLIENTS + CUSTOMERS))
ROUTE_TOTAL=$((ROUTES + ROUTING_RULES))
RATE_TOTAL=$((RATES + RATE_CARDS))
FRAUD_TOTAL=$((FRAUD_LIMITS + DEST_BLOCKS))
CDR_TOTAL=$((CDR + CDR2))
{ printf "%s\n" "# KNVOX V2.5.1 Production Core Readiness Inventory" "" "Generated: $(date -Is)" "" "## Safe baseline" "- pstn_enabled=$PSTN" "- active_calls=$ACTIVE" "- unsafe_provider_trunks=$BAD" "- execution_mode=NO_DIAL_NO_PSTN" "- production_go_live_authorized=false" "" "## Web admin access" "- public_domain=$ADMIN_DOMAIN" "- public_admin_noauth_http=$WEB_CODE" "- expected_noauth_http=401" "- admin_service=$ADMIN_SERVICE" "- admin_bridge_service=$BRIDGE_SERVICE" "- admin_web_proxy_container=$PROXY_RUNNING" "- admin_node_bind=127.0.0.1:8095" "- admin_bridge=knvox_frontend_gateway:8096" "- traefik_route=/admin and /api/admin" "" "## Production core inventory" "- safety_baseline=$([ "$PSTN" = false ] && [ "$ACTIVE" = 0 ] && [ "$BAD" = 0 ] && echo READY || echo BLOCKED)" "- web_admin_tls=$([ "$WEB_CODE" = 401 ] && echo READY || echo CHECK)" "- provider_config=$([ "$PROVIDERS" -gt 0 ] && echo PARTIAL || echo MISSING) provider_trunks=$PROVIDERS" "- client_model=$([ "$CLIENT_TOTAL" -gt 0 ] && echo PARTIAL || echo MISSING) clients=$CLIENTS customers=$CUSTOMERS" "- sip_accounts=$([ "$SIP" -gt 0 ] && echo PARTIAL || echo MISSING) sip_accounts=$SIP" "- routing=$([ "$ROUTE_TOTAL" -gt 0 ] && echo PARTIAL || echo MISSING) routes=$ROUTES routing_rules=$ROUTING_RULES" "- rating=$([ "$RATE_TOTAL" -gt 0 ] && echo PARTIAL || echo MISSING) rates=$RATES rate_cards=$RATE_CARDS" "- fraud_controls=$([ "$FRAUD_TOTAL" -gt 0 ] && echo PARTIAL || echo MISSING) fraud_limits=$FRAUD_LIMITS destination_blocks=$DEST_BLOCKS" "- billing_cdr=$([ "$CDR_TOTAL" -gt 0 ] && echo PARTIAL || echo MISSING) cdr=$CDR call_detail_records=$CDR2 dry_run_events=$DRY" "- dr_assets=$DR_STATUS latest_bundle=$BUNDLE" "" "## Priority production gaps" "$([ "$RATE_TOTAL" -eq 0 ] && echo "- RATING_TABLES_MISSING" || true)" "$([ "$ROUTE_TOTAL" -eq 0 ] && echo "- ROUTING_TABLES_MISSING" || true)" "$([ "$FRAUD_TOTAL" -eq 0 ] && echo "- FRAUD_LIMITS_MISSING" || true)" "$([ "$PROVIDERS" -eq 0 ] && echo "- PROVIDER_TRUNKS_MISSING" || true)" "$([ "$SIP" -eq 0 ] && echo "- SIP_ACCOUNTS_MISSING" || true)" "" "## Next implementation order" "1. Provider production onboarding in vault, still disabled." "2. SIP/customer provisioning model." "3. Routing rules and blocked destinations." "4. Rating tables and margin validation." "5. Fraud limits by customer, SIP and destination." "6. Billing/CDR simulation and export." "7. Monitoring and alerting." "" "## Release constraints" "- pstn_activation_executed=false" "- provider_activation_executed=false" "- real_calls_executed=false" "- production_go_live_authorized=false"; } | tee "$DOC" "$REPORT"
chmod 600 "$REPORT"
echo "REPORT=$REPORT"
echo "DOC=$DOC"
echo "=== V2.5.1 PRODUCTION CORE READINESS INVENTORY OK ==="
