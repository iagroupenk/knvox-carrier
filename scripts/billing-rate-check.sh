#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

DST="${1:-33612345678}"

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v dst="$DST" <<'SQL'
WITH normalized AS (
  SELECT billing.normalize_dst(:'dst') AS nd
),
blocked AS (
  SELECT b.prefix, b.reason
  FROM billing.blocked_prefixes b, normalized n
  WHERE n.nd LIKE b.prefix || '%'
  ORDER BY length(b.prefix) DESC
  LIMIT 1
),
rate AS (
  SELECT r.prefix, r.destination, r.rate_per_min, r.minimum_sec, r.increment_sec
  FROM billing.rate_prefixes r, normalized n
  WHERE r.enabled = true
    AND n.nd LIKE r.prefix || '%'
  ORDER BY length(r.prefix) DESC
  LIMIT 1
)
SELECT
  n.nd AS normalized_dst,
  COALESCE((SELECT prefix FROM blocked), '') AS blocked_prefix,
  COALESCE((SELECT reason FROM blocked), '') AS blocked_reason,
  COALESCE((SELECT prefix FROM rate), '') AS rate_prefix,
  COALESCE((SELECT destination FROM rate), '') AS destination,
  COALESCE((SELECT rate_per_min FROM rate), 0) AS rate_per_min
FROM normalized n;
SQL
