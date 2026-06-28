# KNVOX Security Review / Secrets Hygiene Runbook

Status: RUNBOOK ONLY - SAFE PRE-PROD - NO AUTOMATIC ACTIVATION

## Mandatory safety position

- PSTN OFF.
- Providers sandbox/off.
- No active FreeSWITCH provider gateway XML.
- No active calls.
- External-call API dry-run only.
- Admin console read-only.
- Production go-live not authorized.

## Secrets hygiene objectives

- Confirm .env is not tracked by Git.
- Confirm secrets directory is not tracked by Git.
- Confirm exports directory is not tracked by Git.
- Confirm provider passwords are not stored in clear text in the database.
- Confirm provider credential references point to encrypted secret files.
- Confirm gateway vault remains disabled unless a separate approved release authorizes activation.
- Confirm admin environment file is outside Git.
- Confirm admin session secret is long and unique.
- Confirm API tokens are never printed in reports.

## Manual review commands

cd /opt/knvox-carrier
git status
git ls-files .env secrets exports
make provider-vault-audit
make provider-gateway-vault-audit
make provider-readiness-audit
make pstn-safety-audit
scripts/admin-console-preflight.sh
make health

## Evidence to capture

- Date and operator.
- Git HEAD and latest tag.
- Output proving .env, secrets and exports are not tracked.
- Provider vault audit output.
- Provider gateway vault audit output.
- Provider readiness audit output.
- PSTN safety audit output.
- Admin preflight output.
- Health output.

## Red flags

- .env appears in git ls-files.
- secrets appears in git ls-files.
- exports appears in git ls-files.
- Provider password appears in clear text DB fields.
- Provider credential_ref is missing.
- Active provider gateway XML exists.
- pstn_enabled is not false.
- active_calls is not zero.
- unsafe_provider_trunks is not zero.

## Containment if a secret leak is suspected

1. Stop using the suspected token or password.
2. Rotate the credential in the upstream provider or service.
3. Replace local encrypted secret material.
4. Re-run provider vault and gateway vault audits.
5. Confirm Git history does not expose the secret.
6. Keep PSTN OFF and providers sandbox/off.
7. Record evidence in the incident documentation.

## Forbidden actions

This runbook does not authorize:
- PSTN activation.
- Provider activation.
- Active gateway XML generation.
- Real calls.
- Printing secret values.
- Committing .env, secrets, exports, tokens or passwords.
- Production go-live.
