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

---

## 2026-11-17 — Fix first CI failures on PR #1

| | |
|---|---|
| **Why** | Both workflows failed on commit `03570c1` |
| **Branch / PR** | `security-and-load-testing` / [#1](https://github.com/shaiksadiq90/license-manager/pull/1) |

### What changed

| File | Change |
|---|---|
| `.github/workflows/security.yml` | quoted step names that contain `:`; rewrote the upload-artifact `with:` block. The file was invalid YAML, so no jobs ran |
| `backend/package-lock.json` | express 4.22.3 now resolves body-parser 1.20.9 (was 1.20.8) |

### Evidence

- [security.yml run 44176106265](https://github.com/shaiksadiq90/license-manager/actions/runs/44176106265): failed at parse. Local check: `mapping values are not allowed here`, line 50
- [ci-cd run 44176132695](https://github.com/shaiksadiq90/license-manager/actions/runs/44176132695), job `build-scan (api)`: Trivy reported CVE-2026-111181 (HIGH, body-parser 1.20.8, fixed in 1.20.9)
- Last `main` ci-cd run (2026-10-23) passed, so the CVE was published after that. The Trivy gate caught a new vulnerability as designed.
- Local `npm test`: 13/13 passed after the bump

### Corrections

- First entry said the pipeline was ready to run. It was not: `security.yml` had a YAML error.

---

## 2026-11-17 — Second run: SAST and DAST ran, Locust failed to start

### What changed

| File | Change |
|---|---|
| `.github/workflows/security.yml` | added `actions/setup-python` before Locust; the runner's system Python was missing `charset_normalizer` |

### Evidence — [run 44176675178](https://github.com/shaiksadiq90/license-manager/actions/runs/44176675178) on `fee07d0`

- ci-cd: **passed** (Trivy clean after the body-parser bump)
- Semgrep: **passed**, no ERROR-severity findings
- ZAP API scan: 0 FAIL, 5 WARN, 117 PASS
  - 503 on `/api/licenses` and on `/api/licenses/1870015440967816970` (a huge id). Cause **not yet confirmed**: probably the circuit breaker opening, or the id overflowing Postgres `integer`
  - `X-Powered-By` leaks Express; `X-Content-Type-Options` and `Cross-Origin-Resource-Policy` missing
- ZAP web scan: 0 FAIL, 4 WARN: no anti-clickjacking header, no `X-Content-Type-Options`, nginx version in the `Server` header, no CSP
- Locust: did not run (`ModuleNotFoundError: charset_normalizer`)

### Corrections

- None.

---

## 2026-11-17 — Third run: full pipeline green

### Evidence — [run 44177440833](https://github.com/shaiksadiq90/license-manager/actions/runs/44177440833) on `8311bda`

- ci-cd: passed. security-and-load: passed (Semgrep, ZAP API, ZAP web, Locust)
- Locust, 50 users × 2 min on a GitHub runner: 5,730 requests, **p95 = 4 ms, 0% errors**, max 76 ms, ~48 req/s
- This is a single Docker Compose host on a CI runner, not EKS. It does **not** prove the 99.9% / p95 < 500 ms SLO in AWS.

### Corrections

- None.

---

## 2026-11-17 — Branch history rewritten

The 4 commits on `security-and-load-testing` were rewritten to change the commit metadata only. The code is unchanged. The short SHAs in earlier entries now map like this:

| Old | New |
|---|---|
| `03570c1` | `c48012a` |
| `fee07d0` | `87c27b3` |
| `8311bda` | `3558811` |
| `4ff23c4` | `f99772d` |

The linked CI runs still point at the old SHAs.
