# KNVOX Production Change Control V1.9.4

Status: CONTROL DOCUMENT - DOES NOT ENABLE PSTN

Generated: 2026-06-28T02:14:41+00:00

Purpose:
This document defines the mandatory change-control rules before any production-impacting action.

Mandatory approvals before production change:
- Operator approval.
- Technical validation.
- DR bundle verified.
- Rollback procedure available.
- Health checks passing.
- PSTN safety audit passing.
- Active calls equal 0.
- Provider configuration reviewed.

Forbidden without explicit release gate:
- Setting pstn_enabled=true.
- Activating provider gateway XML.
- Placing real outbound PSTN calls.
- Disabling safety audits.
- Tracking .env, secrets or exports in Git.

Rollback requirement:
Any production activation must include a tested rollback command sequence and must return the platform to pstn_enabled=false if validation fails.

Current locked state:
PSTN OFF / API DRY-RUN ONLY / PROVIDERS SANDBOX-OFF / DR READY.
