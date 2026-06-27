CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.sip_accounts (
    username TEXT PRIMARY KEY,
    customer_code TEXT NOT NULL REFERENCES billing.customers(code),
    display_name TEXT,
    auth_password TEXT NOT NULL,
    realm TEXT NOT NULL DEFAULT 'knvox.local',
    enabled BOOLEAN NOT NULL DEFAULT true,
    cps_limit INTEGER NOT NULL DEFAULT 1,
    max_concurrent_calls INTEGER NOT NULL DEFAULT 2,
    allowed_ip_cidr TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sip_accounts_customer
ON billing.sip_accounts(customer_code);

CREATE TABLE IF NOT EXISTS billing.sip_account_events (
    id BIGSERIAL PRIMARY KEY,
    username TEXT,
    customer_code TEXT,
    event_type TEXT NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sip_account_events_created
ON billing.sip_account_events(created_at DESC);

CREATE OR REPLACE FUNCTION billing.upsert_sip_account(
    p_username TEXT,
    p_customer_code TEXT,
    p_display_name TEXT,
    p_auth_password TEXT,
    p_realm TEXT DEFAULT 'knvox.local',
    p_enabled BOOLEAN DEFAULT true,
    p_cps_limit INTEGER DEFAULT 1,
    p_max_concurrent_calls INTEGER DEFAULT 2,
    p_allowed_ip_cidr TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS TABLE (
    username TEXT,
    customer_code TEXT,
    display_name TEXT,
    realm TEXT,
    enabled BOOLEAN,
    cps_limit INTEGER,
    max_concurrent_calls INTEGER,
    allowed_ip_cidr TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM billing.customers c
        WHERE c.code = p_customer_code
    ) THEN
        RAISE EXCEPTION 'Customer not found: %', p_customer_code;
    END IF;

    UPDATE billing.sip_accounts sa
    SET
        customer_code = p_customer_code,
        display_name = p_display_name,
        auth_password = p_auth_password,
        realm = COALESCE(NULLIF(p_realm, ''), 'knvox.local'),
        enabled = p_enabled,
        cps_limit = p_cps_limit,
        max_concurrent_calls = p_max_concurrent_calls,
        allowed_ip_cidr = p_allowed_ip_cidr,
        notes = p_notes,
        updated_at = now()
    WHERE sa.username = p_username;

    IF NOT FOUND THEN
        INSERT INTO billing.sip_accounts(
            username,
            customer_code,
            display_name,
            auth_password,
            realm,
            enabled,
            cps_limit,
            max_concurrent_calls,
            allowed_ip_cidr,
            notes
        )
        VALUES (
            p_username,
            p_customer_code,
            p_display_name,
            p_auth_password,
            COALESCE(NULLIF(p_realm, ''), 'knvox.local'),
            p_enabled,
            p_cps_limit,
            p_max_concurrent_calls,
            p_allowed_ip_cidr,
            p_notes
        );
    END IF;

    INSERT INTO billing.sip_account_events(username, customer_code, event_type, details)
    VALUES (
        p_username,
        p_customer_code,
        'sip_account_upsert',
        jsonb_build_object(
            'display_name', p_display_name,
            'realm', COALESCE(NULLIF(p_realm, ''), 'knvox.local'),
            'enabled', p_enabled,
            'cps_limit', p_cps_limit,
            'max_concurrent_calls', p_max_concurrent_calls,
            'allowed_ip_cidr', p_allowed_ip_cidr
        )
    );

    RETURN QUERY
    SELECT
        sa.username,
        sa.customer_code,
        sa.display_name,
        sa.realm,
        sa.enabled,
        sa.cps_limit,
        sa.max_concurrent_calls,
        sa.allowed_ip_cidr,
        sa.notes,
        sa.created_at,
        sa.updated_at
    FROM billing.sip_accounts sa
    WHERE sa.username = p_username;
END;
$$;

CREATE OR REPLACE FUNCTION billing.set_sip_account_status(
    p_username TEXT,
    p_enabled BOOLEAN
)
RETURNS TABLE (
    username TEXT,
    customer_code TEXT,
    enabled BOOLEAN,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE billing.sip_accounts sa
    SET
        enabled = p_enabled,
        updated_at = now()
    WHERE sa.username = p_username;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SIP account not found: %', p_username;
    END IF;

    INSERT INTO billing.sip_account_events(username, customer_code, event_type, details)
    SELECT
        sa.username,
        sa.customer_code,
        'sip_account_status_update',
        jsonb_build_object('enabled', p_enabled)
    FROM billing.sip_accounts sa
    WHERE sa.username = p_username;

    RETURN QUERY
    SELECT
        sa.username,
        sa.customer_code,
        sa.enabled,
        sa.updated_at
    FROM billing.sip_accounts sa
    WHERE sa.username = p_username;
END;
$$;
