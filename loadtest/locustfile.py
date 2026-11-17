"""Load test for the License Manager API.

SLO gate (docs/SLO.md): p95 < 500 ms and error rate < 1%.
If either is breached the process exits non-zero, which fails CI.
"""
import random
from locust import HttpUser, task, between, events


class LicenseAdmin(HttpUser):
    wait_time = between(0.5, 2)

    def on_start(self):
        r = self.client.post("/api/licenses", json={"name": f"seed-{random.randint(1, 10**9)}", "seats": 10},
                             name="POST /api/licenses")
        self.lid = r.json().get("id") if r.ok else None

    @task(6)
    def list_licenses(self):
        self.client.get("/api/licenses", name="GET /api/licenses")

    @task(3)
    def get_one(self):
        if self.lid:
            self.client.get(f"/api/licenses/{self.lid}", name="GET /api/licenses/:id")

    @task(1)
    def create_update_delete(self):
        r = self.client.post("/api/licenses", json={"name": "load", "seats": random.randint(1, 500)},
                             name="POST /api/licenses")
        if not r.ok:
            return
        lid = r.json()["id"]
        self.client.put(f"/api/licenses/{lid}", json={"status": "suspended"}, name="PUT /api/licenses/:id")
        self.client.delete(f"/api/licenses/{lid}", name="DELETE /api/licenses/:id")


@events.quitting.add_listener
def slo_gate(environment, **_):
    stats = environment.stats.total
    p95 = stats.get_response_time_percentile(0.95)
    fail_ratio = stats.fail_ratio
    print(f"SLO check: p95={p95} ms (limit 500), error rate={fail_ratio:.2%} (limit 1%)")
    if p95 > 500 or fail_ratio > 0.01:
        environment.process_exit_code = 1
