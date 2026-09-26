# CamDX Security Server — RHEL High Availability Installation

## Status: REQUIRES VERIFICATION

**This document is a structured validation/status record, not an approved 7.8.2 installation procedure.** Standalone 7.8.2 RHEL 9 package validation (`7.8.2-2.el9`) does **not** automatically validate an HA procedure — no 7.8.2 RHEL 9 HA-specific evidence exists yet. The legacy RHEL HA guide it is based on predates the current RHEL 9 / 7.8.2 baseline (its standalone counterpart was RHEL 8 / X-Road 7.3.2) and is treated as historical evidence only.

Do **not** treat this document as authorization to deploy an HA Security Server pair on RHEL 9 / 7.8.2 in production.

## 1. Legacy architecture summary (as documented, not yet re-validated)

The legacy RHEL HA guide follows the same general master/slave, external-load-balancer, PostgreSQL-streaming-replication model described in the Ubuntu HA document (see [`../ubuntu/high-availability-installation.md`](../ubuntu/high-availability-installation.md) §1) — CamDX has historically documented the same HA architecture for both operating systems, with OS-specific service/package-manager commands substituted.

## 2. Items requiring explicit 7.8.2/RHEL 9 re-verification before this procedure can be trusted

All items listed in the Ubuntu HA document's §2 apply equally here (PostgreSQL version/replication, `serverconf` architecture, `pg_hba.conf`/`postgresql.conf`, replication certificates, `rsync` state replication, `keyconf`/softtoken handling, `/etc/xroad` paths, `node.ini` semantics, load-balancer behavior, port passthrough, Operational Monitoring deployment, backup/recovery) — **REQUIRES VERIFICATION** for all, with no RHEL 9-specific evidence available to this task.

Additional RHEL-specific items:

| Item | Status |
|---|---|
| SELinux (enforcing/permissive, custom policy for replication `rsync`/`ssh`/PostgreSQL ports) | **REQUIRES VERIFICATION** — not addressed anywhere in the legacy RHEL standalone or HA guides; a genuine documentation gap, consistent with the same gap noted in the RHEL standalone guide |
| firewalld rules for the HA-specific ports (PostgreSQL replication port, `rsync`/`ssh` between nodes, load-balancer passthrough) | **REQUIRES VERIFICATION** — the legacy guides document only the Admin UI port (`4000/tcp`) via firewalld; a complete HA-specific rule set has not been documented or confirmed |
| RHEL 9 service naming for HA-specific components (if any differ from the standalone service set) | **REQUIRES VERIFICATION** |

## 3. What is safe to reuse as architectural reference only

Same caveat as the Ubuntu HA document: the historical Ansible playbook (`ansible/`) uses Ubuntu 18.04 and private lab addressing, and is retained as architectural illustration only — it does not describe a RHEL topology at all and should not be treated as RHEL-applicable guidance.

## 4. Next steps to reach VALIDATED status

Same process as the Ubuntu HA document §4, performed independently against a RHEL 9 / `7.8.2-2.el9` HA test pair, with explicit attention to the SELinux and firewalld gaps in §2 above, which have no Ubuntu equivalent to fall back on.

## 5. References

- Legacy source: `rhel_high_availability_security_server_installation_with_external_load_balancer.md` (this repository, `main` branch) — treated as historical evidence only.
- [`../ubuntu/high-availability-installation.md`](../ubuntu/high-availability-installation.md) for the shared architectural model and verification checklist this document extends.
- [`../network-requirements.md`](../network-requirements.md).

## 6. Change history

| Date | Change |
|---|---|
| 2026-09-24 | Created as a structured REQUIRES VERIFICATION status document as part of the CamDX-Documents 7.8.2 documentation architecture modernization. No procedural steps from the legacy guide are asserted as validated for RHEL 9/7.8.2. |
