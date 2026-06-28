# KNVOX V1.6.5 - External Call Dry-Run API

Endpoint :

POST /api/v1/external-call/dry-run

Objectif :

- Simuler un appel externe via API
- Retourner provider, destination, sell rate, buy rate, marge
- Confirmer que PSTN reste OFF
- Ne jamais envoyer d'INVITE SIP
- Journaliser dans billing.external_call_dry_run_events

Sécurité :

- Aucun trunk réel utilisé
- Aucun fichier gateway actif
- pstn_enabled reste false
- dry_run=true
- call_was_placed=false

Test :

make external-call-dry-run-test
