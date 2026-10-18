import request from "supertest";
import { buildApp } from "../src/app";
import { MemoryLicenseRepo } from "../src/db/repo";

const app = () => buildApp(new MemoryLicenseRepo());

describe("licenses API", () => {
  it("health and readiness respond", async () => {
    const a = app();
    expect((await request(a).get("/healthz")).status).toBe(200);
    expect((await request(a).get("/readyz")).status).toBe(200);
  });
  it("creates and lists a license", async () => {
    const a = app();
    const c = await request(a).post("/api/licenses").send({ name: "Maya", seats: 10 });
    expect(c.status).toBe(201); expect(c.body.status).toBe("active");
    expect((await request(a).get("/api/licenses")).body).toHaveLength(1);
  });
  it("rejects seats <= 0", async () => {
    expect((await request(app()).post("/api/licenses").send({ name: "X", seats: 0 })).status).toBe(400);
  });
  it("rejects missing name", async () => {
    expect((await request(app()).post("/api/licenses").send({ seats: 5 })).status).toBe(400);
  });
  it("rejects invalid status", async () => {
    expect((await request(app()).post("/api/licenses").send({ name: "X", seats: 1, status: "bogus" })).status).toBe(400);
  });
  it("updates a license", async () => {
    const a = app(); const c = await request(a).post("/api/licenses").send({ name: "3ds Max", seats: 5 });
    const u = await request(a).put(`/api/licenses/${c.body.id}`).send({ seats: 20 });
    expect(u.body.seats).toBe(20);
  });
  it("deletes a license and 404s after", async () => {
    const a = app(); const c = await request(a).post("/api/licenses").send({ name: "Flow", seats: 2 });
    expect((await request(a).delete(`/api/licenses/${c.body.id}`)).status).toBe(204);
    expect((await request(a).get(`/api/licenses/${c.body.id}`)).status).toBe(404);
  });
  it("exposes Prometheus metrics", async () => {
    const r = await request(app()).get("/metrics");
    expect(r.text).toContain("process_cpu");
  });
  it("returns 503 instead of crashing when the database is down", async () => {
    const down = new MemoryLicenseRepo();
    down.list = async () => { throw new Error("connect ECONNREFUSED"); };
    down.ping = async () => false;
    const a = buildApp(down);
    expect((await request(a).get("/api/licenses")).status).toBe(503);
    expect((await request(a).get("/readyz")).status).toBe(503);
    expect((await request(a).get("/healthz")).status).toBe(200);
  });
  it("fails fast while the database is known to be down", async () => {
    let calls = 0;
    const down = new MemoryLicenseRepo();
    down.list = async () => { calls++; throw new Error("connect ETIMEDOUT"); };
    down.ping = async () => false;
    const a = buildApp(down, { breakerRetryMs: 60_000 });
    expect((await request(a).get("/api/licenses")).status).toBe(503);
    expect((await request(a).get("/api/licenses")).status).toBe(503);
    expect(calls).toBe(1);   // the second request never waited on the database
  });
  it("does not open the breaker for errors unrelated to the database connection", async () => {
    let calls = 0;
    const repo = new MemoryLicenseRepo();
    repo.list = async () => { calls++; throw new Error("unexpected bug"); };
    const a = buildApp(repo, { breakerRetryMs: 60_000 });
    await request(a).get("/api/licenses"); await request(a).get("/api/licenses");
    expect(calls).toBe(2);
  });
  it("closes the breaker once the database is back", async () => {
    let fail = true;
    const repo = new MemoryLicenseRepo(); const list = repo.list.bind(repo);
    repo.list = async () => { if (fail) throw new Error("connect ECONNREFUSED 10.0.0.5:5432"); return list(); };
    repo.ping = async () => !fail;
    const a = buildApp(repo, { breakerRetryMs: 20 });
    expect((await request(a).get("/api/licenses")).status).toBe(503);   // trips the breaker
    fail = false;
    expect((await request(a).get("/api/licenses")).status).toBe(503);   // still open: fast 503, no database call
    await new Promise(r => setTimeout(r, 60));                          // background health check sees the database again
    expect((await request(a).get("/api/licenses")).status).toBe(200);
  });
});
