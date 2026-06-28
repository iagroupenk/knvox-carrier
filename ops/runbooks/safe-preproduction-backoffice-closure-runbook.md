# KNVOX Safe Pre-Production Backoffice Closure Runbook

Status: CLOSURE RUNBOOK - SAFE PRE-PROD - NO AUTOMATIC ACTIVATION

## Closure objective

Confirm that the KNVOX backoffice is operational locally and safely closed for pre-production use.

## Mandatory closure state

- Admin service active.
- Admin bound to 127.0.0.1:8095.
- Admin login page reachable.
- Admin access validated.
- PSTN OFF.
- Active calls 0.
- Providers sandbox/off.
- Unsafe provider trunks 0.
- No active provider gateway XML.
- External-call API dry-run only.
- No real calls.
- No production go-live.

## Mandatory closure checks

cd /opt/knvox-carrier
sudo scripts/admin-console-preflight.sh
make pstn-force-off
make provider-vault-audit
make provider-gateway-vault-audit
make provider-readiness-audit
make pstn-safety-audit
make health

## Operational limits after closure

- Use admin console only locally or through approved SSH tunnel.
- Do not expose admin publicly without a separate approved reverse proxy and firewall release.
- Do not enable PSTN.
- Do not enable providers.
- Do not generate active gateway XML.
- Do not run real calls.
- Do not restore over live database.

## Next release gate

Any move toward live operations requires a new explicit production go-live gate and must start from PSTN OFF.
