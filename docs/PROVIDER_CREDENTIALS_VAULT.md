# KNVOX V1.6.2 - Provider Credentials Vault

Stockage chiffré local des credentials provider.

Règles :
- pas de password provider en clair dans PostgreSQL
- secrets/ ignoré par Git
- exports/ ignoré par Git
- VAULT_MASTER_KEY dans .env
- PSTN toujours désactivé
- aucun trunk réel connecté
