CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.pstn_safety_events (
    id BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO billing.system_settings(key, value)
VALUES ('pstn_enabled', 'false')
ON CONFLICT (key) DO UPDATE SET value = 'false';

INSERT INTO billing.pstn_safety_events(event_type, details)
VALUES ('pstn_safety_installed', jsonb_build_object('pstn_enabled', false));
