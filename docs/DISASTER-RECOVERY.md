# Disaster Recovery

| Scenario | Recovery Time Objective | Recovery Point Objective | Mechanism |
|---|---|---|---|
| Pod or node failure | under 1 minute | 0 | 2+ replicas, PodDisruptionBudget, managed node group self-heals |
| Availability Zone loss | under 5 minutes | 0 | Nodes across 2 AZs; RDS Multi-AZ standby (set `multi_az = true` in prod) |
| Bad deploy | under 5 minutes | 0 | `helm upgrade --atomic` auto-rollback; manual `helm rollback license-manager <rev>` |
| Data corruption / accidental delete | under 1 hour | about 5 minutes | RDS point-in-time restore (7-day retention) |
| Full region loss | about 4 hours | 24 hours | Terraform re-apply in second region + cross-region snapshot copy |

## Runbook: point-in-time restore
1. `aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier license-manager-dev --target-db-instance-identifier license-manager-dev-restore --restore-time <UTC timestamp before incident>`
2. Wait until the instance is `available`, then validate row counts.
3. Update the `license-db` Kubernetes Secret with the new endpoint; `kubectl rollout restart deploy/api`.
4. Confirm `/readyz` returns 200 and the SLO dashboard is green.

## Failover test (run quarterly)
- `aws rds reboot-db-instance --db-instance-identifier license-manager-dev --force-failover`
- Expected: about 60-120 seconds of readiness failures, pods recover with no restart. Record the actual duration here.
- `kubectl delete pod -l app=api --wait=false`: confirm zero 5xx thanks to readiness probes + PodDisruptionBudget.
