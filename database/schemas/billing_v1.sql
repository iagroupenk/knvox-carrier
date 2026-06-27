CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    currency TEXT NOT NULL DEFAULT 'EUR',
    prepaid_balance NUMERIC(14,6) NOT NULL DEFAULT 0,
    credit_limit NUMERIC(14,6) NOT NULL DEFAULT 0,
    max_concurrent_calls INTEGER NOT NULL DEFAULT 2,
    cps_limit INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'inactive',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.rate_decks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'EUR',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.rate_prefixes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deck_code TEXT NOT NULL REFERENCES billing.rate_decks(code) ON DELETE CASCADE,
    prefix TEXT NOT NULL,
    destination TEXT NOT NULL,
    rate_per_min NUMERIC(14,6) NOT NULL,
    setup_fee NUMERIC(14,6) NOT NULL DEFAULT 0,
    minimum_sec INTEGER NOT NULL DEFAULT 1,
    increment_sec INTEGER NOT NULL DEFAULT 1,
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(deck_code, prefix)
);

CREATE TABLE IF NOT EXISTS billing.blocked_prefixes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prefix TEXT UNIQUE NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.cdrs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id TEXT UNIQUE NOT NULL,
    customer_code TEXT REFERENCES billing.customers(code),
    src TEXT,
    dst TEXT NOT NULL,
    destination TEXT,
    duration_sec INTEGER NOT NULL DEFAULT 0,
    rate_per_min NUMERIC(14,6) NOT NULL DEFAULT 0,
    cost NUMERIC(14,6) NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'EUR',
    status TEXT NOT NULL DEFAULT 'rated',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_code TEXT NOT NULL REFERENCES billing.customers(code),
    amount NUMERIC(14,6) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'EUR',
    type TEXT NOT NULL,
    reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_billing_cdrs_customer ON billing.cdrs(customer_code);
CREATE INDEX IF NOT EXISTS idx_billing_cdrs_started_at ON billing.cdrs(started_at);
CREATE INDEX IF NOT EXISTS idx_billing_rate_prefixes_prefix ON billing.rate_prefixes(prefix);
