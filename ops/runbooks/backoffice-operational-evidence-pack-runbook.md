# KNVOX Backoffice Operational Evidence Pack Runbook

Status: RUNBOOK ONLY - SAFE PRE-PROD - NO AUTOMATIC ACTIVATION

## Mandatory safety position

- PSTN OFF.
- Providers sandbox/off.
- No active FreeSWITCH provider gateway XML.
- No active calls.
- External-call API dry-run only.
- Admin console read-only.
- Admin console local only on 127.0.0.1:8095.
- Production go-live not authorized.

## Objective

Document how to produce a non-secret operational evidence pack for the KNVOX backoffice.

## Evidence scope

- Git HEAD and latest validated tag.
- Admin service status.
- Local bind check on 127.0.0.1:8095.
- Login page reachability.
- Admin preflight result.
- PSTN safety audit result.
- Provider vault audit result.
- Provider gateway vault audit result.
- Provider readiness audit result.
- Health result.
- DB safety state: pstn_enabled, active_calls, unsafe_provider_trunks.
- DR bundle checksum verification.

## Secret handling rules

- Do not print admin password.
- Do not print API tokens.
- Do not print provider credentials.
- Do not include /etc/knvox-admin-console.env in Git.
- Do not include .env, secrets or exports in Git.

## Forbidden actions

This runbook does not authorize:
- PSTN activation.
- Provider activation.
- Active gateway XML generation.
- Real calls.
- DB mutation.
- SIP mutation.
- Production go-live.
