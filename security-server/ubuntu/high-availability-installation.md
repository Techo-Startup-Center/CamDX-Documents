# CamDX Security Server — Ubuntu High Availability Installation

## Status: REQUIRES VERIFICATION

**This document is a structured validation/status record, not an approved 7.8.2 installation procedure.** Standalone 7.8.2 package validation (`7.8.2-1.ubuntu22.04` / `7.8.2-1.ubuntu24.04`) does **not** automatically validate the HA procedures below — no 7.8.2-specific HA evidence exists yet. The legacy HA guide it is based on was last confirmed against an older X-Road/CamDX release and uses infrastructure assumptions (PostgreSQL 14, a specific replication-port convention) that have not been independently re-verified for 7.8.2.

Do **not** treat this document as authorization to deploy an HA Security Server pair on 7.8.2 in production. Use it as a checklist of what must be re-validated first.

## 1. Legacy architecture summary (as documented, not yet re-validated)

- Master/slave Security Server pair behind an external load balancer (historically nginx).
- `serverconf` database: PostgreSQL streaming replication (hot standby) via a dedicated PostgreSQL instance separate from the default local database, historically on port `5433`.
- `keyconf` (software token + key configuration) replication: scheduled `rsync`+`ssh`.
- Other `/etc/xroad/` state (e.g. `db.properties`, `postgresql/*`, `globalconf/`, `conf.d/node.ini`) replicated the same way.
- **Not** replicated: the `messagelog` database, and OCSP response cache under `/var/cache/xroad`.
- Node role is set via `/etc/xroad/conf.d/node.ini` (`[node]` / `type=master` or `type=slave`).

## 2. Items requiring explicit 7.8.2 re-verification before this procedure can be trusted

| Item | Legacy assumption | Status |
|---|---|---|
| PostgreSQL version | 14 (dedicated replication cluster, historically port `5433`) | **REQUIRES VERIFICATION** |
| PostgreSQL streaming replication configuration | TLS-certificate-based replication, `pg_hba.conf` entries for the replica's network | **REQUIRES VERIFICATION** |
| `serverconf` architecture (separate cluster vs. shared) | Separate `pg_createcluster` instance dedicated to `serverconf` | **REQUIRES VERIFICATION** |
| `pg_hba.conf` / `postgresql.conf` specifics | Not fully enumerated in the legacy source | **REQUIRES VERIFICATION** |
| Replication certificates | Self-signed CA generated ad hoc via `openssl req`/`x509` | **REQUIRES VERIFICATION** — no CamDX-managed CA process documented |
| `rsync` state replication (scheduling, security) | Scheduled `rsync`+`ssh`, no further detail on cron/timer mechanism | **REQUIRES VERIFICATION** |
| `keyconf`/softtoken handling under replication | Replicated via the same `rsync`+`ssh` mechanism as other `/etc/xroad/` state | **REQUIRES VERIFICATION** — softtoken replication has significant security implications and needs explicit confirmation |
| `/etc/xroad` paths | As enumerated in §1 | **REQUIRES VERIFICATION** against the current 7.8.2 package layout |
| `node.ini` master/slave semantics | `[node] type=master` / `type=slave` | **REQUIRES VERIFICATION** — confirm unchanged in 7.8.2 |
| Load balancer behavior | Historically nginx, TCP `5500`/`5577` passthrough required | **REQUIRES VERIFICATION** |
| TCP `5500`/`5577` passthrough | Assumed required, consistent with [`../network-requirements.md`](../network-requirements.md) | **REQUIRES VERIFICATION** for the specific HA load-balancer configuration |
| Client traffic ports | Not separately documented for the HA case | **REQUIRES VERIFICATION** |
| Operational Monitoring deployment (external node) | A dedicated Opmonitor host, reached via port `2080` from master/slave | **REQUIRES VERIFICATION** |
| Backup/recovery implications | Not documented in the legacy source | **REQUIRES VERIFICATION** — a genuine documentation gap |

## 3. What is safe to reuse as architectural reference only

The legacy guide's high-level replication model (§1 above) and the historical Ansible playbook (`ansible/`) are retained as **architectural illustration only**. The Ansible example specifically uses Ubuntu 18.04, Ansible 2.9.27, and private lab IP addressing (`10.0.10.x`) — none of this should be treated as current operational guidance, and none of it has been carried into [`../network-requirements.md`](../network-requirements.md) or [`../provider-connectivity.md`](../provider-connectivity.md).

## 4. Next steps to reach VALIDATED status

1. Provision a 7.8.2 Ubuntu HA test pair and independently re-verify every row in §2 against the actual `7.8.2-1.ubuntu22.04`/`7.8.2-1.ubuntu24.04` packages.
2. Re-run the replication/failover procedure end-to-end and capture evidence (not merely re-transcribe the legacy steps).
3. Confirm current PostgreSQL version requirements against upstream X-Road 7.8.2 documentation.
4. Document a CamDX-specific replication-certificate issuance process, if one is intended, rather than an ad hoc `openssl` example.
5. Only after the above, convert this document's status from REQUIRES VERIFICATION to VALIDATED.

## 5. References

- Legacy source: `high_availability_security_server_installation_with_external_load_balancer.md`, `ansible/README.md` (this repository, `main` branch).
- [`../network-requirements.md`](../network-requirements.md) for the generic TCP `5500`/`5577` peer-connectivity requirement referenced above.

## 6. Change history

| Date | Change |
|---|---|
| 2026-09-24 | Created as a structured REQUIRES VERIFICATION status document as part of the CamDX-Documents 7.8.2 documentation architecture modernization. No procedural steps from the legacy guide are asserted as validated for 7.8.2. |
