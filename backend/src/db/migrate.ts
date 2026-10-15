import { Pool } from "pg";

// Idempotent schema, applied at startup so every environment (Compose, minikube, EKS) self-initialises.
const SCHEMA = `
CREATE TABLE IF NOT EXISTS licenses (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  seats INTEGER NOT NULL CHECK (seats > 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, email TEXT UNIQUE NOT NULL);
CREATE TABLE IF NOT EXISTS license_assignments (
  license_id INTEGER REFERENCES licenses(id) ON DELETE CASCADE,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (license_id, user_id)
);`;

export async function migrate(pool: Pool, attempts = 30): Promise<void> {
  for (let i = 1; i <= attempts; i++) {
    try { await pool.query(SCHEMA); console.log("schema ready"); return; }
    catch (e) { console.log(`database not ready (attempt ${i}/${attempts}): ${(e as Error).message}`); await new Promise(r => setTimeout(r, 2000)); }
  }
  throw new Error("database unavailable, giving up");
}
