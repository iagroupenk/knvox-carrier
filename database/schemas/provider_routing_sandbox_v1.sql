CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.provider_accounts (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'sandbox',
    enabled BOOLEAN NOT NULL DEFAULT true,
    trunk_enabled BOOLEAN NOT NULL DEFAULT false,
    priority INTEGER NOT NULL DEFAULT 100,
    cps_limit INTEGER NOT NULL DEFAULT 10,
    max_concurrent_calls INTEGER NOT NULL DEFAULT 100,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.provider_routes (
    id BIGSERIAL PRIMARY KEY,
    provider_code TEXT NOT NULL REFERENCES billing.provider_accounts(code),
    prefix TEXT NOT NULL,
    destination TEXT NOT NULL,
    buy_rate_per_min NUMERIC(14,6) NOT NULL DEFAULT 0.000000,
    setup_fee NUMERIC(14,6) NOT NULL DEFAULT 0.000000,
    minimum_sec INTEGER NOT NULL DEFAULT 1,
    increment_sec INTEGER NOT NULL DEFAULT 1,
    enabled BOOLEAN NOT NULL DEFAULT true,
    priority INTEGER NOT NULL DEFAULT 100,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(provider_code, prefix)
);

CREATE INDEX IF NOT EXISTS idx_provider_routes_prefix
ON billing.provider_routes(prefix);

CREATE TABLE IF NOT EXISTS billing.routing_decisions (
    id BIGSERIAL PRIMARY KEY,
    call_id TEXT,
    customer_code TEXT,
    src TEXT,
    dst TEXT,
    normalized_dst TEXT,
    selected_provider_code TEXT,
    route_allowed BOOLEAN NOT NULL DEFAULT false,
    route_reason TEXT NOT NULL,
    destination TEXT,
    sell_rate_per_min NUMERIC(14,6),
    buy_rate_per_min NUMERIC(14,6),
    margin_per_min NUMERIC(14,6),
    estimated_sell_cost NUMERIC(14,6),
    estimated_buy_cost NUMERIC(14,6),
    estimated_margin NUMERIC(14,6),
    pstn_enabled BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_routing_decisions_customer_created
ON billing.routing_decisions(customer_code, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_routing_decisions_call_id
ON billing.routing_decisions(call_id);

INSERT INTO billing.provider_accounts(code, name, status, enabled, trunk_enabled, priority, notes)
VALUES
('SIM-FR-1', 'Sandbox France Provider 1', 'sandbox', true, false, 10, 'Simulation uniquement - aucun trunk réel'),
('SIM-WORLD-1', 'Sandbox World Provider 1', 'sandbox', true, false, 20, 'Simulation uniquement - aucun trunk réel')
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    status = EXCLUDED.status,
    enabled = EXCLUDED.enabled,
    trunk_enabled = false,
    priority = EXCLUDED.priority,
    updated_at = now();

INSERT INTO billing.provider_routes(provider_code, prefix, destination, buy_rate_per_min, setup_fee, minimum_sec, increment_sec, enabled, priority)
VALUES
('SIM-FR-1', '33', 'France Sandbox', 0.004000, 0.000000, 1, 1, true, 10),
('SIM-WORLD-1', '212', 'Morocco Sandbox', 0.009000, 0.000000, 1, 1, true, 20),
('SIM-WORLD-1', '1', 'North America Sandbox', 0.006000, 0.000000, 1, 1, true, 30)
ON CONFLICT (provider_code, prefix) DO UPDATE SET
    destination = EXCLUDED.destination,
    buy_rate_per_min = EXCLUDED.buy_rate_per_min,
    setup_fee = EXCLUDED.setup_fee,
    minimum_sec = EXCLUDED.minimum_sec,
    increment_sec = EXCLUDED.increment_sec,
    enabled = EXCLUDED.enabled,
    priority = EXCLUDED.priority;

CREATE OR REPLACE FUNCTION billing.provider_route_simulate(
    p_customer_code TEXT,
    p_src TEXT,
    p_dst TEXT,
    p_call_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    route_allowed BOOLEAN,
    route_reason TEXT,
    route_call_id TEXT,
    normalized_dst TEXT,
    selected_provider_code TEXT,
    provider_name TEXT,
    destination TEXT,
    sell_rate_per_min NUMERIC(14,6),
    buy_rate_per_min NUMERIC(14,6),
    margin_per_min NUMERIC(14,6),
    estimated_sell_cost NUMERIC(14,6),
    estimated_buy_cost NUMERIC(14,6),
    estimated_margin NUMERIC(14,6),
    pstn_enabled BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_call_id TEXT;
    v_dst TEXT;
    v_customer RECORD;
    v_blocked RECORD;
    v_sell RECORD;
    v_route RECORD;
    v_pstn_enabled BOOLEAN;
    v_est_sell NUMERIC(14,6) := 0.000000;
    v_est_buy NUMERIC(14,6) := 0.000000;
    v_margin_per_min NUMERIC(14,6) := 0.000000;
    v_est_margin NUMERIC(14,6) := 0.000000;
BEGIN
    v_call_id := COALESCE(NULLIF(p_call_id, ''), gen_random_uuid()::text);
    v_dst := billing.normalize_dst(p_dst);
    v_pstn_enabled := billing.setting_bool('pstn_enabled', false);

    IF v_dst ~ '^(9996|100[0-9]|101[0-9])$' THEN
        INSERT INTO billing.routing_decisions(
            call_id, customer_code, src, dst, normalized_dst,
            route_allowed, route_reason, pstn_enabled
        )
        VALUES (
            v_call_id, p_customer_code, p_src, p_dst, v_dst,
            true, 'internal_no_provider', v_pstn_enabled
        );

        RETURN QUERY SELECT
            true,
            'internal_no_provider',
            v_call_id,
            v_dst,
            NULL::TEXT,
            NULL::TEXT,
            'Internal'::TEXT,
            0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            v_pstn_enabled;
        RETURN;
    END IF;

    SELECT *
    INTO v_customer
    FROM billing.customers c
    WHERE c.code = p_customer_code;

    IF NOT FOUND THEN
        INSERT INTO billing.routing_decisions(
            call_id, customer_code, src, dst, normalized_dst,
            route_allowed, route_reason, pstn_enabled
        )
        VALUES (
            v_call_id, p_customer_code, p_src, p_dst, v_dst,
            false, 'customer_not_found', v_pstn_enabled
        );

        RETURN QUERY SELECT
            false, 'customer_not_found', v_call_id, v_dst,
            NULL::TEXT, NULL::TEXT, NULL::TEXT,
            0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6),
            v_pstn_enabled;
        RETURN;
    END IF;

    SELECT *
    INTO v_blocked
    FROM billing.blocked_prefixes bp
    WHERE v_dst LIKE bp.prefix || '%'
    ORDER BY length(bp.prefix) DESC
    LIMIT 1;

    IF FOUND THEN
        INSERT INTO billing.routing_decisions(
            call_id, customer_code, src, dst, normalized_dst,
            route_allowed, route_reason, pstn_enabled
        )
        VALUES (
            v_call_id, p_customer_code, p_src, p_dst, v_dst,
            false, 'blocked_prefix_' || v_blocked.prefix, v_pstn_enabled
        );

        RETURN QUERY SELECT
            false, 'blocked_prefix_' || v_blocked.prefix, v_call_id, v_dst,
            NULL::TEXT, NULL::TEXT, NULL::TEXT,
            0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6),
            v_pstn_enabled;
        RETURN;
    END IF;

    SELECT *
    INTO v_sell
    FROM billing.rate_prefixes rp
    WHERE rp.enabled = true
      AND v_dst LIKE rp.prefix || '%'
    ORDER BY length(rp.prefix) DESC
    LIMIT 1;

    IF NOT FOUND THEN
        INSERT INTO billing.routing_decisions(
            call_id, customer_code, src, dst, normalized_dst,
            route_allowed, route_reason, pstn_enabled
        )
        VALUES (
            v_call_id, p_customer_code, p_src, p_dst, v_dst,
            false, 'no_sell_rate_found', v_pstn_enabled
        );

        RETURN QUERY SELECT
            false, 'no_sell_rate_found', v_call_id, v_dst,
            NULL::TEXT, NULL::TEXT, NULL::TEXT,
            0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6), 0.000000::NUMERIC(14,6),
            v_pstn_enabled;
        RETURN;
    END IF;

    SELECT
        pr.*,
        pa.name AS provider_name_value
    INTO v_route
    FROM billing.provider_routes pr
    JOIN billing.provider_accounts pa ON pa.code = pr.provider_code
    WHERE pr.enabled = true
      AND pa.enabled = true
      AND pa.status = 'sandbox'
      AND v_dst LIKE pr.prefix || '%'
    ORDER BY length(pr.prefix) DESC, pr.priority ASC, pr.buy_rate_per_min ASC
    LIMIT 1;

    IF NOT FOUND THEN
        INSERT INTO billing.routing_decisions(
            call_id, customer_code, src, dst, normalized_dst,
            route_allowed, route_reason, destination, sell_rate_per_min, pstn_enabled
        )
        VALUES (
            v_call_id, p_customer_code, p_src, p_dst, v_dst,
            false, 'no_provider_route_found', v_sell.destination, v_sell.rate_per_min, v_pstn_enabled
        );

        RETURN QUERY SELECT
            false, 'no_provider_route_found', v_call_id, v_dst,
            NULL::TEXT, NULL::TEXT, v_sell.destination,
            v_sell.rate_per_min::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            0.000000::NUMERIC(14,6),
            v_pstn_enabled;
        RETURN;
    END IF;

    v_est_sell := (
        v_sell.setup_fee +
        (
            CEIL(GREATEST(v_sell.minimum_sec, 1)::NUMERIC / v_sell.increment_sec::NUMERIC)
            * v_sell.increment_sec::NUMERIC
            / 60::NUMERIC
            * v_sell.rate_per_min
        )
    )::NUMERIC(14,6);

    v_est_buy := (
        v_route.setup_fee +
        (
            CEIL(GREATEST(v_route.minimum_sec, 1)::NUMERIC / v_route.increment_sec::NUMERIC)
            * v_route.increment_sec::NUMERIC
            / 60::NUMERIC
            * v_route.buy_rate_per_min
        )
    )::NUMERIC(14,6);

    v_margin_per_min := (v_sell.rate_per_min - v_route.buy_rate_per_min)::NUMERIC(14,6);
    v_est_margin := (v_est_sell - v_est_buy)::NUMERIC(14,6);

    IF v_pstn_enabled = false THEN
        INSERT INTO billing.routing_decisions(
            call_id, customer_code, src, dst, normalized_dst,
            selected_provider_code, route_allowed, route_reason,
            destination, sell_rate_per_min, buy_rate_per_min,
            margin_per_min, estimated_sell_cost, estimated_buy_cost,
            estimated_margin, pstn_enabled
        )
        VALUES (
            v_call_id, p_customer_code, p_src, p_dst, v_dst,
            v_route.provider_code, false, 'pstn_disabled_sandbox_route_found',
            v_route.destination, v_sell.rate_per_min, v_route.buy_rate_per_min,
            v_margin_per_min, v_est_sell, v_est_buy,
            v_est_margin, v_pstn_enabled
        );

        RETURN QUERY SELECT
            false,
            'pstn_disabled_sandbox_route_found',
            v_call_id,
            v_dst,
            v_route.provider_code,
            v_route.provider_name_value,
            v_route.destination,
            v_sell.rate_per_min::NUMERIC(14,6),
            v_route.buy_rate_per_min::NUMERIC(14,6),
            v_margin_per_min,
            v_est_sell,
            v_est_buy,
            v_est_margin,
            v_pstn_enabled;
        RETURN;
    END IF;

    INSERT INTO billing.routing_decisions(
        call_id, customer_code, src, dst, normalized_dst,
        selected_provider_code, route_allowed, route_reason,
        destination, sell_rate_per_min, buy_rate_per_min,
        margin_per_min, estimated_sell_cost, estimated_buy_cost,
        estimated_margin, pstn_enabled
    )
    VALUES (
        v_call_id, p_customer_code, p_src, p_dst, v_dst,
        v_route.provider_code, true, 'provider_route_selected',
        v_route.destination, v_sell.rate_per_min, v_route.buy_rate_per_min,
        v_margin_per_min, v_est_sell, v_est_buy,
        v_est_margin, v_pstn_enabled
    );

    RETURN QUERY SELECT
        true,
        'provider_route_selected',
        v_call_id,
        v_dst,
        v_route.provider_code,
        v_route.provider_name_value,
        v_route.destination,
        v_sell.rate_per_min::NUMERIC(14,6),
        v_route.buy_rate_per_min::NUMERIC(14,6),
        v_margin_per_min,
        v_est_sell,
        v_est_buy,
        v_est_margin,
        v_pstn_enabled;
END;
$$;
