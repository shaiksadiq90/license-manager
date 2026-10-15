# Service Level Objectives - License API

| Service Level Indicator | Objective (30-day window) | Measured by |
|---|---|---|
| Availability: non-5xx responses / all responses | 99.9% (error budget about 43 minutes per month) | `slo:availability:ratio_rate5m` |
| Latency: 95th percentile request duration | under 500 ms | `slo:latency_p95:5m` |

## Alerting
- **ErrorBudgetFastBurn (page):** error rate above 14.4x the budget for 2 minutes. At that pace the whole monthly budget is gone in about 2 days.
- **LatencyP95High (ticket):** 95th percentile above 500 ms for 10 minutes.

## Error budget policy
- More than 50% of the budget left: ship normally.
- Under 25% left: only reliability fixes and low-risk changes go out.
- Budget used up: freeze feature deploys until the 30-day window recovers, and write a postmortem.
