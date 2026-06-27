# KNVOX V1.4.4 - Portal Auth & Public Access

## Objectif

Exposer le portail client KNVOX en HTTPS via Traefik avec une protection Basic Auth.

## Domaine par défaut

portal.knvox.enaes.net

DNS requis :

A portal.knvox.enaes.net -> 51.222.115.82

## Sécurité

- Portail public protégé par Basic Auth
- Token API non exposé au navigateur
- Nginx injecte le header `X-KNVOX-API-Key`
- Accès local conservé sur 127.0.0.1:8090
- PSTN toujours désactivé

## Commandes

make portal-public
make portal-public-test
make portal-public-status

## Identifiants

Les identifiants sont stockés dans `.env` :

PORTAL_BASIC_USER
PORTAL_BASIC_PASSWORD

Ne pas committer `.env`.
