CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.invoice_exports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_code TEXT NOT NULL REFERENCES billing.customers(code),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    total_calls BIGINT NOT NULL DEFAULT 0,
    billable_calls BIGINT NOT NULL DEFAULT 0,
    total_duration_sec BIGINT NOT NULL DEFAULT 0,
    total_cost NUMERIC(14,6) NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'EUR',
    status TEXT NOT NULL DEFAULT 'generated',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoice_exports_customer_created
ON billing.invoice_exports(customer_code, created_at DESC);

CREATE OR REPLACE FUNCTION billing.customer_usage_summary(
    p_customer_code TEXT,
    p_date_from DATE,
    p_date_to DATE
)
RETURNS TABLE (
    customer_code TEXT,
    period_start DATE,
    period_end DATE,
    total_calls BIGINT,
    billable_calls BIGINT,
    total_duration_sec BIGINT,
    total_cost NUMERIC(14,6),
    average_cost_per_call NUMERIC(14,6),
    currency TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p_customer_code,
        p_date_from,
        p_date_to,
        COUNT(c.*)::BIGINT AS total_calls,
        COUNT(*) FILTER (WHERE COALESCE(c.cost, 0) > 0)::BIGINT AS billable_calls,
        COALESCE(SUM(c.duration_sec), 0)::BIGINT AS total_duration_sec,
        COALESCE(SUM(c.cost), 0)::NUMERIC(14,6) AS total_cost,
        CASE
            WHEN COUNT(c.*) > 0 THEN (COALESCE(SUM(c.cost), 0) / COUNT(c.*))::NUMERIC(14,6)
            ELSE 0::NUMERIC(14,6)
        END AS average_cost_per_call,
        COALESCE(MAX(c.currency), 'EUR') AS currency
    FROM billing.cdrs c
    WHERE c.customer_code = p_customer_code
      AND c.created_at >= p_date_from::TIMESTAMPTZ
      AND c.created_at < (p_date_to + 1)::TIMESTAMPTZ;
END;
$$;

CREATE OR REPLACE FUNCTION billing.customer_margin_summary(
    p_customer_code TEXT,
    p_date_from DATE,
    p_date_to DATE
)
RETURNS TABLE (
    customer_code TEXT,
    period_start DATE,
    period_end DATE,
    total_calls BIGINT,
    total_revenue NUMERIC(14,6),
    estimated_buy_cost NUMERIC(14,6),
    estimated_margin NUMERIC(14,6),
    estimated_margin_percent NUMERIC(14,6)
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p_customer_code,
        p_date_from,
        p_date_to,
        COUNT(c.*)::BIGINT AS total_calls,
        COALESCE(SUM(c.cost), 0)::NUMERIC(14,6) AS total_revenue,
        COALESCE(SUM(rd.estimated_buy_cost), 0)::NUMERIC(14,6) AS estimated_buy_cost,
        (COALESCE(SUM(c.cost), 0) - COALESCE(SUM(rd.estimated_buy_cost), 0))::NUMERIC(14,6) AS estimated_margin,
        CASE
            WHEN COALESCE(SUM(c.cost), 0) > 0 THEN
                (((COALESCE(SUM(c.cost), 0) - COALESCE(SUM(rd.estimated_buy_cost), 0)) / COALESCE(SUM(c.cost), 0)) * 100)::NUMERIC(14,6)
            ELSE 0::NUMERIC(14,6)
        END AS estimated_margin_percent
    FROM billing.cdrs c
    LEFT JOIN LATERAL (
        SELECT r.estimated_buy_cost
        FROM billing.routing_decisions r
        WHERE r.call_id = c.call_id
        ORDER BY r.created_at DESC
        LIMIT 1
    ) rd ON true
    WHERE c.customer_code = p_customer_code
      AND c.created_at >= p_date_from::TIMESTAMPTZ
      AND c.created_at < (p_date_to + 1)::TIMESTAMPTZ;
END;
$$;

CREATE OR REPLACE FUNCTION billing.create_invoice_export(
    p_customer_code TEXT,
    p_date_from DATE,
    p_date_to DATE
)
RETURNS TABLE (
    export_id UUID,
    customer_code TEXT,
    period_start DATE,
    period_end DATE,
    total_calls BIGINT,
    billable_calls BIGINT,
    total_duration_sec BIGINT,
    total_cost NUMERIC(14,6),
    currency TEXT,
    status TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_usage RECORD;
    v_export_id UUID;
BEGIN
    SELECT *
    INTO v_usage
    FROM billing.customer_usage_summary(p_customer_code, p_date_from, p_date_to);

    INSERT INTO billing.invoice_exports(
        customer_code,
        period_start,
        period_end,
        total_calls,
        billable_calls,
        total_duration_sec,
        total_cost,
        currency,
        status
    )
    VALUES (
        p_customer_code,
        p_date_from,
        p_date_to,
        v_usage.total_calls,
        v_usage.billable_calls,
        v_usage.total_duration_sec,
        v_usage.total_cost,
        v_usage.currency,
        'generated'
    )
    RETURNING id INTO v_export_id;

    RETURN QUERY
    SELECT
        v_export_id,
        p_customer_code,
        p_date_from,
        p_date_to,
        v_usage.total_calls,
        v_usage.billable_calls,
        v_usage.total_duration_sec,
        v_usage.total_cost,
        v_usage.currency,
        'generated'::TEXT;
END;
$$;
