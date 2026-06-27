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
    UPDATE billing.blocked_prefixes bp
    SET reason = p_reason
    WHERE bp.prefix = p_prefix;

    IF NOT FOUND THEN
        INSERT INTO billing.blocked_prefixes(
            prefix,
            reason
        )
        VALUES (
            p_prefix,
            p_reason
        );
    END IF;

    INSERT INTO billing.rate_admin_events(event_type, prefix, details)
    VALUES (
        'blocked_prefix_upsert',
        p_prefix,
        jsonb_build_object('reason', p_reason)
    );

    RETURN QUERY
    SELECT
        bp.prefix,
        bp.reason
    FROM billing.blocked_prefixes bp
    WHERE bp.prefix = p_prefix
    LIMIT 1;
END;
$$;
