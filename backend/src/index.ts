import { Pool } from "pg";
import { buildApp } from "./app";
import { PgLicenseRepo } from "./db/repo";

const pool = new Pool({ connectionString: process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/licenses" });
const port = Number(process.env.PORT ?? 3000);
const server = buildApp(new PgLicenseRepo(pool)).listen(port, () => console.log(`API listening on ${port}`));

// graceful shutdown so Kubernetes rolling updates drain cleanly
process.on("SIGTERM", () => server.close(() => pool.end().then(() => process.exit(0))));
