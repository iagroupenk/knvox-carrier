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
