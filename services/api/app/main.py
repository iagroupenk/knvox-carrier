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


class AuthorizeCallRequest(BaseModel):
    customer_code: str = Field(..., min_length=1, max_length=64)
    src: str = Field(..., min_length=1, max_length=64)
    dst: str = Field(..., min_length=1, max_length=64)
    call_id: Optional[str] = None


class AuthorizeCallResponse(BaseModel):
    allowed: bool
    reason: str
    normalized_dst: str
    customer_balance: float
    active_calls: int
    max_concurrent_calls: int
    rate_per_min: float
    estimated_min_cost: float
    call_id: str


app = FastAPI(title=APP_NAME, version="1.3.5")


def require_api_key(x_knvox_api_key: Optional[str]) -> None:
    expected = get_env("BILLING_API_TOKEN")
    if not x_knvox_api_key or x_knvox_api_key != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")


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


@app.post("/api/v1/authorize-call", response_model=AuthorizeCallResponse)
def authorize_call(
    payload: AuthorizeCallRequest,
    x_knvox_api_key: Optional[str] = Header(default=None),
):
    require_api_key(x_knvox_api_key)

    call_id = payload.call_id or f"api-{uuid.uuid4()}"

    sql = """
        SELECT *
        FROM billing.authorize_call(%s, %s, %s, %s);
    """

    try:
        with db_connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    sql,
                    (
                        payload.customer_code,
                        payload.src,
                        payload.dst,
                        call_id,
                    ),
                )
                row = cur.fetchone()
                conn.commit()

        if row is None:
            raise HTTPException(status_code=500, detail="No authorization result")

        result = row_to_json(dict(row))
        result["call_id"] = call_id
        return result

    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/api/v1/status")
def status(x_knvox_api_key: Optional[str] = Header(default=None)):
    require_api_key(x_knvox_api_key)

    sql = """
        SELECT
            (SELECT value FROM billing.system_settings WHERE key='pstn_enabled') AS pstn_enabled,
            (SELECT count(*) FROM billing.customers) AS customers,
            (SELECT count(*) FROM billing.rate_prefixes WHERE enabled = true) AS active_rates,
            (SELECT count(*) FROM billing.blocked_prefixes) AS blocked_prefixes,
            (SELECT count(*) FROM billing.active_calls) AS active_calls;
    """

    with db_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            row = cur.fetchone()

    return row_to_json(dict(row))
