# KNVOX PSTN Rollback Procedure V1.9.2

Status: GUARDED ROLLBACK PROCEDURE - DOES NOT ENABLE PSTN

Generated: 2026-06-28T02:11:58+00:00

Purpose:
This document defines the emergency rollback procedure to return KNVOX to a safe no-PSTN state.

Rollback objectives:
- Force pstn_enabled=false.
- Ensure active_calls equals 0.
- Disable/sandbox provider trunks.
- Remove or keep disabled any provider gateway XML.
- Reload/check services only after safety validation.
- Run PSTN safety audit.
- Run health checks.
- Confirm external-call API remains dry-run only.

Emergency rollback command sequence:
1. make pstn-force-off
2. Verify billing.system_settings pstn_enabled=false
3. Verify billing.active_calls count=0
4. Verify provider_trunks enabled=false and sandbox_only=true
5. Verify no active provider gateway XML exists
6. Run make pstn-safety-audit
7. Run make health

Forbidden in this release:
- No pstn_enabled=true.
- No active provider gateway XML.
- No real outbound PSTN call.
