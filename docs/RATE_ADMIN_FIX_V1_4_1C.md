# KNVOX V1.4.1c - Blocked Prefix SQL Fix

## Correction

Correction de l'ambiguïté PostgreSQL sur `prefix` dans la fonction :

billing.upsert_blocked_prefix(...)

Ancienne erreur :

column reference "prefix" is ambiguous

## Solution

La fonction utilise maintenant :

- UPDATE billing.blocked_prefixes
- INSERT si aucune ligne modifiée

au lieu de :

ON CONFLICT (prefix)

## Test

make rate-admin-test
make api-status
make health
