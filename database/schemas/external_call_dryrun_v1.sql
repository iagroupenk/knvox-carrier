CREATE TABLE IF NOT EXISTS billing.external_call_dry_run_events (
    id BIGSERIAL PRIMARY KEY,
    customer_code TEXT,
    src TEXT,
    dst TEXT,
    call_id TEXT,
    selected_provider_code TEXT,
    route_allowed BOOLEAN,
    route_reason TEXT,
    pstn_enabled BOOLEAN,
    request JSONB NOT NULL DEFAULT '{}'::jsonb,
    response JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO billing.system_settings(key, value)
VALUES ('pstn_enabled', 'false')
ON CONFLICT (key) DO UPDATE SET value = 'false';
