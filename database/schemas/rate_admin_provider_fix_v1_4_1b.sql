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
    IF NOT EXISTS (
        SELECT 1
        FROM billing.provider_accounts pa
        WHERE pa.code = p_provider_code
    ) THEN
        INSERT INTO billing.provider_accounts(
            code,
            name,
            status,
            enabled,
            trunk_enabled,
            priority,
            cps_limit,
            max_concurrent_calls,
            notes
        )
        VALUES (
            p_provider_code,
            p_provider_code,
            'sandbox',
            true,
            false,
            p_priority,
            10,
            100,
            'Créé automatiquement par Rate Admin API - sandbox uniquement'
        );
    ELSE
        UPDATE billing.provider_accounts pa
        SET
            enabled = true,
            trunk_enabled = false,
            status = 'sandbox',
            updated_at = now()
        WHERE pa.code = p_provider_code;
    END IF;

    UPDATE billing.provider_routes pr
    SET
        destination = p_destination,
        buy_rate_per_min = p_buy_rate_per_min,
        setup_fee = p_setup_fee,
        minimum_sec = p_minimum_sec,
        increment_sec = p_increment_sec,
        enabled = p_enabled,
        priority = p_priority
    WHERE pr.provider_code = p_provider_code
      AND pr.prefix = p_prefix;

    IF NOT FOUND THEN
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
        );
    END IF;

    INSERT INTO billing.rate_admin_events(event_type, prefix, provider_code, details)
    VALUES (
        'provider_route_upsert',
        p_prefix,
        p_provider_code,
        jsonb_build_object(
            'destination', p_destination,
            'buy_rate_per_min', p_buy_rate_per_min,
            'setup_fee', p_setup_fee,
            'minimum_sec', p_minimum_sec,
            'increment_sec', p_increment_sec,
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
      AND pr.prefix = p_prefix
    ORDER BY pr.id DESC
    LIMIT 1;
END;
$$;
