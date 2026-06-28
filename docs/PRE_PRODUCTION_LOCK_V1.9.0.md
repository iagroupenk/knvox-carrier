# KNVOX Pre-Production Lock V1.9.0

Status: PSTN OFF / DR READY / API DRY-RUN ONLY

Locked at: 2026-06-28T02:06:48+00:00

Git commit at generation: 2cec5a77bf01b5f1417c4231033188fa73afd46c

Critical guarantees:
- PSTN remains disabled.
- External call API remains dry-run only.
- Provider gateways remain sandbox/disabled.
- Secrets, .env and exports are not tracked by Git.
- DR bundle, database dump and Docker image backup exist.
- Health and PSTN safety audits must pass before any production change.

Activation rule:
Real PSTN activation requires a separate explicit activation procedure, zero active calls, provider credential validation, route approval and rollback plan.
