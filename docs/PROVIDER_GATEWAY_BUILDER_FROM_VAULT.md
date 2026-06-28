# KNVOX V1.6.3 - Provider Gateway Builder From Vault

Objectif : générer une configuration gateway FreeSWITCH depuis les credentials chiffrés.

Règles :

- Le fichier généré reste dans `secrets/`
- Le fichier reste en `.disabled`
- FreeSWITCH ne charge rien
- Aucun password provider en clair dans PostgreSQL
- Rien de secret dans GitHub
- PSTN toujours désactivé

Commandes :

make provider-gateway-vault-test
make provider-gateway-vault-build
make provider-gateway-vault-audit
