import { Pool } from "pg";

export interface License { id: number; name: string; seats: number; status: "active" | "suspended" | "expired"; }
export type NewLicense = Omit<License, "id">;

export interface LicenseRepo {
  list(): Promise<License[]>;
  get(id: number): Promise<License | null>;
  create(l: NewLicense): Promise<License>;
  update(id: number, l: Partial<NewLicense>): Promise<License | null>;
  remove(id: number): Promise<boolean>;
  ping(): Promise<boolean>;
}

export class PgLicenseRepo implements LicenseRepo {
  constructor(private pool: Pool) {}
  async list() { return (await this.pool.query("SELECT * FROM licenses ORDER BY id")).rows; }
  async get(id: number) { return (await this.pool.query("SELECT * FROM licenses WHERE id=$1", [id])).rows[0] ?? null; }
  async create(l: NewLicense) {
    return (await this.pool.query("INSERT INTO licenses(name,seats,status) VALUES($1,$2,$3) RETURNING *", [l.name, l.seats, l.status])).rows[0];
  }
  async update(id: number, l: Partial<NewLicense>) {
    const cur = await this.get(id); if (!cur) return null;
    const m = { ...cur, ...l };
    return (await this.pool.query("UPDATE licenses SET name=$1,seats=$2,status=$3 WHERE id=$4 RETURNING *", [m.name, m.seats, m.status, id])).rows[0];
  }
  async remove(id: number) { return ((await this.pool.query("DELETE FROM licenses WHERE id=$1", [id])).rowCount ?? 0) > 0; }
  async ping() { try { await this.pool.query("SELECT 1"); return true; } catch { return false; } }
}

export class MemoryLicenseRepo implements LicenseRepo {
  private rows: License[] = []; private seq = 1;
  async list() { return [...this.rows]; }
  async get(id: number) { return this.rows.find(r => r.id === id) ?? null; }
  async create(l: NewLicense) { const r = { id: this.seq++, ...l }; this.rows.push(r); return r; }
  async update(id: number, l: Partial<NewLicense>) { const r = await this.get(id); if (!r) return null; Object.assign(r, l); return r; }
  async remove(id: number) { const n = this.rows.length; this.rows = this.rows.filter(r => r.id !== id); return this.rows.length < n; }
  async ping() { return true; }
}
