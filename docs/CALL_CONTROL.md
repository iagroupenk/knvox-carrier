# KNVOX V1.3.6 - Call Control Integration

## Objectif

Kamailio interroge l'API interne de billing avant de laisser passer un appel INVITE.

## Comportement

- 9996 : autorisé par API comme appel interne de test
- 1000 à 1019 : autorisé par API comme appel interne
- Numéro externe avec tarif : refusé tant que PSTN est désactivé
- Préfixe à risque : refusé immédiatement

## API appelée

Kamailio appelle localement :

http://127.0.0.1:8088/api/v1/authorize-call

avec le header :

X-KNVOX-API-Key

## Sécurité

Aucun trunk fournisseur ne doit être connecté tant que :

- PSTN est désactivé
- les routes fournisseurs ne sont pas définies
- la déduction temps réel n'est pas validée
- les limites CPS et appels simultanés ne sont pas reliées en production
