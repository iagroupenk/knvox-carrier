# KNVOX Operational Acceptance Checklist V1.9.5

Status: PRE-PRODUCTION ACCEPTANCE - DOES NOT ENABLE PSTN

Generated: 2026-06-28T02:16:23+00:00

Acceptance state:
- PSTN OFF.
- API dry-run only.
- Providers sandbox/off.
- No active provider gateway XML.
- Secrets, .env and exports not tracked by Git.
- DR bundle verified.
- PostgreSQL backup verified.
- Docker image backup verified.
- Production change-control document available.
- Activation and rollback procedures documented.

Mandatory checks before future production activation:
1. Git main aligned with origin/main.
2. active_calls equals 0.
3. pstn_enabled equals false before activation gate.
4. Provider credentials validated.
5. Rollback command validated.
6. DR bundle checksum verified.
7. PSTN safety audit passes.
8. Health check passes.

Current release guarantee:
This release only validates operational readiness and does not place real calls.
