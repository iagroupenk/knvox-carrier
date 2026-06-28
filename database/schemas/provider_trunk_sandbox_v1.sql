CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.provider_trunks (
    provider_code TEXT PRIMARY KEY,
    trunk_name TEXT NOT NULL,
    sip_host TEXT NOT NULL,
    sip_port INTEGER NOT NULL DEFAULT 5060,
    transport TEXT NOT NULL DEFAULT 'udp',
    auth_username TEXT,
    auth_password TEXT,
    from_domain TEXT,
    register BOOLEAN NOT NULL DEFAULT false,
    enabled BOOLEAN NOT NULL DEFAULT false,
    sandbox_only BOOLEAN NOT NULL DEFAULT true,
    max_cps INTEGER NOT NULL DEFAULT 1,
    max_concurrent_calls INTEGER NOT NULL DEFAULT 2,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.provider_trunk_events (
    id BIGSERIAL PRIMARY KEY,
    provider_code TEXT,
    event_type TEXT NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION billing.upsert_provider_trunk(
    p_provider_code TEXT,
    p_trunk_name TEXT,
    p_sip_host TEXT,
    p_sip_port INTEGER DEFAULT 5060,
    p_transport TEXT DEFAULT 'udp',
    p_auth_username TEXT DEFAULT NULL,
    p_auth_password TEXT DEFAULT NULL,
    p_from_domain TEXT DEFAULT NULL,
    p_register BOOLEAN DEFAULT false,
    p_enabled BOOLEAN DEFAULT false,
    p_sandbox_only BOOLEAN DEFAULT true,
    p_max_cps INTEGER DEFAULT 1,
    p_max_concurrent_calls INTEGER DEFAULT 2,
    p_notes TEXT DEFAULT NULL
)
RETURNS TABLE (
    provider_code TEXT,
    trunk_name TEXT,
    sip_host TEXT,
    sip_port INTEGER,
    transport TEXT,
    register BOOLEAN,
    enabled BOOLEAN,
    sandbox_only BOOLEAN,
    max_cps INTEGER,
    max_concurrent_calls INTEGER,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE billing.provider_trunks pt
    SET
        trunk_name = p_trunk_name,
        sip_host = p_sip_host,
        sip_port = p_sip_port,
        transport = lower(p_transport),
        auth_username = p_auth_username,
        auth_password = p_auth_password,
        from_domain = p_from_domain,
        register = p_register,
        enabled = p_enabled,
        sandbox_only = p_sandbox_only,
        max_cps = p_max_cps,
        max_concurrent_calls = p_max_concurrent_calls,
        notes = p_notes,
        updated_at = now()
    WHERE pt.provider_code = p_provider_code;

    IF NOT FOUND THEN
        INSERT INTO billing.provider_trunks(
            provider_code,
            trunk_name,
            sip_host,
            sip_port,
            transport,
            auth_username,
            auth_password,
            from_domain,
            register,
            enabled,
            sandbox_only,
            max_cps,
            max_concurrent_calls,
            notes
        )
        VALUES (
            p_provider_code,
            p_trunk_name,
            p_sip_host,
            p_sip_port,
            lower(p_transport),
            p_auth_username,
            p_auth_password,
            p_from_domain,
            p_register,
            p_enabled,
            p_sandbox_only,
            p_max_cps,
            p_max_concurrent_calls,
            p_notes
        );
    END IF;

    INSERT INTO billing.provider_trunk_events(provider_code, event_type, details)
    VALUES (
        p_provider_code,
        'provider_trunk_upsert',
        jsonb_build_object(
            'sip_host', p_sip_host,
            'sip_port', p_sip_port,
            'transport', lower(p_transport),
            'register', p_register,
            'enabled', p_enabled,
            'sandbox_only', p_sandbox_only
        )
    );

    RETURN QUERY
    SELECT
        pt.provider_code,
        pt.trunk_name,
        pt.sip_host,
        pt.sip_port,
        pt.transport,
        pt.register,
        pt.enabled,
        pt.sandbox_only,
        pt.max_cps,
        pt.max_concurrent_calls,
        pt.updated_at
    FROM billing.provider_trunks pt
    WHERE pt.provider_code = p_provider_code;
END;
$$;

CREATE OR REPLACE FUNCTION billing.set_provider_trunk_status(
    p_provider_code TEXT,
    p_enabled BOOLEAN
)
RETURNS TABLE (
    provider_code TEXT,
    trunk_name TEXT,
    enabled BOOLEAN,
    sandbox_only BOOLEAN,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE billing.provider_trunks pt
    SET enabled = p_enabled,
        updated_at = now()
    WHERE pt.provider_code = p_provider_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Provider trunk not found: %', p_provider_code;
    END IF;

    INSERT INTO billing.provider_trunk_events(provider_code, event_type, details)
    VALUES (
        p_provider_code,
        'provider_trunk_status',
        jsonb_build_object('enabled', p_enabled)
    );

    RETURN QUERY
    SELECT
        pt.provider_code,
        pt.trunk_name,
        pt.enabled,
        pt.sandbox_only,
        pt.updated_at
    FROM billing.provider_trunks pt
    WHERE pt.provider_code = p_provider_code;
END;
$$;

SELECT billing.upsert_provider_trunk(
    'SIM-FR-1',
    'France Sandbox Provider',
    'sandbox.invalid',
    5060,
    'udp',
    NULL,
    NULL,
    'sandbox.invalid',
    false,
    false,
    true,
    1,
    2,
    'Sandbox only - no real SIP connection'
);

SELECT billing.upsert_provider_trunk(
    'SIM-WORLD-1',
    'World Sandbox Provider',
    'sandbox.invalid',
    5060,
    'udp',
    NULL,
    NULL,
    'sandbox.invalid',
    false,
    false,
    true,
    1,
    2,
    'Sandbox only - no real SIP connection'
);

SELECT billing.upsert_provider_trunk(
    'SIM-UK-1',
    'UK Sandbox Provider',
    'sandbox.invalid',
    5060,
    'udp',
    NULL,
    NULL,
    'sandbox.invalid',
    false,
    false,
    true,
    1,
    2,
    'Sandbox only - no real SIP connection'
);
