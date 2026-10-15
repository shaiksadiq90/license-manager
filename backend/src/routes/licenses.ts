import { Router } from "express";
import { LicenseRepo } from "../db/repo";

const STATUSES = ["active", "suspended", "expired"];

function validate(body: any, partial = false): string | null {
  if (!partial || body.name !== undefined) if (typeof body.name !== "string" || !body.name.trim()) return "name is required";
  if (!partial || body.seats !== undefined) if (!Number.isInteger(body.seats) || body.seats <= 0) return "seats must be a positive integer";
  if (body.status !== undefined && !STATUSES.includes(body.status)) return "invalid status";
  return null;
}

export function licenseRouter(repo: LicenseRepo) {
  const r = Router();
  r.get("/", async (_q, s) => s.json(await repo.list()));
  r.get("/:id", async (q, s) => { const l = await repo.get(+q.params.id); l ? s.json(l) : s.status(404).json({ error: "not found" }); });
  r.post("/", async (q, s) => {
    const err = validate(q.body); if (err) return s.status(400).json({ error: err });
    s.status(201).json(await repo.create({ name: q.body.name, seats: q.body.seats, status: q.body.status ?? "active" }));
  });
  r.put("/:id", async (q, s) => {
    const err = validate(q.body, true); if (err) return s.status(400).json({ error: err });
    const l = await repo.update(+q.params.id, q.body); l ? s.json(l) : s.status(404).json({ error: "not found" });
  });
  r.delete("/:id", async (q, s) => (await repo.remove(+q.params.id)) ? s.status(204).end() : s.status(404).json({ error: "not found" }));
  return r;
}
