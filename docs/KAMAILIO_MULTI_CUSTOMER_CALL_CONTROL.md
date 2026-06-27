# KNVOX V1.5.0 - Kamailio Multi-Customer Call Control

## Objectif

Remplacer le customer `TEST1000` codé en dur dans Kamailio par une résolution dynamique :

SIP username -> billing.sip_accounts -> customer_code -> billing.start_call()

## Fonctionnement

Lors d'un INVITE, Kamailio appelle :

/usr/local/bin/knvox-authorize-call.sh '$fU' '$fU' '$rU' '$ci' '$si'

Le script :

1. résout le compte SIP appelant
2. vérifie que le compte SIP est actif
3. vérifie que le customer est actif
4. appelle /api/v1/start-call avec le bon customer_code
5. autorise ou refuse l'appel

## Sécurité

- PSTN toujours désactivé
- Aucun trunk réel connecté
- API token non exposé publiquement
- Les comptes SIP désactivés sont bloqués

## Tests

make call-control-multi
make call-control-multi-test
