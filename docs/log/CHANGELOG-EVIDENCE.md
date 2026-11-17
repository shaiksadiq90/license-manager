# Change and evidence log

One entry per change. Each entry records **what changed, the evidence for it, and any
corrections** to earlier entries or docs. Rules:

- No guessing. If something isn't confirmed by a run, a link or a file, mark it **not yet confirmed**.
- Never rewrite an old entry. Add a new one and list it under *Corrections*.
- Evidence means a link to a CI run, a report artifact, a PR, a commit or a file.

---

## 2026-11-17 — Add SAST (Semgrep), DAST (OWASP ZAP) and load testing (Locust)

| | |
|---|---|
| **Why** | Mentor feedback: show security testing and load testing as part of the DevOps pipeline |
| **Branch / PR** | `security-and-load-testing` / PR pending |

### What changed

| File | Change |
|---|---|
| `.github/workflows/security.yml` | new: Semgrep SAST → start stack → ZAP API + baseline scans → Locust load test with SLO gate |
| `.zap/rules.tsv` | new: ZAP rule overrides; all WARN for now |
| `loadtest/locustfile.py` | new: mixed read/write traffic; fails if p95 > 500 ms or errors > 1% |
| `loadtest/openapi.yaml` | new: API spec that ZAP uses to find endpoints |
| `docs/log/CHANGELOG-EVIDENCE.md` | new: this log |

### Evidence

- First CI run: **not yet confirmed** (link goes here once it has run)
- Semgrep findings count: **not yet confirmed**
- ZAP alert counts (high / medium / low): **not yet confirmed**
- Locust p95 and error rate at 50 users: **not yet confirmed**

### Corrections

- None yet.
