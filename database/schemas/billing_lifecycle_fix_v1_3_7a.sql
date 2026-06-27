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
    v_call_id TEXT;
BEGIN
    v_call_id := COALESCE(NULLIF(p_call_id, ''), gen_random_uuid()::text);

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

CREATE OR REPLACE FUNCTION billing.end_call(
    p_call_id TEXT,
    p_end_reason TEXT DEFAULT 'normal'
)
RETURNS TABLE (
    found BOOLEAN,
    call_id TEXT,
    customer_code TEXT,
    src TEXT,
    dst TEXT,
    normalized_dst TEXT,
    duration_sec INTEGER,
    cost NUMERIC(14,6),
    balance_after NUMERIC(14,6),
    reason TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_call RECORD;
    v_rate RECORD;
    v_duration INTEGER;
    v_cost NUMERIC(14,6);
    v_balance NUMERIC(14,6);
    v_destination TEXT;
    v_rate_per_min NUMERIC(14,6);
BEGIN
    SELECT *
    INTO v_call
    FROM billing.active_calls ac
    WHERE ac.call_id = p_call_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            false,
            p_call_id,
            NULL::TEXT,
            NULL::TEXT,
            NULL::TEXT,
            NULL::TEXT,
            0,
            0::NUMERIC(14,6),
            0::NUMERIC(14,6),
            'active_call_not_found';
        RETURN;
    END IF;

    v_duration := GREATEST(1, EXTRACT(EPOCH FROM (now() - v_call.started_at))::INTEGER);

    IF v_call.normalized_dst ~ '^(9996|100[0-9]|101[0-9])$' THEN
        v_cost := 0::NUMERIC(14,6);
        v_destination := 'Internal';
        v_rate_per_min := 0::NUMERIC(14,6);
    ELSE
        SELECT *
        INTO v_rate
        FROM billing.rate_prefixes rp
        WHERE rp.enabled = true
          AND v_call.normalized_dst LIKE rp.prefix || '%'
        ORDER BY length(rp.prefix) DESC
        LIMIT 1;

        IF FOUND THEN
            v_destination := v_rate.destination;
            v_rate_per_min := v_rate.rate_per_min;
            v_cost := (
                v_rate.setup_fee +
                (
                    CEIL(GREATEST(v_duration, v_rate.minimum_sec)::NUMERIC / v_rate.increment_sec::NUMERIC)
                    * v_rate.increment_sec::NUMERIC
                    / 60::NUMERIC
                    * v_rate.rate_per_min
                )
            )::NUMERIC(14,6);
        ELSE
            v_destination := 'No rate on end';
            v_rate_per_min := 0::NUMERIC(14,6);
            v_cost := 0::NUMERIC(14,6);
        END IF;
    END IF;

    UPDATE billing.cdrs c
    SET
        duration_sec = v_duration,
        rate_per_min = v_rate_per_min,
        cost = v_cost,
        status = 'rated'
    WHERE c.call_id = p_call_id;

    IF NOT FOUND THEN
        INSERT INTO billing.cdrs(
            call_id,
            customer_code,
            src,
            dst,
            destination,
            duration_sec,
            rate_per_min,
            cost,
            currency,
            status
        )
        VALUES (
            p_call_id,
            v_call.customer_code,
            v_call.src,
            v_call.dst,
            v_destination,
            v_duration,
            v_rate_per_min,
            v_cost,
            'EUR',
            'rated'
        );
    END IF;

    IF v_cost > 0 THEN
        UPDATE billing.customers c
        SET prepaid_balance = c.prepaid_balance - v_cost
        WHERE c.code = v_call.customer_code
        RETURNING c.prepaid_balance INTO v_balance;

        INSERT INTO billing.wallet_transactions(customer_code, amount, currency, type, reference)
        VALUES (v_call.customer_code, -v_cost, 'EUR', 'call_debit', p_call_id);
    ELSE
        SELECT c.prepaid_balance
        INTO v_balance
        FROM billing.customers c
        WHERE c.code = v_call.customer_code;
    END IF;

    DELETE FROM billing.active_calls ac
    WHERE ac.call_id = p_call_id;

    RETURN QUERY SELECT
        true,
        p_call_id,
        v_call.customer_code,
        v_call.src,
        v_call.dst,
        v_call.normalized_dst,
        v_duration,
        v_cost,
        COALESCE(v_balance, 0::NUMERIC(14,6)),
        p_end_reason;
END;
$$;
