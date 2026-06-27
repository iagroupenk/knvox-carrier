CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.rate_admin_events (
    id BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    prefix TEXT,
    provider_code TEXT,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rate_admin_events_created
ON billing.rate_admin_events(created_at DESC);

DELETE FROM billing.blocked_prefixes b
USING billing.blocked_prefixes b2
WHERE b.ctid < b2.ctid
  AND b.prefix = b2.prefix;

CREATE UNIQUE INDEX IF NOT EXISTS idx_blocked_prefixes_unique_prefix
ON billing.blocked_prefixes(prefix);

CREATE OR REPLACE FUNCTION billing.upsert_sell_rate(
    p_prefix TEXT,
    p_destination TEXT,
    p_rate_per_min NUMERIC,
    p_setup_fee NUMERIC DEFAULT 0,
    p_minimum_sec INTEGER DEFAULT 1,
    p_increment_sec INTEGER DEFAULT 1,
    p_enabled BOOLEAN DEFAULT true
)
RETURNS TABLE (
    prefix TEXT,
    destination TEXT,
    rate_per_min NUMERIC(14,6),
    setup_fee NUMERIC(14,6),
    minimum_sec INTEGER,
    increment_sec INTEGER,
    enabled BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_deck_id INTEGER;
    v_has_rate_deck_id BOOLEAN;
BEGIN
    UPDATE billing.rate_prefixes rp
    SET
        destination = p_destination,
        rate_per_min = p_rate_per_min,
        setup_fee = p_setup_fee,
        minimum_sec = p_minimum_sec,
        increment_sec = p_increment_sec,
        enabled = p_enabled
    WHERE rp.prefix = p_prefix;

    IF NOT FOUND THEN
        SELECT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'billing'
              AND table_name = 'rate_prefixes'
              AND column_name = 'rate_deck_id'
        )
        INTO v_has_rate_deck_id;

        IF v_has_rate_deck_id THEN
            SELECT id INTO v_deck_id
            FROM billing.rate_decks
            ORDER BY id
            LIMIT 1;

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
                p_prefix,
                p_destination,
                p_rate_per_min,
                p_setup_fee,
                p_minimum_sec,
                p_increment_sec,
                p_enabled
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
                p_prefix,
                p_destination,
                p_rate_per_min,
                p_setup_fee,
                p_minimum_sec,
                p_increment_sec,
                p_enabled
            );
        END IF;
    END IF;

    INSERT INTO billing.rate_admin_events(event_type, prefix, details)
    VALUES (
        'sell_rate_upsert',
        p_prefix,
        jsonb_build_object(
            'destination', p_destination,
            'rate_per_min', p_rate_per_min,
            'setup_fee', p_setup_fee,
            'minimum_sec', p_minimum_sec,
            'increment_sec', p_increment_sec,
            'enabled', p_enabled
        )
    );

    RETURN QUERY
    SELECT
        rp.prefix,
        rp.destination,
        rp.rate_per_min,
        rp.setup_fee,
        rp.minimum_sec,
        rp.increment_sec,
        rp.enabled
    FROM billing.rate_prefixes rp
    WHERE rp.prefix = p_prefix
    ORDER BY rp.id DESC
    LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION billing.disable_sell_rate(p_prefix TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE billing.rate_prefixes
    SET enabled = false
    WHERE prefix = p_prefix;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    INSERT INTO billing.rate_admin_events(event_type, prefix, details)
    VALUES ('sell_rate_disable', p_prefix, jsonb_build_object('updated_rows', v_count));

    RETURN v_count > 0;
END;
$$;

CREATE OR REPLACE FUNCTION billing.upsert_blocked_prefix(
    p_prefix TEXT,
    p_reason TEXT
)
RETURNS TABLE (
    prefix TEXT,
    reason TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO billing.blocked_prefixes(prefix, reason)
    VALUES (p_prefix, p_reason)
    ON CONFLICT (prefix) DO UPDATE SET
        reason = EXCLUDED.reason;

    INSERT INTO billing.rate_admin_events(event_type, prefix, details)
    VALUES ('blocked_prefix_upsert', p_prefix, jsonb_build_object('reason', p_reason));

    RETURN QUERY
    SELECT bp.prefix, bp.reason
    FROM billing.blocked_prefixes bp
    WHERE bp.prefix = p_prefix;
END;
$$;

CREATE OR REPLACE FUNCTION billing.delete_blocked_prefix(p_prefix TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM billing.blocked_prefixes
    WHERE prefix = p_prefix;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    INSERT INTO billing.rate_admin_events(event_type, prefix, details)
    VALUES ('blocked_prefix_delete', p_prefix, jsonb_build_object('deleted_rows', v_count));

    RETURN v_count > 0;
END;
$$;

CREATE OR REPLACE FUNCTION billing.upsert_provider_route_admin(
    p_provider_code TEXT,
    p_prefix TEXT,
    p_destination TEXT,
    p_buy_rate_per_min NUMERIC,
    p_setup_fee NUMERIC DEFAULT 0,
    p_minimum_sec INTEGER DEFAULT 1,
    p_increment_sec INTEGER DEFAULT 1,
    p_enabled BOOLEAN DEFAULT true,
    p_priority INTEGER DEFAULT 100
)
RETURNS TABLE (
    provider_code TEXT,
    prefix TEXT,
    destination TEXT,
    buy_rate_per_min NUMERIC(14,6),
    setup_fee NUMERIC(14,6),
    minimum_sec INTEGER,
    increment_sec INTEGER,
    enabled BOOLEAN,
    priority INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM billing.provider_accounts pa WHERE pa.code = p_provider_code) THEN
        INSERT INTO billing.provider_accounts(code, name, status, enabled, trunk_enabled, priority, notes)
        VALUES (
            p_provider_code,
            p_provider_code,
            'sandbox',
            true,
            false,
            p_priority,
            'Créé automatiquement par Rate Admin API - sandbox uniquement'
        );
    END IF;

    INSERT INTO billing.provider_routes(
        provider_code,
        prefix,
        destination,
        buy_rate_per_min,
        setup_fee,
        minimum_sec,
        increment_sec,
        enabled,
        priority
    )
    VALUES (
        p_provider_code,
        p_prefix,
        p_destination,
        p_buy_rate_per_min,
        p_setup_fee,
        p_minimum_sec,
        p_increment_sec,
        p_enabled,
        p_priority
    )
    ON CONFLICT (provider_code, prefix) DO UPDATE SET
        destination = EXCLUDED.destination,
        buy_rate_per_min = EXCLUDED.buy_rate_per_min,
        setup_fee = EXCLUDED.setup_fee,
        minimum_sec = EXCLUDED.minimum_sec,
        increment_sec = EXCLUDED.increment_sec,
        enabled = EXCLUDED.enabled,
        priority = EXCLUDED.priority;

    INSERT INTO billing.rate_admin_events(event_type, prefix, provider_code, details)
    VALUES (
        'provider_route_upsert',
        p_prefix,
        p_provider_code,
        jsonb_build_object(
            'destination', p_destination,
            'buy_rate_per_min', p_buy_rate_per_min,
            'enabled', p_enabled,
            'priority', p_priority
        )
    );

    RETURN QUERY
    SELECT
        pr.provider_code,
        pr.prefix,
        pr.destination,
        pr.buy_rate_per_min,
        pr.setup_fee,
        pr.minimum_sec,
        pr.increment_sec,
        pr.enabled,
        pr.priority
    FROM billing.provider_routes pr
    WHERE pr.provider_code = p_provider_code
      AND pr.prefix = p_prefix;
END;
$$;
