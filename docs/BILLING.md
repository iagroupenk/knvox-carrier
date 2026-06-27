# KNVOX V1.3.0 - Billing Core

## Objectif

Cette version installe la base billing KNVOX :

- CGRateS engine
- PostgreSQL schema billing
- clients
- fournisseurs
- rate decks
- préfixes tarifaires
- CDRs
- wallet transactions
- prefixes bloqués

## Ports

CGRateS est exposé uniquement localement :

- 127.0.0.1:2012 JSON-RPC
- 127.0.0.1:2080 HTTP API si activée

Aucun port billing n'est exposé publiquement.

## Important

Aucun fournisseur PSTN n'est encore connecté.

Les appels externes restent bloqués par Kamailio jusqu'à la mise en place complète :

- contrôle solde
- autorisation d'appel
- limite CPS
- limite appels simultanés
- LCR
- anti-fraude destination
