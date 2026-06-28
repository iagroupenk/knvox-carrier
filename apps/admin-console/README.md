# KNVOX Admin Console

V2.3.0 baseline admin en mode sécurisé.

## État

- Lecture seule.
- Aucune activation PSTN.
- Aucune génération de gateway provider active.
- Aucune activation de trunk.
- API external-call uniquement en dry-run.
- Les secrets doivent rester dans `.env` ou `secrets/`, jamais dans Git.

## Lancement local

```bash
cd /opt/knvox-carrier/apps/admin-console
ADMIN_CONSOLE_USER=admin \
ADMIN_CONSOLE_PASSWORD="CHANGE_ME_LOCAL_ONLY" \
ADMIN_CONSOLE_SESSION_SECRET="$(openssl rand -hex 32)" \
BILLING_API_URL="http://127.0.0.1:8088" \
BILLING_API_TOKEN="$BILLING_API_TOKEN" \
node server.js
```

Puis ouvrir :

```text
http://127.0.0.1:8090
```

## Mot de passe hashé recommandé

```bash
printf "%s" "mot-de-passe-fort" | sha256sum | awk "{print \$1}"
```

Puis utiliser `ADMIN_CONSOLE_PASSWORD_SHA256` au lieu de `ADMIN_CONSOLE_PASSWORD`.

## Variables

- `ADMIN_CONSOLE_HOST` défaut `127.0.0.1`
- `ADMIN_CONSOLE_PORT` défaut `8090`
- `ADMIN_CONSOLE_USER`
- `ADMIN_CONSOLE_PASSWORD` ou `ADMIN_CONSOLE_PASSWORD_SHA256`
- `ADMIN_CONSOLE_SESSION_SECRET`
- `BILLING_API_URL`
- `BILLING_API_TOKEN`

## Prochaines versions

- V2.3.1 gestion clients.
- V2.3.2 SIP accounts.
- V2.3.3 providers/trunks en lecture seule.
- V2.3.4 billing/CDR dry-run.
- V2.3.5 monitoring admin.
- V2.3.6 paramètres système.
- V2.3.7 audit logs.
