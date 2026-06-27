# KNVOX V1.3.7 - Call Lifecycle & CDR Safety

## Objectif

Cette version ajoute le cycle de vie d'appel :

- Start call
- Active calls
- End call
- CDR
- Débit wallet si appel payant

## Règle actuelle

Le PSTN reste désactivé.

Donc :

- 9996 : autorisé, CDR coût 0
- 1000 à 1019 : autorisé, coût 0
- numéros externes : refusés tant que pstn_enabled=false
- préfixes à risque : refusés

## Endpoints API

POST /api/v1/start-call

POST /api/v1/end-call

GET /api/v1/active-calls

POST /api/v1/cleanup-active-calls
