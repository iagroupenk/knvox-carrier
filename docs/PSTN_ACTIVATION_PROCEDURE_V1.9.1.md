# KNVOX PSTN Activation Procedure V1.9.1

Status: DRAFT ONLY - DOES NOT ENABLE PSTN

Generated: 2026-06-28T02:08:15+00:00

Purpose:
This document defines the guarded procedure required before any real PSTN activation.

Mandatory prerequisites:
- Git main aligned with origin.
- PSTN currently disabled.
- active_calls equals 0.
- Provider trunks reviewed and approved.
- Provider credential vault validated.
- Rollback plan prepared.
- DR bundle verified.
- Maintenance window approved.

Forbidden actions in this release:
- No provider gateway XML activation.
- No pstn_enabled=true.
- No real outbound call placement.

Activation gate:
A future release must explicitly perform a separate activation command and rollback command after operator approval.

Rollback rule:
Rollback must force pstn_enabled=false, disable provider trunks, remove active gateway XML, reload services, run PSTN safety audit and run health.
