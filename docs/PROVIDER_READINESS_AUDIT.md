# KNVOX V1.6.4 - Provider Readiness Audit

Objectif : vérifier qu'un provider sandbox est prêt techniquement avant toute future activation réelle.

Contrôles :

- PSTN OFF
- Aucun appel actif
- Provider trunk présent
- Credential vault présent et déchiffrable
- Aucun mot de passe provider en clair DB
- Aucun gateway actif FreeSWITCH
- Route sandbox trouvée
- Marge positive
- Gateway généré en .disabled

Commandes :

make provider-readiness-test
make provider-readiness-audit

Cette version ne connecte aucun trunk réel.
