# KNVOX Daily Safe-Mode Operations Checklist

Status: RUNBOOK ONLY - SAFE PRE-PROD - NO AUTOMATIC ACTIVATION

## Mandatory safety position

- PSTN OFF.
- Providers sandbox/off.
- No active FreeSWITCH provider gateway XML.
- No active calls.
- External-call API dry-run only.
- Admin console read-only.
- Production go-live not authorized.

## Daily operator routine

Run these checks once per operating day before any admin usage:

cd /opt/knvox-carrier
sudo scripts/admin-console-preflight.sh
make pstn-safety-audit
make provider-vault-audit
make provider-gateway-vault-audit
make provider-readiness-audit
make health

## Daily evidence to capture

- Date and operator.
- Git HEAD and latest tag.
- PSTN OFF proof.
- Active calls equals zero.
- Providers sandbox/off proof.
- No active provider gateway XML proof.
- Latest DR bundle filename and checksum result.
- Latest offsite-ready package path.
- Health output.

## Escalation conditions

Stop operations and investigate if any of these occur:

- pstn_enabled is not false.
- active_calls is not zero.
- Any provider trunk is enabled or sandbox_only is false.
- A provider gateway XML appears in the active FreeSWITCH external profile.
- DR bundle checksum fails.
- Offsite package is missing.
- Admin console exposes any write/system action.
- External-call dry-run reports call_was_placed true.

## Forbidden actions

This runbook does not authorize:
- PSTN activation.
- Provider activation.
- Active gateway XML generation.
- Real calls.
- Production go-live.
- Database mutation from admin.
- SIP mutation from admin.
