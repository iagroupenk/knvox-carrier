# KNVOX Admin Console - Systemd Activation Runbook

Status: RUNBOOK ONLY - NO AUTOMATIC ACTIVATION - SAFE PRE-PROD

## Mandatory safety position

- PSTN OFF.
- Providers sandbox/off.
- No active FreeSWITCH provider gateway.
- No active calls.
- External-call API dry-run only.
- Admin console read-only.
- Production go-live not authorized.

## Mandatory preflight

Run manually:

```bash
cd /opt/knvox-carrier
sudo scripts/admin-console-preflight.sh
make pstn-safety-audit
make provider-vault-audit
make provider-gateway-vault-audit
make provider-readiness-audit
make health
```

## Manual systemd installation only

```bash
sudo install -m 0640 -o root -g root ops/admin-console.env.example /etc/knvox-admin-console.env
sudo nano /etc/knvox-admin-console.env
sudo cp ops/systemd/knvox-admin-console.service.example /etc/systemd/system/knvox-admin-console.service
sudo systemctl daemon-reload
sudo systemctl enable --now knvox-admin-console
sudo systemctl status knvox-admin-console --no-pager
```

## Rollback

```bash
sudo systemctl disable --now knvox-admin-console
sudo rm -f /etc/systemd/system/knvox-admin-console.service
sudo systemctl daemon-reload
```

## Forbidden actions

This runbook does not authorize PSTN activation, provider activation, active gateway XML generation, real calls, DB mutation from admin, SIP mutation, or production go-live.
