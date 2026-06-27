# KNVOX V1.2.0 - SIP Security Layer

## Objectif

Cette version empêche le serveur SIP de fonctionner comme relais ouvert.

## Destinations autorisées en V1.2.0

Uniquement :

- 1000 à 1019
- 9996 echo test

Tout autre numéro est bloqué par Kamailio avec :

403 Destination Blocked

## Protections actives

- limitation des méthodes SIP
- anti-scan User-Agent
- rate limit IP avec Pike
- blocage des destinations externes
- logs sécurité Kamailio
- FreeSWITCH non exposé directement

## Important

Ne pas connecter de trunk fournisseur avant la mise en place de :

- comptes clients
- ACL IP clients
- billing temps réel
- limite d'appels simultanés
- limite CPS
- blocage pays sensibles
- alertes solde
