import os
import csv
import io
import uuid
import secrets
from decimal import Decimal
from typing import Optional, Any, Dict, List

import psycopg2
import psycopg2.extras
from fastapi import FastAPI, Header, HTTPException, Query, Response
from pydantic import BaseModel, Field


APP_NAME = "KNVOX Billing Authorization API"


def get_env(name: str, default: Optional[str] = None) -> str:
    value = os.getenv(name, default)
    if value is None or value == "":
        raise RuntimeError(f"Missing environment variable: {name}")
    return value


def db_connect():
    return psycopg2.connect(
        host=get_env("POSTGRES_HOST", "postgres"),
        port=int(get_env("POSTGRES_PORT", "5432")),
        dbname=get_env("POSTGRES_DB"),
        user=get_env("POSTGRES_USER"),
        password=get_env("POSTGRES_PASSWORD"),
        cursor_factory=psycopg2.extras.RealDictCursor,
    )


def json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def row_to_json(row: Dict[str, Any]) -> Dict[str, Any]:
    return {key: json_safe(value) for key, value in row.items()}


def rows_to_json(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [row_to_json(dict(row)) for row in rows]


def require_api_key(x_knvox_api_key: Optional[str]) -> None:
    expected = get_env("BILLING_API_TOKEN")
    if not x_knvox_api_key or x_knvox_api_key != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")


class AuthorizeCallRequest(BaseModel):
    customer_code: str = Field(..., min_length=1, max_length=64)
    src: str = Field(..., min_length=1, max_length=64)
    dst: str = Field(..., min_length=1, max_length=64)
    call_id: Optional[str] = None


class EndCallRequest(BaseModel):
    call_id: str = Field(..., min_length=1, max_length=256)
    reason: Optional[str] = "normal"


class ProviderRouteSimulateRequest(BaseModel):
    customer_code: str = Field(..., min_length=1, max_length=64)
    src: str = Field(..., min_length=1, max_length=64)
    dst: str = Field(..., min_length=1, max_length=64)
    call_id: Optional[str] = None


class CustomerCreateRequest(BaseModel):
    code: str = Field(..., min_length=2, max_length=64)
    name: str = Field(..., min_length=2, max_length=255)
    currency: str = Field(default="EUR", min_length=3, max_length=3)
    prepaid_balance: float = 0.0
    cps_limit: int = 1
    max_concurrent_calls: int = 2
    daily_spend_limit: float = 20.0
    max_rate_per_min: float = 0.5
    max_call_duration_sec: int = 3600


class CustomerCreditRequest(BaseModel):
    amount: float = Field(..., gt=0)
    reference: Optional[str] = None
    note: Optional[str] = None


class CustomerLimitsRequest(BaseModel):
    cps_limit: Optional[int] = None
    max_concurrent_calls: Optional[int] = None
    daily_spend_limit: Optional[float] = None
    max_rate_per_min: Optional[float] = None
    max_call_duration_sec: Optional[int] = None


class CustomerStatusRequest(BaseModel):
    status: str = Field(..., pattern="^(active|suspended|closed)$")



class SellRateRequest(BaseModel):
    prefix: str = Field(..., min_length=1, max_length=32)
    destination: str = Field(..., min_length=2, max_length=255)
    rate_per_min: float = Field(..., ge=0)
    setup_fee: float = 0.0
    minimum_sec: int = 1
    increment_sec: int = 1
    enabled: bool = True


class BlockedPrefixRequest(BaseModel):
    prefix: str = Field(..., min_length=1, max_length=32)
    reason: str = Field(..., min_length=2, max_length=255)




class SipAccountRequest(BaseModel):
    username: str = Field(..., min_length=2, max_length=64)
    customer_code: str = Field(..., min_length=2, max_length=64)
    display_name: Optional[str] = None
    auth_password: Optional[str] = None
    realm: str = "knvox.local"
    enabled: bool = True
    cps_limit: int = 1
    max_concurrent_calls: int = 2
    allowed_ip_cidr: Optional[str] = None
    notes: Optional[str] = None


class SipAccountStatusRequest(BaseModel):
    enabled: bool


class InvoiceExportRequest(BaseModel):
    date_from: str = Field(..., min_length=10, max_length=10)
    date_to: str = Field(..., min_length=10, max_length=10)


class ProviderRouteAdminRequest(BaseModel):
    provider_code: str = Field(..., min_length=2, max_length=64)
    prefix: str = Field(..., min_length=1, max_length=32)
    destination: str = Field(..., min_length=2, max_length=255)
    buy_rate_per_min: float = Field(..., ge=0)
    setup_fee: float = 0.0
    minimum_sec: int = 1
    increment_sec: int = 1
    enabled: bool = True
    priority: int = 100


class FraudLockRequest(BaseModel):
    fraud_locked: bool


app = FastAPI(title=APP_NAME, version="1.5.0")


@app.get("/health")
def health():
    try:
        with db_connect() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1 AS ok;")
                row = cur.fetchone()
        return {"status": "ok", "database": row["ok"]}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc))


@app.post("/api/v1/authorize-call")
def authorize_call(payload: AuthorizeCallRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)
    call_id = payload.call_id or f"api-{uuid.uuid4()}"

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.authorize_call(%s, %s, %s, %s);",
                (payload.customer_code, payload.src, payload.dst, call_id),
            )
            row = cur.fetchone()
            conn.commit()

    result = row_to_json(dict(row))
    result["call_id"] = call_id
    return result


@app.post("/api/v1/start-call")
def start_call(payload: AuthorizeCallRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)
    call_id = payload.call_id or f"api-{uuid.uuid4()}"

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.start_call(%s, %s, %s, %s);",
                (payload.customer_code, payload.src, payload.dst, call_id),
            )
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.post("/api/v1/end-call")
def end_call(payload: EndCallRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.end_call(%s, %s);",
                (payload.call_id, payload.reason or "normal"),
            )
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.get("/api/v1/active-calls")
def active_calls(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT call_id, customer_code, src, dst, normalized_dst, started_at, last_seen_at
                FROM billing.active_calls
                ORDER BY started_at DESC;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.post("/api/v1/cleanup-active-calls")
def cleanup_active_calls(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT billing.cleanup_active_calls(360) AS cleaned;")
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.post("/api/v1/provider-route-simulate")
def provider_route_simulate(payload: ProviderRouteSimulateRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)
    call_id = payload.call_id or f"route-{uuid.uuid4()}"

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.provider_route_simulate(%s, %s, %s, %s);",
                (payload.customer_code, payload.src, payload.dst, call_id),
            )
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.get("/api/v1/provider-routes")
def provider_routes(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    pa.code AS provider_code,
                    pa.name AS provider_name,
                    pa.status,
                    pa.enabled,
                    pa.trunk_enabled,
                    pr.prefix,
                    pr.destination,
                    pr.buy_rate_per_min,
                    pr.minimum_sec,
                    pr.increment_sec,
                    pr.priority
                FROM billing.provider_accounts pa
                LEFT JOIN billing.provider_routes pr ON pr.provider_code = pa.code
                ORDER BY pa.priority ASC, pr.priority ASC, pr.prefix;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.get("/api/v1/customers")
def list_customers(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    code,
                    name,
                    status,
                    currency,
                    prepaid_balance,
                    cps_limit,
                    max_concurrent_calls,
                    fraud_locked,
                    daily_spend_limit,
                    max_rate_per_min,
                    max_call_duration_sec,
                    created_at,
                    updated_at
                FROM billing.customers
                ORDER BY code;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.post("/api/v1/customers")
def create_customer(payload: CustomerCreateRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO billing.customers(
                    code,
                    name,
                    status,
                    currency,
                    prepaid_balance,
                    max_concurrent_calls,
                    cps_limit,
                    fraud_locked,
                    daily_spend_limit,
                    max_rate_per_min,
                    max_call_duration_sec,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, 'active', %s, %s, %s, %s, false, %s, %s, %s, now(), now())
                ON CONFLICT (code) DO UPDATE SET
                    name = EXCLUDED.name,
                    status = 'active',
                    currency = EXCLUDED.currency,
                    prepaid_balance = EXCLUDED.prepaid_balance,
                    max_concurrent_calls = EXCLUDED.max_concurrent_calls,
                    cps_limit = EXCLUDED.cps_limit,
                    fraud_locked = false,
                    daily_spend_limit = EXCLUDED.daily_spend_limit,
                    max_rate_per_min = EXCLUDED.max_rate_per_min,
                    max_call_duration_sec = EXCLUDED.max_call_duration_sec,
                    updated_at = now()
                RETURNING *;
            """, (
                payload.code,
                payload.name,
                payload.currency.upper(),
                payload.prepaid_balance,
                payload.max_concurrent_calls,
                payload.cps_limit,
                payload.daily_spend_limit,
                payload.max_rate_per_min,
                payload.max_call_duration_sec,
            ))
            row = cur.fetchone()

            cur.execute("""
                INSERT INTO billing.customer_admin_events(customer_code, event_type, amount, currency, reference, details)
                VALUES (%s, 'customer_upsert', %s, %s, %s, jsonb_build_object('name', %s));
            """, (
                payload.code,
                payload.prepaid_balance,
                payload.currency.upper(),
                f"admin-create-{uuid.uuid4()}",
                payload.name,
            ))

            conn.commit()

    return row_to_json(dict(row))


@app.get("/api/v1/customers/{customer_code}")
def get_customer(customer_code: str, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM billing.customer_summary(%s);", (customer_code,))
            row = cur.fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Customer not found")

    return row_to_json(dict(row))


@app.post("/api/v1/customers/{customer_code}/credit")
def credit_customer(customer_code: str, payload: CustomerCreditRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)
    reference = payload.reference or f"credit-{uuid.uuid4()}"

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE billing.customers
                SET prepaid_balance = prepaid_balance + %s,
                    updated_at = now()
                WHERE code = %s
                RETURNING code, prepaid_balance, currency;
            """, (payload.amount, customer_code))
            row = cur.fetchone()

            if row is None:
                raise HTTPException(status_code=404, detail="Customer not found")

            cur.execute("""
                INSERT INTO billing.wallet_transactions(customer_code, amount, currency, type, reference)
                VALUES (%s, %s, %s, 'admin_credit', %s);
            """, (customer_code, payload.amount, row["currency"], reference))

            cur.execute("""
                INSERT INTO billing.customer_admin_events(customer_code, event_type, amount, currency, reference, details)
                VALUES (%s, 'credit', %s, %s, %s, jsonb_build_object('note', %s));
            """, (customer_code, payload.amount, row["currency"], reference, payload.note or ""))

            conn.commit()

    return {"customer_code": customer_code, "credited": payload.amount, "balance": json_safe(row["prepaid_balance"]), "reference": reference}


@app.post("/api/v1/customers/{customer_code}/limits")
def update_customer_limits(customer_code: str, payload: CustomerLimitsRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE billing.customers
                SET
                    cps_limit = COALESCE(%s, cps_limit),
                    max_concurrent_calls = COALESCE(%s, max_concurrent_calls),
                    daily_spend_limit = COALESCE(%s, daily_spend_limit),
                    max_rate_per_min = COALESCE(%s, max_rate_per_min),
                    max_call_duration_sec = COALESCE(%s, max_call_duration_sec),
                    updated_at = now()
                WHERE code = %s
                RETURNING *;
            """, (
                payload.cps_limit,
                payload.max_concurrent_calls,
                payload.daily_spend_limit,
                payload.max_rate_per_min,
                payload.max_call_duration_sec,
                customer_code,
            ))
            row = cur.fetchone()

            if row is None:
                raise HTTPException(status_code=404, detail="Customer not found")

            cur.execute("""
                INSERT INTO billing.customer_admin_events(customer_code, event_type, details)
                VALUES (%s, 'limits_update', jsonb_build_object(
                    'cps_limit', %s,
                    'max_concurrent_calls', %s,
                    'daily_spend_limit', %s,
                    'max_rate_per_min', %s,
                    'max_call_duration_sec', %s
                ));
            """, (
                customer_code,
                payload.cps_limit,
                payload.max_concurrent_calls,
                payload.daily_spend_limit,
                payload.max_rate_per_min,
                payload.max_call_duration_sec,
            ))

            conn.commit()

    return row_to_json(dict(row))


@app.post("/api/v1/customers/{customer_code}/status")
def update_customer_status(customer_code: str, payload: CustomerStatusRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE billing.customers
                SET status = %s,
                    updated_at = now()
                WHERE code = %s
                RETURNING code, status;
            """, (payload.status, customer_code))
            row = cur.fetchone()

            if row is None:
                raise HTTPException(status_code=404, detail="Customer not found")

            cur.execute("""
                INSERT INTO billing.customer_admin_events(customer_code, event_type, details)
                VALUES (%s, 'status_update', jsonb_build_object('status', %s));
            """, (customer_code, payload.status))

            conn.commit()

    return row_to_json(dict(row))


@app.post("/api/v1/customers/{customer_code}/fraud-lock")
def update_customer_fraud_lock(customer_code: str, payload: FraudLockRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE billing.customers
                SET fraud_locked = %s,
                    updated_at = now()
                WHERE code = %s
                RETURNING code, fraud_locked;
            """, (payload.fraud_locked, customer_code))
            row = cur.fetchone()

            if row is None:
                raise HTTPException(status_code=404, detail="Customer not found")

            cur.execute("""
                INSERT INTO billing.customer_admin_events(customer_code, event_type, details)
                VALUES (%s, 'fraud_lock_update', jsonb_build_object('fraud_locked', %s));
            """, (customer_code, payload.fraud_locked))

            conn.commit()

    return row_to_json(dict(row))


@app.get("/api/v1/customers/{customer_code}/cdrs")
def customer_cdrs(customer_code: str, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    call_id,
                    src,
                    dst,
                    destination,
                    duration_sec,
                    rate_per_min,
                    cost,
                    currency,
                    status,
                    created_at
                FROM billing.cdrs
                WHERE customer_code = %s
                ORDER BY created_at DESC
                LIMIT 100;
            """, (customer_code,))
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.get("/api/v1/customers/{customer_code}/fraud-events")
def customer_fraud_events(customer_code: str, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    created_at,
                    event_type,
                    severity,
                    src,
                    dst,
                    normalized_dst,
                    call_id,
                    details
                FROM billing.fraud_events
                WHERE customer_code = %s
                ORDER BY created_at DESC
                LIMIT 100;
            """, (customer_code,))
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.get("/api/v1/customers/{customer_code}/routing-decisions")
def customer_routing_decisions(customer_code: str, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    created_at,
                    src,
                    dst,
                    normalized_dst,
                    selected_provider_code,
                    route_allowed,
                    route_reason,
                    destination,
                    sell_rate_per_min,
                    buy_rate_per_min,
                    margin_per_min,
                    estimated_margin,
                    pstn_enabled
                FROM billing.routing_decisions
                WHERE customer_code = %s
                ORDER BY created_at DESC
                LIMIT 100;
            """, (customer_code,))
            rows = cur.fetchall()

    return rows_to_json(rows)



@app.get("/api/v1/rates")
def list_rates(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    prefix,
                    destination,
                    rate_per_min,
                    setup_fee,
                    minimum_sec,
                    increment_sec,
                    enabled
                FROM billing.rate_prefixes
                ORDER BY prefix;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.post("/api/v1/rates")
def upsert_rate(payload: SellRateRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.upsert_sell_rate(%s, %s, %s, %s, %s, %s, %s);",
                (
                    payload.prefix,
                    payload.destination,
                    payload.rate_per_min,
                    payload.setup_fee,
                    payload.minimum_sec,
                    payload.increment_sec,
                    payload.enabled,
                ),
            )
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.post("/api/v1/rates/{prefix}/disable")
def disable_rate(prefix: str, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT billing.disable_sell_rate(%s) AS disabled;", (prefix,))
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.get("/api/v1/blocked-prefixes")
def list_blocked_prefixes(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT prefix, reason
                FROM billing.blocked_prefixes
                ORDER BY prefix;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.post("/api/v1/blocked-prefixes")
def upsert_blocked_prefix(payload: BlockedPrefixRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.upsert_blocked_prefix(%s, %s);",
                (payload.prefix, payload.reason),
            )
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.delete("/api/v1/blocked-prefixes/{prefix}")
def delete_blocked_prefix(prefix: str, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT billing.delete_blocked_prefix(%s) AS deleted;", (prefix,))
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.post("/api/v1/provider-routes")
def upsert_provider_route(payload: ProviderRouteAdminRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.upsert_provider_route_admin(%s, %s, %s, %s, %s, %s, %s, %s, %s);",
                (
                    payload.provider_code,
                    payload.prefix,
                    payload.destination,
                    payload.buy_rate_per_min,
                    payload.setup_fee,
                    payload.minimum_sec,
                    payload.increment_sec,
                    payload.enabled,
                    payload.priority,
                ),
            )
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.get("/api/v1/rate-admin-events")
def rate_admin_events(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    created_at,
                    event_type,
                    prefix,
                    provider_code,
                    details
                FROM billing.rate_admin_events
                ORDER BY created_at DESC
                LIMIT 100;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)



@app.get("/api/v1/reports/customers/{customer_code}/usage")
def report_customer_usage(
    customer_code: str,
    date_from: str = Query(default="1970-01-01"),
    date_to: str = Query(default="2999-12-31"),
    x_knvox_api_key: Optional[str] = Header(default=None)
):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.customer_usage_summary(%s, %s::date, %s::date);",
                (customer_code, date_from, date_to),
            )
            row = cur.fetchone()

    return row_to_json(dict(row))


@app.get("/api/v1/reports/customers/{customer_code}/margin")
def report_customer_margin(
    customer_code: str,
    date_from: str = Query(default="1970-01-01"),
    date_to: str = Query(default="2999-12-31"),
    x_knvox_api_key: Optional[str] = Header(default=None)
):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.customer_margin_summary(%s, %s::date, %s::date);",
                (customer_code, date_from, date_to),
            )
            row = cur.fetchone()

    return row_to_json(dict(row))


@app.get("/api/v1/reports/customers/{customer_code}/wallet")
def report_customer_wallet(
    customer_code: str,
    x_knvox_api_key: Optional[str] = Header(default=None)
):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    created_at,
                    customer_code,
                    amount,
                    currency,
                    type,
                    reference
                FROM billing.wallet_transactions
                WHERE customer_code = %s
                ORDER BY created_at DESC
                LIMIT 200;
            """, (customer_code,))
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.get("/api/v1/reports/customers/{customer_code}/cdrs.csv")
def export_customer_cdrs_csv(
    customer_code: str,
    date_from: str = Query(default="1970-01-01"),
    date_to: str = Query(default="2999-12-31"),
    x_knvox_api_key: Optional[str] = Header(default=None)
):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    call_id,
                    customer_code,
                    src,
                    dst,
                    destination,
                    duration_sec,
                    rate_per_min,
                    cost,
                    currency,
                    status,
                    created_at
                FROM billing.cdrs
                WHERE customer_code = %s
                  AND created_at >= %s::date
                  AND created_at < (%s::date + 1)
                ORDER BY created_at DESC;
            """, (customer_code, date_from, date_to))
            rows = cur.fetchall()

    output = io.StringIO()
    fieldnames = [
        "call_id",
        "customer_code",
        "src",
        "dst",
        "destination",
        "duration_sec",
        "rate_per_min",
        "cost",
        "currency",
        "status",
        "created_at",
    ]
    writer = csv.DictWriter(output, fieldnames=fieldnames)
    writer.writeheader()

    for row in rows:
        safe = row_to_json(dict(row))
        writer.writerow({k: safe.get(k, "") for k in fieldnames})

    filename = f"{customer_code}_cdrs_{date_from}_{date_to}.csv"

    return Response(
        content=output.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


@app.post("/api/v1/reports/customers/{customer_code}/invoice-export")
def create_invoice_export(
    customer_code: str,
    payload: InvoiceExportRequest,
    x_knvox_api_key: Optional[str] = Header(default=None)
):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.create_invoice_export(%s, %s::date, %s::date);",
                (customer_code, payload.date_from, payload.date_to),
            )
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.get("/api/v1/reports/invoice-exports")
def list_invoice_exports(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    id,
                    customer_code,
                    period_start,
                    period_end,
                    total_calls,
                    billable_calls,
                    total_duration_sec,
                    total_cost,
                    currency,
                    status,
                    created_at
                FROM billing.invoice_exports
                ORDER BY created_at DESC
                LIMIT 100;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)



@app.get("/api/v1/sip-accounts")
def list_sip_accounts(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    username,
                    customer_code,
                    display_name,
                    realm,
                    enabled,
                    cps_limit,
                    max_concurrent_calls,
                    allowed_ip_cidr,
                    notes,
                    created_at,
                    updated_at
                FROM billing.sip_accounts
                ORDER BY customer_code, username;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.post("/api/v1/sip-accounts")
def upsert_sip_account(payload: SipAccountRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    password = payload.auth_password or secrets.token_urlsafe(18)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.upsert_sip_account(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);",
                (
                    payload.username,
                    payload.customer_code,
                    payload.display_name or payload.username,
                    password,
                    payload.realm,
                    payload.enabled,
                    payload.cps_limit,
                    payload.max_concurrent_calls,
                    payload.allowed_ip_cidr,
                    payload.notes,
                ),
            )
            row = cur.fetchone()
            conn.commit()

    result = row_to_json(dict(row))
    result["auth_password"] = password
    result["warning"] = "Password returned for provisioning. Store securely."
    return result


@app.get("/api/v1/sip-accounts/{username}")
def get_sip_account(username: str, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    username,
                    customer_code,
                    display_name,
                    realm,
                    enabled,
                    cps_limit,
                    max_concurrent_calls,
                    allowed_ip_cidr,
                    notes,
                    created_at,
                    updated_at
                FROM billing.sip_accounts
                WHERE username = %s;
            """, (username,))
            row = cur.fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="SIP account not found")

    return row_to_json(dict(row))


@app.get("/api/v1/customers/{customer_code}/sip-accounts")
def customer_sip_accounts(customer_code: str, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    username,
                    customer_code,
                    display_name,
                    realm,
                    enabled,
                    cps_limit,
                    max_concurrent_calls,
                    allowed_ip_cidr,
                    notes,
                    created_at,
                    updated_at
                FROM billing.sip_accounts
                WHERE customer_code = %s
                ORDER BY username;
            """, (customer_code,))
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.post("/api/v1/sip-accounts/{username}/status")
def set_sip_account_status(username: str, payload: SipAccountStatusRequest, x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.set_sip_account_status(%s,%s);",
                (username, payload.enabled),
            )
            row = cur.fetchone()
            conn.commit()

    return row_to_json(dict(row))


@app.get("/api/v1/sip-account-events")
def sip_account_events(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    created_at,
                    username,
                    customer_code,
                    event_type,
                    details
                FROM billing.sip_account_events
                ORDER BY created_at DESC
                LIMIT 100;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)



@app.get("/api/v1/call-control/resolve-sip-account/{username}")
def call_control_resolve_sip_account(
    username: str,
    source_ip: str = Query(default=""),
    x_knvox_api_key: Optional[str] = Header(default=None)
):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.resolve_sip_account_for_call(%s, %s);",
                (username, source_ip),
            )
            row = cur.fetchone()

    return row_to_json(dict(row))


@app.get("/api/v1/call-control/sip-account-map")
def call_control_sip_account_map(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    sa.username,
                    sa.customer_code,
                    c.name AS customer_name,
                    c.status AS customer_status,
                    sa.enabled AS sip_enabled,
                    sa.cps_limit,
                    sa.max_concurrent_calls,
                    sa.allowed_ip_cidr,
                    sa.updated_at
                FROM billing.sip_accounts sa
                JOIN billing.customers c ON c.code = sa.customer_code
                ORDER BY sa.username;
            """)
            rows = cur.fetchall()

    return rows_to_json(rows)


@app.get("/api/v1/status")
def status(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    sql = """
        SELECT
            (SELECT value FROM billing.system_settings WHERE key='pstn_enabled') AS pstn_enabled,
            (SELECT count(*) FROM billing.customers) AS customers,
            (SELECT count(*) FROM billing.rate_prefixes WHERE enabled = true) AS active_rates,
            (SELECT count(*) FROM billing.blocked_prefixes) AS blocked_prefixes,
            (SELECT count(*) FROM billing.active_calls) AS active_calls,
            (SELECT count(*) FROM billing.cdrs) AS cdrs,
            (SELECT count(*) FROM billing.provider_accounts) AS providers,
            (SELECT count(*) FROM billing.provider_routes WHERE enabled=true) AS provider_routes,
            (SELECT count(*) FROM billing.routing_decisions) AS routing_decisions,
            (SELECT count(*) FROM billing.fraud_events) AS fraud_events;
    """

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            row = cur.fetchone()

    return row_to_json(dict(row))
