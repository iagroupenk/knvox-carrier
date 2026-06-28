ALTER TABLE billing.provider_trunks
ADD COLUMN IF NOT EXISTS credential_ref TEXT;

ALTER TABLE billing.provider_trunks
ADD COLUMN IF NOT EXISTS credentials_updated_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS billing.provider_credential_events (
    id BIGSERIAL PRIMARY KEY,
    provider_code TEXT,
    event_type TEXT NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION billing.set_provider_trunk_credential_ref(
    p_provider_code TEXT,
    p_credential_ref TEXT,
    p_auth_username TEXT DEFAULT NULL,
    p_from_domain TEXT DEFAULT NULL
)
RETURNS TABLE (
    provider_code TEXT,
    trunk_name TEXT,
    credential_ref TEXT,
    auth_username TEXT,
    from_domain TEXT,
    credentials_updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE billing.provider_trunks pt
    SET
        credential_ref = p_credential_ref,
        auth_username = NULLIF(p_auth_username, ''),
        auth_password = NULL,
        from_domain = COALESCE(NULLIF(p_from_domain, ''), pt.from_domain),
        credentials_updated_at = now(),
        updated_at = now()
    WHERE pt.provider_code = p_provider_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Provider trunk not found: %', p_provider_code;
    END IF;

    INSERT INTO billing.provider_credential_events(provider_code, event_type, details)
    VALUES (
        p_provider_code,
        'credential_ref_set',
        jsonb_build_object('credential_ref', p_credential_ref)
    );

    RETURN QUERY
    SELECT
        pt.provider_code,
        pt.trunk_name,
        pt.credential_ref,
        pt.auth_username,
        pt.from_domain,
        pt.credentials_updated_at
    FROM billing.provider_trunks pt
    WHERE pt.provider_code = p_provider_code;
END;
$$;
