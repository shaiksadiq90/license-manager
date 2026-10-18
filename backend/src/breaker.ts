import { Request, Response, NextFunction } from "express";

// Circuit breaker for the database. Once a request fails because the database is unreachable, every request
// gets a 503 straight away instead of waiting on a dead connection. While the breaker is open, a background
// health check (not a user's request) pings the database every `retryMs` and closes the breaker when it answers.
// Only "can't reach the database" errors should open the breaker; a bug in one request must not take down everyone
export function isConnectionError(err: Error & { code?: string }) {
  return ["ECONNREFUSED", "ENOTFOUND", "EAI_AGAIN", "ETIMEDOUT", "ECONNRESET", "57P01"].includes(err.code ?? "")
    || /connect|connection terminated|timeout exceeded/i.test(err.message);
}

export function circuitBreaker(ping: () => Promise<boolean>, retryMs = 2000) {
  let open = false;
  const probe = async () => {
    const ok = await ping().catch(() => false);
    if (ok) open = false; else setTimeout(probe, retryMs).unref();
  };
  return {
    guard(_q: Request, s: Response, next: NextFunction) {
      if (open) { s.status(503).json({ error: "service unavailable" }); return; }
      next();
    },
    trip() { if (!open) { open = true; setTimeout(probe, retryMs).unref(); } },
    reset() { open = false; },   // any successful health check (e.g. the readiness probe) closes it at once
    isOpen: () => open,
  };
}
