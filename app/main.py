import os
import time
import random
import logging

from fastapi import FastAPI, Depends, HTTPException
from pydantic import BaseModel
import redis as redis_lib

from app.telemetry import configure_telemetry
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

logger = logging.getLogger(__name__)

# OTEL_SDK_DISABLED=true disables all telemetry (used in tests and dry runs)
configure_telemetry()

app = FastAPI(title="NR Sandbox")
FastAPIInstrumentor.instrument_app(app)

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")


def get_redis() -> redis_lib.Redis:
    return redis_lib.from_url(REDIS_URL, decode_responses=True)


class Item(BaseModel):
    name: str
    value: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/items")
def list_items(r: redis_lib.Redis = Depends(get_redis)):
    keys = r.keys("item:*")
    return {k.removeprefix("item:"): r.get(k) for k in keys}


@app.post("/items", status_code=201)
def create_item(item: Item, r: redis_lib.Redis = Depends(get_redis)):
    r.set(f"item:{item.name}", item.value)
    logger.info("item created: %s", item.name)
    return {"name": item.name, "value": item.value}


@app.get("/items/slow")
def slow_endpoint():
    """Produces p95/p99 latency spikes visible in both stacks."""
    delay = random.uniform(1.5, 3.0)
    time.sleep(delay)
    return {"latency_ms": round(delay * 1000)}


@app.get("/items/error")
def error_endpoint():
    """Drives error rate signal in both stacks."""
    logger.error("intentional error triggered")
    raise HTTPException(status_code=500, detail="intentional error")
