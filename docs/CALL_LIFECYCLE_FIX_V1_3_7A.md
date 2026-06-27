# KNVOX V1.3.7a - Call Lifecycle SQL Fix

## Correction

Correction de l'ambiguïté PostgreSQL sur `call_id` dans la fonction `billing.start_call()`.

Ancien comportement :

- API `/api/v1/start-call`
- erreur 500
- PostgreSQL : `column reference "call_id" is ambiguous`

Nouveau comportement :

- `billing.start_call()` utilise UPDATE puis INSERT
- plus de `ON CONFLICT (call_id)` ambigu
- `billing.end_call()` évite aussi les conflits similaires sur les CDR

## Tests

make call-lifecycle-test
make health
