CREATE SCHEMA IF NOT EXISTS billing;

INSERT INTO billing.sip_accounts(
    username,
    customer_code,
    display_name,
    auth_password,
    realm,
    enabled,
    cps_limit,
    max_concurrent_calls,
    notes
)
SELECT
    '1000',
    'TEST1000',
    'Default TEST1000 SIP 1000',
    'managed-by-freeswitch',
    'knvox.local',
    true,
    1,
    2,
    'Compte bootstrap pour compatibilité Kamailio multi-client'
WHERE EXISTS (
    SELECT 1 FROM billing.customers WHERE code = 'TEST1000'
)
ON CONFLICT (username) DO UPDATE SET
    customer_code = EXCLUDED.customer_code,
    display_name = EXCLUDED.display_name,
    enabled = true,
    realm = EXCLUDED.realm,
    cps_limit = EXCLUDED.cps_limit,
    max_concurrent_calls = EXCLUDED.max_concurrent_calls,
    notes = EXCLUDED.notes,
    updated_at = now();

CREATE OR REPLACE FUNCTION billing.resolve_sip_account_for_call(
    p_username TEXT,
    p_source_ip TEXT DEFAULT NULL
)
RETURNS TABLE (
    resolved_username TEXT,
    customer_code TEXT,
    allowed BOOLEAN,
    reason TEXT,
    account_enabled BOOLEAN,
    customer_status TEXT,
    allowed_ip_cidr TEXT,
    cps_limit INTEGER,
    max_concurrent_calls INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_account RECORD;
    v_customer RECORD;
BEGIN
    SELECT *
    INTO v_account
    FROM billing.sip_accounts sa
    WHERE sa.username = p_username;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            p_username,
            NULL::TEXT,
            false,
            'sip_account_not_found',
            false,
            NULL::TEXT,
            NULL::TEXT,
            0::INTEGER,
            0::INTEGER;
        RETURN;
    END IF;

    IF v_account.enabled = false THEN
        RETURN QUERY SELECT
            v_account.username,
            v_account.customer_code,
            false,
            'sip_account_disabled',
            false,
            NULL::TEXT,
            v_account.allowed_ip_cidr,
            v_account.cps_limit,
            v_account.max_concurrent_calls;
        RETURN;
    END IF;

    SELECT *
    INTO v_customer
    FROM billing.customers c
    WHERE c.code = v_account.customer_code;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            v_account.username,
            v_account.customer_code,
            false,
            'customer_not_found',
            v_account.enabled,
            NULL::TEXT,
            v_account.allowed_ip_cidr,
            v_account.cps_limit,
            v_account.max_concurrent_calls;
        RETURN;
    END IF;

    IF v_customer.status <> 'active' THEN
        RETURN QUERY SELECT
            v_account.username,
            v_account.customer_code,
            false,
            'customer_' || v_customer.status,
            v_account.enabled,
            v_customer.status,
            v_account.allowed_ip_cidr,
            v_account.cps_limit,
            v_account.max_concurrent_calls;
        RETURN;
    END IF;

    IF v_account.allowed_ip_cidr IS NOT NULL AND trim(v_account.allowed_ip_cidr) <> '' THEN
        BEGIN
            IF p_source_ip IS NULL OR trim(p_source_ip) = '' OR NOT (p_source_ip::inet <<= v_account.allowed_ip_cidr::cidr) THEN
                RETURN QUERY SELECT
                    v_account.username,
                    v_account.customer_code,
                    false,
                    'source_ip_not_allowed',
                    v_account.enabled,
                    v_customer.status,
                    v_account.allowed_ip_cidr,
                    v_account.cps_limit,
                    v_account.max_concurrent_calls;
                RETURN;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT
                v_account.username,
                v_account.customer_code,
                false,
                'invalid_source_ip_or_cidr',
                v_account.enabled,
                v_customer.status,
                v_account.allowed_ip_cidr,
                v_account.cps_limit,
                v_account.max_concurrent_calls;
            RETURN;
        END;
    END IF;

    RETURN QUERY SELECT
        v_account.username,
        v_account.customer_code,
        true,
        'sip_account_resolved',
        v_account.enabled,
        v_customer.status,
        v_account.allowed_ip_cidr,
        v_account.cps_limit,
        v_account.max_concurrent_calls;
END;
$$;
