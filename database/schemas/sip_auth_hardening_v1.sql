CREATE OR REPLACE FUNCTION billing.set_sip_allowed_ip(
    p_username TEXT,
    p_allowed_ip_cidr TEXT
)
RETURNS TABLE (
    username TEXT,
    customer_code TEXT,
    enabled BOOLEAN,
    allowed_ip_cidr TEXT,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_allowed_ip_cidr IS NOT NULL AND trim(p_allowed_ip_cidr) <> '' THEN
        PERFORM p_allowed_ip_cidr::cidr;
    END IF;

    UPDATE billing.sip_accounts sa
    SET allowed_ip_cidr = NULLIF(trim(p_allowed_ip_cidr), ''),
        updated_at = now()
    WHERE sa.username = p_username;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SIP account not found: %', p_username;
    END IF;

    RETURN QUERY
    SELECT sa.username, sa.customer_code, sa.enabled, sa.allowed_ip_cidr, sa.updated_at
    FROM billing.sip_accounts sa
    WHERE sa.username = p_username;
END;
$$;

CREATE OR REPLACE FUNCTION billing.clear_sip_allowed_ip(
    p_username TEXT
)
RETURNS TABLE (
    username TEXT,
    customer_code TEXT,
    enabled BOOLEAN,
    allowed_ip_cidr TEXT,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM billing.set_sip_allowed_ip(p_username, NULL);
END;
$$;
