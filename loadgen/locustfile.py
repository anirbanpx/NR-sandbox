"""
Load generator — simulates realistic API traffic against the FastAPI app.

Run locally:    locust -f loadgen/locustfile.py --host http://localhost:8000
Run headless:   locust -f loadgen/locustfile.py --host http://<ec2-ip> \
                    --headless -u 20 -r 2 --run-time 10m

Traffic mix mirrors a typical read-heavy API:
  80% GET  /items       — baseline read throughput
  15% POST /items       — write traffic with unique payloads
   4% GET  /items/slow  — latency spike signal (p95/p99)
   1% GET  /items/error — error rate signal
"""
import random
import string
from locust import HttpUser, task, between


def _random_string(length: int = 8) -> str:
    return "".join(random.choices(string.ascii_lowercase, k=length))


class APIUser(HttpUser):
    wait_time = between(0.5, 2.0)

    @task(80)
    def list_items(self):
        self.client.get("/items", name="/items [GET]")

    @task(15)
    def create_item(self):
        self.client.post(
            "/items",
            json={"name": _random_string(), "value": _random_string(16)},
            name="/items [POST]",
        )

    @task(4)
    def slow_endpoint(self):
        # Long timeout — this endpoint sleeps 1.5–3s intentionally
        with self.client.get(
            "/items/slow", name="/items/slow", timeout=10, catch_response=True
        ) as resp:
            if resp.status_code == 200:
                resp.success()

    @task(1)
    def error_endpoint(self):
        with self.client.get(
            "/items/error", name="/items/error", catch_response=True
        ) as resp:
            # 500 is expected — mark as success so Locust doesn't count it as a failure
            if resp.status_code == 500:
                resp.success()
