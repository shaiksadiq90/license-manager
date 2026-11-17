import express, { Request, Response, NextFunction } from "express";
import client from "prom-client";
import { LicenseRepo } from "./db/repo";
import { licenseRouter } from "./routes/licenses";
import { circuitBreaker, isConnectionError } from "./breaker";

export function buildApp(repo: LicenseRepo, opts: { breakerRetryMs?: number } = {}) {
  const app = express();
  const breaker = circuitBreaker(() => repo.ping(), opts.breakerRetryMs ?? 2000);
  const registry = new client.Registry();
  client.collectDefaultMetrics({ register: registry });
  const httpDuration = new client.Histogram({
    name: "http_request_duration_seconds", help: "HTTP request latency",
    labelNames: ["method", "route", "status"], buckets: [0.05, 0.1, 0.25, 0.5, 1, 2.5], registers: [registry],
  });

  app.disable("x-powered-by");                                                     // don't advertise Express
  app.use((_q, s, next) => {                                                       // security headers on every response
    s.set({ "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", "Cross-Origin-Resource-Policy": "same-origin",
      "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'", "Cache-Control": "no-store" });
    next();
  });
  app.use(express.json());
  app.use((req, res, next) => {
    const end = httpDuration.startTimer();
    res.on("finish", () => end({ method: req.method, route: req.baseUrl + (req.route?.path ?? ""), status: String(res.statusCode) }));
    next();
  });

  app.get("/healthz", (_q, s) => s.json({ status: "ok" }));                       // liveness
  app.get("/readyz", async (_q, s) => {                                           // readiness
    if (await repo.ping()) { breaker.reset(); s.json({ status: "ready" }); } else s.status(503).json({ status: "db unavailable" });
  });
  app.get("/metrics", async (_q, s) => { s.set("Content-Type", registry.contentType); s.end(await registry.metrics()); });
  app.use("/api", breaker.guard);
  app.use("/api/licenses", licenseRouter(repo));
  app.use((_q, s) => { s.status(404).json({ error: "not found" }); });           // JSON 404, not Express's HTML page

  // Client errors (e.g. malformed JSON) keep their 4xx. Only database connection failures are a 503 and open
  // the breaker; any other error is a 500 so real bugs aren't hidden behind "service unavailable"
  app.use((err: Error & { status?: number }, _q: Request, s: Response, _n: NextFunction) => {
    if (err.status && err.status >= 400 && err.status < 500) return s.status(err.status).json({ error: "bad request" });
    console.error("request failed:", err.message);
    if (isConnectionError(err)) { breaker.trip(); return s.status(503).json({ error: "service unavailable" }); }
    s.status(500).json({ error: "internal error" });
  });
  return app;
}
