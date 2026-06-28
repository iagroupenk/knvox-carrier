# KNVOX V1.6.1 - PSTN Activation Safety Checklist

Objectif : empêcher toute activation PSTN accidentelle.

Commandes :

make pstn-force-off
make pstn-safety-audit
make pstn-status
make pstn-enable-request

Règles :

- pstn_enabled doit rester false
- aucun trunk réel actif
- aucun fichier FreeSWITCH gateway .xml actif
- seuls les fichiers .disabled sont autorisés
- aucun appel actif avant audit
- préfixes bloqués obligatoires
- marge négative interdite

Cette version ne connecte aucun trunk réel.
