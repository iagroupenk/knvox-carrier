CREATE SCHEMA IF NOT EXISTS billing;

ALTER TABLE billing.customers
ADD COLUMN IF NOT EXISTS fraud_locked BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE billing.customers
ADD COLUMN IF NOT EXISTS daily_spend_limit NUMERIC(14,6) NOT NULL DEFAULT 20.000000;

ALTER TABLE billing.customers
ADD COLUMN IF NOT EXISTS max_rate_per_min NUMERIC(14,6) NOT NULL DEFAULT 0.500000;

ALTER TABLE billing.customers
ADD COLUMN IF NOT EXISTS max_call_duration_sec INTEGER NOT NULL DEFAULT 3600;

UPDATE billing.customers
SET
    fraud_locked = false,
    daily_spend_limit = 20.000000,
    max_rate_per_min = 0.500000,
    max_call_duration_sec = 3600
WHERE code = 'TEST1000';

CREATE TABLE IF NOT EXISTS billing.call_attempts (
    id BIGSERIAL PRIMARY KEY,
    call_id TEXT,
    customer_code TEXT,
    src TEXT,
    dst TEXT,
    normalized_dst TEXT,
    allowed BOOLEAN,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_call_attempts_customer_created
ON billing.call_attempts(customer_code, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_call_attempts_call_id
ON billing.call_attempts(call_id);

CREATE TABLE IF NOT EXISTS billing.fraud_events (
    id BIGSERIAL PRIMARY KEY,
    customer_code TEXT,
    event_type TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'medium',
    src TEXT,
    dst TEXT,
    normalized_dst TEXT,
    call_id TEXT,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fraud_events_customer_created
ON billing.fraud_events(customer_code, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_fraud_events_type_created
ON billing.fraud_events(event_type, created_at DESC);

DO $$
DECLARE
    v_deck_id INTEGER;
    v_has_rate_deck_id BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'billing'
          AND table_name = 'rate_prefixes'
          AND column_name = 'rate_deck_id'
    )
    INTO v_has_rate_deck_id;

    SELECT id INTO v_deck_id
    FROM billing.rate_decks
    ORDER BY id
    LIMIT 1;

    IF NOT EXISTS (SELECT 1 FROM billing.rate_prefixes WHERE prefix = '979') THEN
        IF v_has_rate_deck_id THEN
            INSERT INTO billing.rate_prefixes(
                rate_deck_id,
                prefix,
                destination,
                rate_per_min,
                setup_fee,
                minimum_sec,
                increment_sec,
                enabled
            )
            VALUES (
                v_deck_id,
                '979',
                'High Rate Fraud Test',
                2.000000,
                0.000000,
                1,
                1,
                true
            );
        ELSE
            INSERT INTO billing.rate_prefixes(
                prefix,
                destination,
                rate_per_min,
                setup_fee,
                minimum_sec,
                increment_sec,
                enabled
            )
            VALUES (
                '979',
                'High Rate Fraud Test',
                2.000000,
                0.000000,
                1,
                1,
                true
            );
        END IF;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION billing.fraud_precheck(
    p_customer_code TEXT,
    p_src TEXT,
    p_dst TEXT,
    p_call_id TEXT
)
RETURNS TABLE (
    allowed BOOLEAN,
    reason TEXT,
    customer_balance NUMERIC(14,6),
    rate_per_min NUMERIC(14,6),
    estimated_min_cost NUMERIC(14,6),
    active_calls INTEGER,
    max_concurrent_calls INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer RECORD;
    v_dst TEXT;
    v_attempts_1s INTEGER;
    v_active_count INTEGER;
    v_rate RECORD;
    v_rate_per_min NUMERIC(14,6) := 0.000000;
    v_estimated NUMERIC(14,6) := 0.000000;
    v_usage_today NUMERIC(14,6) := 0.000000;
    v_cps_limit INTEGER;
BEGIN
    v_dst := billing.normalize_dst(p_dst);

    SELECT *
    INTO v_customer
    FROM billing.customers c
    WHERE c.code = p_customer_code;

    IF NOT FOUND THEN
        INSERT INTO billing.call_attempts(call_id, customer_code, src, dst, normalized_dst, allowed, reason)
        VALUES (p_call_id, p_customer_code, p_src, p_dst, v_dst, false, 'customer_not_found');

        INSERT INTO billing.fraud_events(customer_code, event_type, severity, src, dst, normalized_dst, call_id, details)
        VALUES (p_customer_code, 'customer_not_found', 'high', p_src, p_dst, v_dst, p_call_id, '{}'::jsonb);

        RETURN QUERY SELECT false, 'customer_not_found', 0::NUMERIC(14,6), 0::NUMERIC(14,6), 0::NUMERIC(14,6), 0, 0;
        RETURN;
    END IF;

    SELECT count(*)
    INTO v_active_count
    FROM billing.active_calls ac
    WHERE ac.customer_code = p_customer_code;

    INSERT INTO billing.call_attempts(call_id, customer_code, src, dst, normalized_dst, allowed, reason)
    VALUES (p_call_id, p_customer_code, p_src, p_dst, v_dst, NULL, 'pending');

    IF v_customer.fraud_locked = true THEN
        UPDATE billing.call_attempts ca
        SET allowed = false, reason = 'fraud_locked'
        WHERE ca.id = currval('billing.call_attempts_id_seq');

        INSERT INTO billing.fraud_events(customer_code, event_type, severity, src, dst, normalized_dst, call_id, details)
        VALUES (p_customer_code, 'fraud_locked', 'critical', p_src, p_dst, v_dst, p_call_id, '{}'::jsonb);

        RETURN QUERY SELECT false, 'fraud_locked', v_customer.prepaid_balance, 0::NUMERIC(14,6), 0::NUMERIC(14,6), v_active_count, v_customer.max_concurrent_calls;
        RETURN;
    END IF;

    v_cps_limit := GREATEST(COALESCE(v_customer.cps_limit, 1), 1);

    SELECT count(*)
    INTO v_attempts_1s
    FROM billing.call_attempts ca
    WHERE ca.customer_code = p_customer_code
      AND ca.created_at >= now() - interval '1 second';

    IF v_attempts_1s > v_cps_limit THEN
        UPDATE billing.call_attempts ca
        SET allowed = false, reason = 'cps_limit'
        WHERE ca.id = currval('billing.call_attempts_id_seq');

        INSERT INTO billing.fraud_events(customer_code, event_type, severity, src, dst, normalized_dst, call_id, details)
        VALUES (
            p_customer_code,
            'cps_limit',
            'high',
            p_src,
            p_dst,
            v_dst,
            p_call_id,
            jsonb_build_object('attempts_1s', v_attempts_1s, 'cps_limit', v_cps_limit)
        );

        RETURN QUERY SELECT false, 'cps_limit', v_customer.prepaid_balance, 0::NUMERIC(14,6), 0::NUMERIC(14,6), v_active_count, v_customer.max_concurrent_calls;
        RETURN;
    END IF;

    IF v_active_count >= v_customer.max_concurrent_calls THEN
        UPDATE billing.call_attempts ca
        SET allowed = false, reason = 'concurrent_limit'
        WHERE ca.id = currval('billing.call_attempts_id_seq');

        INSERT INTO billing.fraud_events(customer_code, event_type, severity, src, dst, normalized_dst, call_id, details)
        VALUES (
            p_customer_code,
            'concurrent_limit',
            'high',
            p_src,
            p_dst,
            v_dst,
            p_call_id,
            jsonb_build_object('active_calls', v_active_count, 'max_concurrent_calls', v_customer.max_concurrent_calls)
        );

        RETURN QUERY SELECT false, 'concurrent_limit', v_customer.prepaid_balance, 0::NUMERIC(14,6), 0::NUMERIC(14,6), v_active_count, v_customer.max_concurrent_calls;
        RETURN;
    END IF;

    IF NOT (v_dst ~ '^(9996|100[0-9]|101[0-9])$') THEN
        SELECT *
        INTO v_rate
        FROM billing.rate_prefixes rp
        WHERE rp.enabled = true
          AND v_dst LIKE rp.prefix || '%'
        ORDER BY length(rp.prefix) DESC
        LIMIT 1;

        IF FOUND THEN
            v_rate_per_min := v_rate.rate_per_min;

            v_estimated := (
                v_rate.setup_fee +
                (
                    CEIL(GREATEST(v_rate.minimum_sec, 1)::NUMERIC / v_rate.increment_sec::NUMERIC)
                    * v_rate.increment_sec::NUMERIC
                    / 60::NUMERIC
                    * v_rate.rate_per_min
                )
            )::NUMERIC(14,6);

            IF v_rate_per_min > v_customer.max_rate_per_min THEN
                UPDATE billing.call_attempts ca
                SET allowed = false, reason = 'max_rate_per_min'
                WHERE ca.id = currval('billing.call_attempts_id_seq');

                INSERT INTO billing.fraud_events(customer_code, event_type, severity, src, dst, normalized_dst, call_id, details)
                VALUES (
                    p_customer_code,
                    'max_rate_per_min',
                    'high',
                    p_src,
                    p_dst,
                    v_dst,
                    p_call_id,
                    jsonb_build_object('rate_per_min', v_rate_per_min, 'max_rate_per_min', v_customer.max_rate_per_min)
                );

                RETURN QUERY SELECT false, 'max_rate_per_min', v_customer.prepaid_balance, v_rate_per_min, v_estimated, v_active_count, v_customer.max_concurrent_calls;
                RETURN;
            END IF;

            SELECT COALESCE(SUM(c.cost), 0)::NUMERIC(14,6)
            INTO v_usage_today
            FROM billing.cdrs c
            WHERE c.customer_code = p_customer_code
              AND c.created_at >= date_trunc('day', now());

            IF (v_usage_today + v_estimated) > v_customer.daily_spend_limit THEN
                UPDATE billing.call_attempts ca
                SET allowed = false, reason = 'daily_spend_limit'
                WHERE ca.id = currval('billing.call_attempts_id_seq');

                INSERT INTO billing.fraud_events(customer_code, event_type, severity, src, dst, normalized_dst, call_id, details)
                VALUES (
                    p_customer_code,
                    'daily_spend_limit',
                    'high',
                    p_src,
                    p_dst,
                    v_dst,
                    p_call_id,
                    jsonb_build_object('usage_today', v_usage_today, 'estimated_min_cost', v_estimated, 'daily_spend_limit', v_customer.daily_spend_limit)
                );

                RETURN QUERY SELECT false, 'daily_spend_limit', v_customer.prepaid_balance, v_rate_per_min, v_estimated, v_active_count, v_customer.max_concurrent_calls;
                RETURN;
            END IF;
        END IF;
    END IF;

    UPDATE billing.call_attempts ca
    SET allowed = true, reason = 'fraud_precheck_ok'
    WHERE ca.id = currval('billing.call_attempts_id_seq');

    RETURN QUERY SELECT true, 'fraud_precheck_ok', v_customer.prepaid_balance, v_rate_per_min, v_estimated, v_active_count, v_customer.max_concurrent_calls;
END;
$$;

CREATE OR REPLACE FUNCTION billing.start_call(
    p_customer_code TEXT,
    p_src TEXT,
    p_dst TEXT,
    p_call_id TEXT
)
RETURNS TABLE (
    allowed BOOLEAN,
    reason TEXT,
    normalized_dst TEXT,
    customer_balance NUMERIC(14,6),
    active_calls INTEGER,
    max_concurrent_calls INTEGER,
    rate_per_min NUMERIC(14,6),
    estimated_min_cost NUMERIC(14,6),
    call_id TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_auth RECORD;
    v_guard RECORD;
    v_call_id TEXT;
    v_dst TEXT;
BEGIN
    v_call_id := COALESCE(NULLIF(p_call_id, ''), gen_random_uuid()::text);
    v_dst := billing.normalize_dst(p_dst);

    SELECT *
    INTO v_guard
    FROM billing.fraud_precheck(p_customer_code, p_src, p_dst, v_call_id);

    IF v_guard.allowed = false THEN
        RETURN QUERY SELECT
            false,
            v_guard.reason,
            v_dst,
            v_guard.customer_balance,
            v_guard.active_calls,
            v_guard.max_concurrent_calls,
            v_guard.rate_per_min,
            v_guard.estimated_min_cost,
            v_call_id;
        RETURN;
    END IF;

    SELECT *
    INTO v_auth
    FROM billing.authorize_call(p_customer_code, p_src, p_dst, v_call_id);

    IF v_auth.allowed = true THEN
        UPDATE billing.active_calls ac
        SET last_seen_at = now()
        WHERE ac.call_id = v_call_id;

        IF NOT FOUND THEN
            INSERT INTO billing.active_calls(
                call_id,
                customer_code,
                src,
                dst,
                normalized_dst
            )
            VALUES (
                v_call_id,
                p_customer_code,
                p_src,
                p_dst,
                v_auth.normalized_dst
            );
        END IF;
    END IF;

    RETURN QUERY SELECT
        v_auth.allowed,
        v_auth.reason,
        v_auth.normalized_dst,
        v_auth.customer_balance,
        v_auth.active_calls,
        v_auth.max_concurrent_calls,
        v_auth.rate_per_min,
        v_auth.estimated_min_cost,
        v_call_id;
END;
$$;
