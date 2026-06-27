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
    v_deck_code TEXT;
    v_has_deck_code BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'billing'
          AND table_name = 'rate_prefixes'
          AND column_name = 'deck_code'
    )
    INTO v_has_deck_code;

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

        IF v_has_deck_code THEN
            SELECT rp.deck_code
            INTO v_deck_code
            FROM billing.rate_prefixes rp
            WHERE rp.deck_code IS NOT NULL
            ORDER BY rp.created_at ASC
            LIMIT 1;

            IF v_deck_code IS NULL THEN
                SELECT rd.code
                INTO v_deck_code
                FROM billing.rate_decks rd
                ORDER BY rd.created_at ASC
                LIMIT 1;
            END IF;

            IF v_deck_code IS NULL THEN
                RAISE EXCEPTION 'No billing rate deck found for deck_code insert';
            END IF;

            INSERT INTO billing.rate_prefixes(
                deck_code,
                prefix,
                destination,
                rate_per_min,
                setup_fee,
                minimum_sec,
                increment_sec,
                enabled
            )
            VALUES (
                v_deck_code,
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
    ORDER BY rp.created_at DESC
    LIMIT 1;
END;
$$;
