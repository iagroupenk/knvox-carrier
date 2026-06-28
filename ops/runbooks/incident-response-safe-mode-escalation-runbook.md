# KNVOX Incident Response / Safe-Mode Escalation Runbook

Status: RUNBOOK ONLY - SAFE PRE-PROD - NO AUTOMATIC ACTIVATION

## Mandatory safety position

- PSTN OFF.
- Providers sandbox/off.
- No active FreeSWITCH provider gateway XML.
- No active calls.
- External-call API dry-run only.
- Admin console read-only.
- Production go-live not authorized.

## Incident triggers

Open an incident immediately if one of these conditions is detected:

- pstn_enabled is not false.
- active_calls is not zero.
- A provider trunk is enabled.
- A provider trunk has sandbox_only false.
- An active provider gateway XML exists in FreeSWITCH external profile.
- External-call dry-run returns call_was_placed true.
- API execution_mode is not NO_DIAL_NO_PSTN.
- DR checksum verification fails.
- Offsite-ready package is missing.
- Admin console exposes write or system actions.

## Immediate containment

cd /opt/knvox-carrier
make pstn-force-off
make pstn-safety-audit
make provider-vault-audit
make provider-gateway-vault-audit
make provider-readiness-audit
make health

## Evidence to capture

- Incident date and operator.
- Git HEAD and latest tag.
- Output of pstn-safety-audit.
- Output of provider-vault-audit.
- Output of provider-gateway-vault-audit.
- Output of provider-readiness-audit.
- Output of health.
- DB state for pstn_enabled, active_calls, unsafe_provider_trunks.
- Presence or absence of active provider gateway XML.
- Latest DR bundle and checksum result.

## Escalation levels

Level 1: Documentation or evidence issue only.
Level 2: Safe-mode drift but no real call possibility.
Level 3: Provider or gateway activation detected.
Level 4: Any real call path suspected.

## Recovery rules

- Do not enable PSTN during incident response.
- Do not enable providers during incident response.
- Do not generate active gateway XML during incident response.
- Do not run restore on live database.
- Do not perform production go-live.
- Keep all admin modules read-only.

## Closure criteria

- pstn_enabled=false.
- active_calls=0.
- unsafe_provider_trunks=0.
- No active provider gateway XML.
- Dry-run reports NO_DIAL_NO_PSTN.
- DR checksum passes.
- Health passes.
- Incident evidence is appended to documentation.

## Forbidden actions

This runbook does not authorize:
- PSTN activation.
- Provider activation.
- Active gateway XML generation.
- Real calls.
- Live database restore.
- Production go-live.
