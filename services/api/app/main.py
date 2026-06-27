import os
import uuid
from decimal import Decimal
from typing import Optional, Any, Dict

import psycopg2
import psycopg2.extras
from fastapi import FastAPI, Header, HTTPException
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
    return value


def row_to_json(row: Dict[str, Any]) -> Dict[str, Any]:
    return {key: json_safe(value) for key, value in row.items()}


def require_api_key(x_knvox_api_key: Optional[str]) -> None:
    expected = get_env("BILLING_API_TOKEN")
    if not x_knvox_api_key or x_knvox_api_key != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")


class AuthorizeCallRequest(BaseModel):
    customer_code: str = Field(..., min_length=1, max_length=64)
    src: str = Field(..., min_length=1, max_length=64)
    dst: str = Field(..., min_length=1, max_length=64)
    call_id: Optional[str] = None



class ProviderRouteSimulateRequest(BaseModel):
    customer_code: str = Field(..., min_length=1, max_length=64)
    src: str = Field(..., min_length=1, max_length=64)
    dst: str = Field(..., min_length=1, max_length=64)
    call_id: Optional[str] = None


class EndCallRequest(BaseModel):
    call_id: str = Field(..., min_length=1, max_length=256)
    reason: Optional[str] = "normal"


app = FastAPI(title=APP_NAME, version="1.3.9")


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

    if row is None:
        raise HTTPException(status_code=500, detail="No authorization result")

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

    if row is None:
        raise HTTPException(status_code=500, detail="No start-call result")

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

    if row is None:
        raise HTTPException(status_code=500, detail="No end-call result")

    return row_to_json(dict(row))


@app.get("/api/v1/active-calls")
def active_calls(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT call_id, customer_code, src, dst, normalized_dst, started_at, last_seen_at
                FROM billing.active_calls
                ORDER BY started_at DESC;
                """
            )
            rows = cur.fetchall()

    return [row_to_json(dict(row)) for row in rows]


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

    if row is None:
        raise HTTPException(status_code=500, detail="No provider route result")

    return row_to_json(dict(row))


@app.get("/api/v1/provider-routes")
def provider_routes(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
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
                """
            )
            rows = cur.fetchall()

    return [row_to_json(dict(row)) for row in rows]


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
            (SELECT count(*) FROM billing.cdrs) AS cdrs;
    """

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            row = cur.fetchone()

    return row_to_json(dict(row))
