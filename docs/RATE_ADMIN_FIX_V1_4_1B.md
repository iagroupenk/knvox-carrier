# KNVOX V1.4.1b - Provider Route SQL Fix

## Correction

Correction de l'ambiguïté PostgreSQL sur `provider_code` dans la fonction :

billing.upsert_provider_route_admin(...)

Ancienne erreur :

column reference "provider_code" is ambiguous

## Solution

La fonction utilise maintenant :

- UPDATE provider_routes
- INSERT si aucune ligne modifiée

au lieu de :

ON CONFLICT (provider_code, prefix)

## Test

make rate-admin-test
make api-status
make health
