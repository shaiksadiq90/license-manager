import { Pool } from "pg";
import { buildApp } from "./app";
import { PgLicenseRepo } from "./db/repo";
import { migrate } from "./db/migrate";

// Give up on a new connection after 1 s, so an unreachable database fails fast instead of hanging requests
const pool = new Pool({ connectionString: process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/licenses", connectionTimeoutMillis: 1000 });
// An idle client losing its connection (e.g. database restart) must not crash the process
pool.on("error", err => console.error("postgres pool error:", err.message));

const port = Number(process.env.PORT ?? 3000);

migrate(pool).then(() => {
  const server = buildApp(new PgLicenseRepo(pool)).listen(port, () => console.log(`API listening on ${port}`));
  // graceful shutdown so Kubernetes rolling updates drain cleanly
  process.on("SIGTERM", () => server.close(() => pool.end().then(() => process.exit(0))));
}).catch(err => { console.error(err); process.exit(1); });
