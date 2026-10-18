import express, { Request, Response, NextFunction } from "express";
import client from "prom-client";
import { LicenseRepo } from "./db/repo";
import { licenseRouter } from "./routes/licenses";
import { circuitBreaker } from "./breaker";

export function buildApp(repo: LicenseRepo, opts: { breakerOpenMs?: number } = {}) {
  const app = express();
  const breaker = circuitBreaker(opts.breakerOpenMs ?? 2000);
  const registry = new client.Registry();
  client.collectDefaultMetrics({ register: registry });
  const httpDuration = new client.Histogram({
    name: "http_request_duration_seconds", help: "HTTP request latency",
    labelNames: ["method", "route", "status"], buckets: [0.05, 0.1, 0.25, 0.5, 1, 2.5], registers: [registry],
  });

  app.use(express.json());
  app.use((req, res, next) => {
    const end = httpDuration.startTimer();
    res.on("finish", () => end({ method: req.method, route: req.baseUrl + (req.route?.path ?? ""), status: String(res.statusCode) }));
    next();
  });

  app.get("/healthz", (_q, s) => s.json({ status: "ok" }));                       // liveness
  app.get("/readyz", async (_q, s) => (await repo.ping()) ? s.json({ status: "ready" }) : s.status(503).json({ status: "db unavailable" })); // readiness
  app.get("/metrics", async (_q, s) => { s.set("Content-Type", registry.contentType); s.end(await registry.metrics()); });
  app.use("/api", breaker.guard);
  app.use("/api/licenses", licenseRouter(repo));

  // Dependency failures (e.g. database down) become a 503 instead of a crash, and open the circuit breaker
  app.use((err: Error, _q: Request, s: Response, _n: NextFunction) => {
    console.error("request failed:", err.message);
    breaker.trip();
    s.status(503).json({ error: "service unavailable" });
  });
  return app;
}
