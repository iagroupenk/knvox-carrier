# KNVOX Admin Console - Reverse Proxy TLS Runbook

Status: RUNBOOK ONLY - NO AUTOMATIC ACTIVATION - SAFE PRE-PROD

## Mandatory safety position

- PSTN OFF.
- Providers sandbox/off.
- No active FreeSWITCH provider gateway XML.
- No active calls.
- External-call API dry-run only.
- Admin console read-only.
- Production go-live not authorized.

## Recommended exposure model

The admin console must remain bound locally:

ADMIN_CONSOLE_HOST=127.0.0.1
ADMIN_CONSOLE_PORT=8095

Expose it only through a reverse proxy with:
- TLS certificate.
- Firewall.
- IP allowlist.
- Strong admin password or hash.
- ADMIN_ALLOWED_IPS configured.
- No direct public Node.js exposure.

## Example Nginx server block

This example is documentation only.

```nginx
server {
    listen 443 ssl http2;
    server_name admin.example.com;

    ssl_certificate /etc/letsencrypt/live/admin.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8095;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

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

## Forbidden actions

This runbook does not authorize:
- PSTN activation.
- Provider activation.
- Active gateway XML generation.
- Real calls.
- DB mutation from admin.
- SIP mutation.
- Production go-live.
