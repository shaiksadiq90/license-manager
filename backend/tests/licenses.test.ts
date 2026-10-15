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
});
