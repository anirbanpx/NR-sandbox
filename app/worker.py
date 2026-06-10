"""
Background worker — polls a Redis queue and processes jobs.

This process is intentionally NOT auto-instrumented by either stack out of the box.
Killing it mid-run is the central demo moment: the process disappears from the host
process list, but neither stack alerts by default. That's the gap the prototype shows.

Run: python -m app.worker
Stop: kill <pid>  (or Ctrl-C) to trigger the gap demonstration
"""
import os
import time
import random
import logging
import signal
import sys

import redis

from app.telemetry import configure_telemetry

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("worker")

configure_telemetry(service_name="nr-sandbox-worker")

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
QUEUE_KEY = "jobs:pending"
POLL_INTERVAL = float(os.getenv("WORKER_POLL_INTERVAL", "2"))


def handle_job(job_id: str, payload: str) -> None:
    duration = random.uniform(0.1, 0.5)
    time.sleep(duration)
    logger.info("processed job %s in %.0fms", job_id, duration * 1000)


def run() -> None:
    r = redis.from_url(REDIS_URL, decode_responses=True)
    logger.info("worker started — polling %s every %.1fs", QUEUE_KEY, POLL_INTERVAL)

    def _shutdown(sig, frame):
        logger.info("worker shutting down (signal %s)", sig)
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    while True:
        try:
            job = r.blpop(QUEUE_KEY, timeout=POLL_INTERVAL)
            if job:
                _, payload = job
                job_id = payload.split(":", 1)[0] if ":" in payload else payload
                handle_job(job_id, payload)
        except redis.exceptions.ConnectionError as exc:
            logger.warning("redis connection error: %s — retrying in 5s", exc)
            time.sleep(5)
        except Exception as exc:
            logger.error("unhandled error: %s", exc, exc_info=True)
            time.sleep(1)


if __name__ == "__main__":
    run()
