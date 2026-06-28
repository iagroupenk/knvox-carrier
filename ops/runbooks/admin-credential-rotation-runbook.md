# KNVOX Admin Credential Rotation Runbook

Status: RUNBOOK ONLY - SAFE PRE-PROD - NO AUTOMATIC ACTIVATION

## Mandatory safety position

- PSTN OFF.
- Providers sandbox/off.
- No active FreeSWITCH provider gateway XML.
- No active calls.
- External-call API dry-run only.
- Admin console read-only.
- Production go-live not authorized.

## Objective

Document the safe rotation procedure for admin console credentials without executing a rotation in this release.

## Current credential model

- Admin environment file: /etc/knvox-admin-console.env
- Admin service: knvox-admin-console
- Local bind only: 127.0.0.1:8095
- Recommended authentication: ADMIN_PASSWORD_SHA256 when supported.
- Fallback authentication: ADMIN_PASSWORD only when SHA256 is not supported by the app.
- Session secret must be long and unique.

## Manual rotation procedure

1. Generate a new random password.
2. Generate SHA256 hash if ADMIN_PASSWORD_SHA256 is supported.
3. Backup /etc/knvox-admin-console.env with mode 0600.
4. Replace only the admin password or password hash.
5. Rotate ADMIN_SESSION_SECRET if a full session reset is required.
6. Restart knvox-admin-console.
7. Verify login locally on http://127.0.0.1:8095/admin/login.
8. Confirm PSTN remains OFF.
9. Confirm providers remain sandbox/off.
10. Store the new password in the approved external vault, not in Git.

## Required checks after rotation

cd /opt/knvox-carrier
sudo scripts/admin-console-preflight.sh
make pstn-safety-audit
make provider-vault-audit
make provider-gateway-vault-audit
make provider-readiness-audit
make health

## Forbidden actions

This runbook does not authorize:
- PSTN activation.
- Provider activation.
- Active gateway XML generation.
- Real calls.
- Production go-live.
- Committing /etc/knvox-admin-console.env.
- Printing secrets in reports.
- Storing passwords in Git.
