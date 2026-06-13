"""
Load generator — simulates realistic API traffic against the FastAPI app.

Run locally:    locust -f loadgen/locustfile.py --host http://localhost:8000
Run headless:   locust -f loadgen/locustfile.py --host http://<ec2-ip> \
                    --headless -u 20 -r 2 --run-time 10m

Traffic mix mirrors a read-heavy CRUD API:
  74% GET    /items          — baseline read throughput
  13% POST   /items          — write traffic, grows item pool
   7% PUT    /items/{name}   — updates on existing items
   4% GET    /items/slow     — latency spike signal (p95/p99)
   1% DELETE /items/{name}   — rare deletes, keeps pool stable
   1% GET    /items/error    — error rate signal
"""
import random
import string
from locust import HttpUser, task, between


def _random_string(length: int = 8) -> str:
    return "".join(random.choices(string.ascii_lowercase, k=length))


class APIUser(HttpUser):
    wait_time = between(0.5, 2.0)
    _known_names: list = []  # shared across all user instances

    @task(74)
    def list_items(self):
        self.client.get("/items", name="/items [GET]")

    @task(13)
    def create_item(self):
        name = _random_string()
        self.client.post(
            "/items",
            json={"name": name, "value": _random_string(16)},
            name="/items [POST]",
        )
        APIUser._known_names.append(name)

    @task(7)
    def update_item(self):
        if not APIUser._known_names:
            return
        name = random.choice(APIUser._known_names)
        self.client.put(
            f"/items/{name}",
            json={"value": _random_string(16)},
            name="/items/{name} [PUT]",
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
    def delete_item(self):
        if not APIUser._known_names:
            return
        name = APIUser._known_names.pop(random.randrange(len(APIUser._known_names)))
        with self.client.delete(
            f"/items/{name}",
            name="/items/{name} [DELETE]",
            catch_response=True,
        ) as resp:
            # 404 is acceptable — another user may have deleted this item already
            if resp.status_code in (204, 404):
                resp.success()

    @task(1)
    def error_endpoint(self):
        with self.client.get(
            "/items/error", name="/items/error", catch_response=True
        ) as resp:
            # 500 is expected — mark as success so Locust doesn't count it as a failure
            if resp.status_code == 500:
                resp.success()
