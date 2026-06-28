# KNVOX Admin Console

V2.3.1 adds a read-only client management module.

Routes: `/admin`, `/admin/clients`, `/admin/clients/:customer_code`, `/api/admin/status`, `/api/admin/clients`.

Safety: PSTN activation, provider activation and gateway XML generation are not available.


## V2.3.2 SIP Accounts Read-Only

Adds `/admin/sip-accounts` and `/api/admin/sip-accounts` in read-only mode.


## V2.3.3 Providers Read-Only

Adds `/admin/providers` and `/api/admin/providers` in read-only mode. Provider activation and gateway XML generation are not available.


## V2.3.4 Billing CDR Dry-run Read-Only

Adds `/admin/billing`, `/api/admin/billing`, `/api/admin/billing/summary` and `/api/admin/billing/dry-run-events` in read-only mode.


## V2.3.5 Monitoring Read-Only

Adds `/admin/monitoring` and `/api/admin/monitoring` in read-only mode.


## V2.3.6 Evidence Center Read-Only

Adds `/admin/evidence` and `/api/admin/evidence` in metadata-only read-only mode.


## V2.3.7 Access Hardening RBAC Read-Only

Adds `/admin/access` and `/api/admin/access` with read-only RBAC/access-hardening status.


## V2.3.8 Production Readiness Checklist Read-Only

Adds `/admin/readiness` and `/api/admin/readiness` with safe pre-production readiness checks in read-only mode.


## V2.3.9 UI Consolidation Navigation Polish

Consolidates admin navigation, dashboard module cards and safe-mode footer in read-only mode.

## V2.4.1 Backoffice Install Systemd Runbook

Adds a read-only preflight script and a systemd activation runbook. Documentation only. No PSTN activation, no provider activation, no real calls, no production go-live.


## V2.4.2 Backoffice Reverse Proxy TLS Runbook

Adds a documentation-only reverse proxy and TLS runbook. No Nginx activation, no certificate issuance, no PSTN activation, no provider activation, no production go-live.


## V2.4.3 Backup Restore Drill Runbook

Adds a documentation-only backup restore drill runbook. No restore execution, no database overwrite, no PSTN activation, no provider activation, no production go-live.

## V2.4.4 Operations Checklist / Daily Safe-Mode Routine

Adds a documentation-only daily safe-mode operations checklist. No production action, no PSTN activation, no provider activation, no real calls, no production go-live.

## V2.4.5 Incident Response / Safe-Mode Escalation Runbook

Adds a documentation-only incident response and safe-mode escalation runbook. No production action, no PSTN activation, no provider activation, no restore execution, no production go-live.

## V2.4.6 Security Review / Secrets Hygiene Runbook

Adds a documentation-only security review and secrets hygiene runbook. No secret exposure, no production action, no PSTN activation, no provider activation, no production go-live.
