import { Request, Response, NextFunction } from "express";

// Circuit breaker for the database. Once a request fails because the database is unreachable, answer 503
// straight away for `openMs` instead of making every request wait on a dead connection. After that window,
// one request at a time is let through to test whether the database is back (half-open); success closes it.
export function circuitBreaker(openMs = 2000) {
  let openUntil = 0;
  let probing = false;
  return {
    guard(_q: Request, s: Response, next: NextFunction) {
      if (Date.now() < openUntil || probing) { s.status(503).json({ error: "service unavailable" }); return; }
      if (openUntil > 0) {
        probing = true;
        const done = () => { if (!probing) return; probing = false; if (s.writableFinished && s.statusCode < 500) openUntil = 0; };
        s.on("finish", done); s.on("close", done);
      }
      next();
    },
    trip() { openUntil = Date.now() + openMs; probing = false; },
  };
}
