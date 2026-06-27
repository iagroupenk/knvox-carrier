# KNVOX V1.4.1a - Rate Admin deck_code Fix

## Correction

La table `billing.rate_prefixes` contient une colonne obligatoire `deck_code`.

La fonction `billing.upsert_sell_rate()` a été corrigée pour récupérer automatiquement un deck existant et insérer les nouveaux tarifs avec `deck_code`.

## Erreur corrigée

`null value in column "deck_code" of relation "rate_prefixes" violates not-null constraint`

## Test

make rate-admin-test
make api-status
make health
