# KNVOX Backup Restore Drill Runbook

Status: RUNBOOK ONLY - NO RESTORE EXECUTION - SAFE PRE-PROD

## Mandatory safety position

- PSTN OFF.
- Providers sandbox/off.
- No active FreeSWITCH provider gateway XML.
- No active calls.
- External-call API dry-run only.
- Admin console read-only.
- Production go-live not authorized.

## Objective

Document a controlled restore drill procedure for KNVOX assets without executing any restore during this release.

## Assets to verify before any drill

- Latest encrypted V2 DR bundle in exports/dr-bundles.
- Matching SHA256 checksum.
- Latest offsite-ready package in exports/offsite-ready.
- Latest PostgreSQL dump in exports/db-backups.
- Docker image backup for knvox-billing-api.
- Admin documentation and runbooks.

## Manual validation commands

```bash
cd /opt/knvox-carrier
sudo scripts/admin-console-preflight.sh
make pstn-safety-audit
make provider-vault-audit
make provider-gateway-vault-audit
make provider-readiness-audit
make health
```

## Restore drill principle

A restore drill must be executed only on an isolated test host or disposable namespace.

Production host restrictions:
- Do not restore database over the live DB.
- Do not start PSTN.
- Do not activate providers.
- Do not generate active gateway XML.
- Do not place real calls.

## Isolated drill outline

1. Copy the encrypted DR bundle and checksum to an isolated test host.
2. Verify checksum with sha256sum -c.
3. Decrypt using the approved offline procedure.
4. Extract into a temporary directory.
5. Load Docker image backups into the isolated Docker engine.
6. Restore PostgreSQL dump into a temporary database only.
7. Start services with PSTN forced OFF.
8. Run health and safety audits.
9. Destroy the temporary database and temporary files.
10. Produce a signed evidence note.

## Evidence required after a real drill

- Hostname of isolated drill machine.
- Date and operator.
- DR bundle filename and checksum.
- Database restore target name.
- Docker image IDs loaded.
- PSTN OFF proof.
- Provider sandbox/off proof.
- Health output.
- Cleanup proof.

## Forbidden actions

This runbook does not authorize:
- Production restore execution.
- Live database overwrite.
- PSTN activation.
- Provider activation.
- Active gateway XML generation.
- Real calls.
- Production go-live.
