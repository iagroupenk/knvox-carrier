# KNVOX V1.3.8 - Fraud Guard & Limits

## Objectif

Cette version ajoute une couche anti-fraude avant l'autorisation billing.

## Contrôles actifs

- CPS par client
- Nombre d'appels simultanés
- Verrouillage fraude client
- Tarif maximum par minute
- Limite de dépense journalière
- Journalisation des tentatives d'appel
- Journalisation des événements fraude

## Tables

- billing.call_attempts
- billing.fraud_events

## Colonnes ajoutées sur billing.customers

- fraud_locked
- daily_spend_limit
- max_rate_per_min
- max_call_duration_sec

## Comportement attendu

- 9996 : autorisé
- 979123456 : bloqué avec `max_rate_per_min`
- deuxième appel lancé dans la même seconde : bloqué avec `cps_limit`
- client fraud_locked=true : bloqué avec `fraud_locked`

## Important

Le PSTN reste désactivé. Aucun trunk fournisseur ne doit être connecté avant validation complète.
