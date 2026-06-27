CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.customer_admin_events (
    id BIGSERIAL PRIMARY KEY,
    customer_code TEXT,
    event_type TEXT NOT NULL,
    amount NUMERIC(14,6),
    currency TEXT DEFAULT 'EUR',
    reference TEXT,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customer_admin_events_customer_created
ON billing.customer_admin_events(customer_code, created_at DESC);

ALTER TABLE billing.customers
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE billing.customers
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION billing.customer_summary(p_customer_code TEXT)
RETURNS TABLE (
    code TEXT,
    name TEXT,
    status TEXT,
    currency TEXT,
    prepaid_balance NUMERIC(14,6),
    rated_usage NUMERIC(14,6),
    theoretical_remaining_balance NUMERIC(14,6),
    cps_limit INTEGER,
    max_concurrent_calls INTEGER,
    fraud_locked BOOLEAN,
    daily_spend_limit NUMERIC(14,6),
    max_rate_per_min NUMERIC(14,6),
    max_call_duration_sec INTEGER,
    active_calls BIGINT,
    cdrs BIGINT,
    fraud_events BIGINT,
    routing_decisions BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.code,
        c.name,
        c.status,
        c.currency,
        c.prepaid_balance,
        COALESCE((SELECT SUM(x.cost) FROM billing.cdrs x WHERE x.customer_code = c.code), 0)::NUMERIC(14,6) AS rated_usage,
        (
            c.prepaid_balance - COALESCE((SELECT SUM(x.cost) FROM billing.cdrs x WHERE x.customer_code = c.code), 0)
        )::NUMERIC(14,6) AS theoretical_remaining_balance,
        c.cps_limit,
        c.max_concurrent_calls,
        c.fraud_locked,
        c.daily_spend_limit,
        c.max_rate_per_min,
        c.max_call_duration_sec,
        COALESCE((SELECT COUNT(*) FROM billing.active_calls ac WHERE ac.customer_code = c.code), 0) AS active_calls,
        COALESCE((SELECT COUNT(*) FROM billing.cdrs cd WHERE cd.customer_code = c.code), 0) AS cdrs,
        COALESCE((SELECT COUNT(*) FROM billing.fraud_events fe WHERE fe.customer_code = c.code), 0) AS fraud_events,
        COALESCE((SELECT COUNT(*) FROM billing.routing_decisions rd WHERE rd.customer_code = c.code), 0) AS routing_decisions
    FROM billing.customers c
    WHERE c.code = p_customer_code;
END;
$$;
