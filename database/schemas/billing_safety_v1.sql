CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.system_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO billing.system_settings(key, value)
VALUES
('pstn_enabled', 'false'),
('require_balance', 'true'),
('min_call_balance', '0.010000')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS billing.active_calls (
    call_id TEXT PRIMARY KEY,
    customer_code TEXT NOT NULL REFERENCES billing.customers(code),
    src TEXT,
    dst TEXT NOT NULL,
    normalized_dst TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_active_calls_customer
ON billing.active_calls(customer_code);

CREATE TABLE IF NOT EXISTS billing.call_authorizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id TEXT,
    customer_code TEXT,
    src TEXT,
    dst TEXT,
    normalized_dst TEXT,
    allowed BOOLEAN NOT NULL,
    reason TEXT NOT NULL,
    rate_per_min NUMERIC(14,6),
    estimated_min_cost NUMERIC(14,6),
    balance NUMERIC(14,6),
    active_calls INTEGER,
    max_concurrent_calls INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_call_auth_customer
ON billing.call_authorizations(customer_code);

CREATE INDEX IF NOT EXISTS idx_call_auth_created
ON billing.call_authorizations(created_at);

CREATE OR REPLACE FUNCTION billing.normalize_dst(p_dst TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_dst TEXT;
BEGIN
    v_dst := regexp_replace(coalesce(p_dst, ''), '[^0-9+]', '', 'g');

    IF left(v_dst, 1) = '+' THEN
        v_dst := substr(v_dst, 2);
    END IF;

    IF left(v_dst, 2) = '00' THEN
        v_dst := substr(v_dst, 3);
    END IF;

    RETURN v_dst;
END;
$$;

CREATE OR REPLACE FUNCTION billing.setting_bool(p_key TEXT, p_default BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_value TEXT;
BEGIN
    SELECT value INTO v_value
    FROM billing.system_settings
    WHERE key = p_key;

    IF v_value IS NULL THEN
        RETURN p_default;
    END IF;

    RETURN lower(v_value) IN ('true', '1', 'yes', 'on');
END;
$$;

CREATE OR REPLACE FUNCTION billing.authorize_call(
    p_customer_code TEXT,
    p_src TEXT,
    p_dst TEXT,
    p_call_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    allowed BOOLEAN,
    reason TEXT,
    normalized_dst TEXT,
    customer_balance NUMERIC(14,6),
    active_calls INTEGER,
    max_concurrent_calls INTEGER,
    rate_per_min NUMERIC(14,6),
    estimated_min_cost NUMERIC(14,6)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer RECORD;
    v_dst TEXT;
    v_blocked RECORD;
    v_rate RECORD;
    v_active INTEGER;
    v_pstn_enabled BOOLEAN;
    v_estimated NUMERIC(14,6);
    v_call_id TEXT;
BEGIN
    v_call_id := COALESCE(p_call_id, gen_random_uuid()::text);
    v_dst := billing.normalize_dst(p_dst);

    SELECT *
    INTO v_customer
    FROM billing.customers
    WHERE code = p_customer_code;

    IF NOT FOUND THEN
        INSERT INTO billing.call_authorizations(call_id, customer_code, src, dst, normalized_dst, allowed, reason)
        VALUES (v_call_id, p_customer_code, p_src, p_dst, v_dst, false, 'customer_not_found');

        RETURN QUERY SELECT false, 'customer_not_found', v_dst, 0::numeric(14,6), 0, 0, 0::numeric(14,6), 0::numeric(14,6);
        RETURN;
    END IF;

    IF v_customer.status <> 'active' THEN
        INSERT INTO billing.call_authorizations(call_id, customer_code, src, dst, normalized_dst, allowed, reason, balance)
        VALUES (v_call_id, p_customer_code, p_src, p_dst, v_dst, false, 'customer_inactive', v_customer.prepaid_balance);

        RETURN QUERY SELECT false, 'customer_inactive', v_dst, v_customer.prepaid_balance, 0, v_customer.max_concurrent_calls, 0::numeric(14,6), 0::numeric(14,6);
        RETURN;
    END IF;

    IF v_dst ~ '^(9996|100[0-9]|101[0-9])$' THEN
        INSERT INTO billing.call_authorizations(call_id, customer_code, src, dst, normalized_dst, allowed, reason, balance)
        VALUES (v_call_id, p_customer_code, p_src, p_dst, v_dst, true, 'internal_test_allowed', v_customer.prepaid_balance);

        RETURN QUERY SELECT true, 'internal_test_allowed', v_dst, v_customer.prepaid_balance, 0, v_customer.max_concurrent_calls, 0::numeric(14,6), 0::numeric(14,6);
        RETURN;
    END IF;

    SELECT *
    INTO v_blocked
    FROM billing.blocked_prefixes
    WHERE v_dst LIKE prefix || '%'
    ORDER BY length(prefix) DESC
    LIMIT 1;

    IF FOUND THEN
        INSERT INTO billing.call_authorizations(call_id, customer_code, src, dst, normalized_dst, allowed, reason, balance)
        VALUES (v_call_id, p_customer_code, p_src, p_dst, v_dst, false, 'blocked_prefix_' || v_blocked.prefix, v_customer.prepaid_balance);

        RETURN QUERY SELECT false, 'blocked_prefix_' || v_blocked.prefix, v_dst, v_customer.prepaid_balance, 0, v_customer.max_concurrent_calls, 0::numeric(14,6), 0::numeric(14,6);
        RETURN;
    END IF;

    SELECT *
    INTO v_rate
    FROM billing.rate_prefixes
    WHERE enabled = true
      AND v_dst LIKE prefix || '%'
    ORDER BY length(prefix) DESC
    LIMIT 1;

    IF NOT FOUND THEN
        INSERT INTO billing.call_authorizations(call_id, customer_code, src, dst, normalized_dst, allowed, reason, balance)
        VALUES (v_call_id, p_customer_code, p_src, p_dst, v_dst, false, 'no_rate_found', v_customer.prepaid_balance);

        RETURN QUERY SELECT false, 'no_rate_found', v_dst, v_customer.prepaid_balance, 0, v_customer.max_concurrent_calls, 0::numeric(14,6), 0::numeric(14,6);
        RETURN;
    END IF;

    v_estimated := (
        v_rate.setup_fee +
        (
            CEIL(GREATEST(v_rate.minimum_sec, 1)::numeric / v_rate.increment_sec::numeric)
            * v_rate.increment_sec::numeric
            / 60::numeric
            * v_rate.rate_per_min
        )
    )::numeric(14,6);

    SELECT count(*)
    INTO v_active
    FROM billing.active_calls
    WHERE customer_code = p_customer_code;

    IF v_active >= v_customer.max_concurrent_calls THEN
        INSERT INTO billing.call_authorizations(call_id, customer_code, src, dst, normalized_dst, allowed, reason, rate_per_min, estimated_min_cost, balance, active_calls, max_concurrent_calls)
        VALUES (v_call_id, p_customer_code, p_src, p_dst, v_dst, false, 'concurrent_limit', v_rate.rate_per_min, v_estimated, v_customer.prepaid_balance, v_active, v_customer.max_concurrent_calls);

        RETURN QUERY SELECT false, 'concurrent_limit', v_dst, v_customer.prepaid_balance, v_active, v_customer.max_concurrent_calls, v_rate.rate_per_min, v_estimated;
        RETURN;
    END IF;

    IF v_customer.prepaid_balance < v_estimated THEN
        INSERT INTO billing.call_authorizations(call_id, customer_code, src, dst, normalized_dst, allowed, reason, rate_per_min, estimated_min_cost, balance, active_calls, max_concurrent_calls)
        VALUES (v_call_id, p_customer_code, p_src, p_dst, v_dst, false, 'insufficient_balance', v_rate.rate_per_min, v_estimated, v_customer.prepaid_balance, v_active, v_customer.max_concurrent_calls);

        RETURN QUERY SELECT false, 'insufficient_balance', v_dst, v_customer.prepaid_balance, v_active, v_customer.max_concurrent_calls, v_rate.rate_per_min, v_estimated;
        RETURN;
    END IF;

    v_pstn_enabled := billing.setting_bool('pstn_enabled', false);

    IF v_pstn_enabled = false THEN
        INSERT INTO billing.call_authorizations(call_id, customer_code, src, dst, normalized_dst, allowed, reason, rate_per_min, estimated_min_cost, balance, active_calls, max_concurrent_calls)
        VALUES (v_call_id, p_customer_code, p_src, p_dst, v_dst, false, 'pstn_disabled', v_rate.rate_per_min, v_estimated, v_customer.prepaid_balance, v_active, v_customer.max_concurrent_calls);

        RETURN QUERY SELECT false, 'pstn_disabled', v_dst, v_customer.prepaid_balance, v_active, v_customer.max_concurrent_calls, v_rate.rate_per_min, v_estimated;
        RETURN;
    END IF;

    INSERT INTO billing.call_authorizations(call_id, customer_code, src, dst, normalized_dst, allowed, reason, rate_per_min, estimated_min_cost, balance, active_calls, max_concurrent_calls)
    VALUES (v_call_id, p_customer_code, p_src, p_dst, v_dst, true, 'authorized', v_rate.rate_per_min, v_estimated, v_customer.prepaid_balance, v_active, v_customer.max_concurrent_calls);

    RETURN QUERY SELECT true, 'authorized', v_dst, v_customer.prepaid_balance, v_active, v_customer.max_concurrent_calls, v_rate.rate_per_min, v_estimated;
END;
$$;
