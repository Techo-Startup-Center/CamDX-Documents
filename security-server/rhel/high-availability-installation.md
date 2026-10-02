# CamDX Security Server — RHEL High Availability Installation

## Status: CAMDX 7.8.2 VALIDATION REQUIRED

**This document is an architecture + validation-readiness document, not an approved 7.8.2 installation procedure.** Standalone 7.8.2 RHEL 9 package validation (`7.8.2-2.el9`) does **not** automatically validate an HA procedure — no 7.8.2 RHEL 9 HA-specific runtime evidence exists yet.

**Do not treat this document as authorization to deploy an HA Security Server pair on RHEL 9 / 7.8.2 in production.** This document shares the replicated primary/secondary + external-load-balancer architecture described in full in [`../ubuntu/high-availability-installation.md`](../ubuntu/high-availability-installation.md) — CamDX has historically documented the same HA architecture for both operating systems, with OS-specific package-manager, service, and security-subsystem commands substituted. **This document does not simply copy the Ubuntu commands and swap `apt` for `dnf`** — it separately researches and states the RHEL 9-specific differences below. Read the Ubuntu HA document first for the full architectural narrative (§1–§11 there); this document does not repeat that narrative, only the RHEL-specific deltas.

Every claim below is classified as **UPSTREAM-CONFIRMED**, **CAMDX 7.8.2 VALIDATION REQUIRED**, or (where genuinely no evidence exists either upstream or from CamDX) an explicit documentation gap — never a bare `UNKNOWN`.

## 1. Shared architecture (unchanged from Ubuntu)

Every item in [`../ubuntu/high-availability-installation.md`](../ubuntu/high-availability-installation.md) §1 (overview), §3 (serverconf streaming replication architecture), §5 (state replication scope — including the corrected replication-exclusion table), §6 (`node.ini` semantics), §7 (external load balancer architectural requirements), §9 (failover/promotion — manual, not automatic), and §11 (Operational Monitoring policy) apply identically on RHEL 9. **Do not restate a different architecture for RHEL** — the only legitimate differences are the OS-level mechanics below.

## 2. PostgreSQL version — resolved from package metadata, still not a single fixed number

**Package-metadata question now resolved by direct, read-only inspection; CAMDX 7.8.2 VALIDATION REQUIRED remains for a live-host confirmation.**

**CamDX package dependency, confirmed directly (read-only, no install/rebuild, via `rpm -qpR` inside the existing Rocky Linux 9 build container already used for the RHEL standalone guide's own package inspection) against the frozen `7.8.2-2.el9` RPM artifacts:**
```text
$ rpm -qpR xroad-database-local-7.8.2-2.el9.noarch.rpm
postgresql-contrib
postgresql-server
xroad-base = 7.8.2-2.el9
...

$ rpm -qpR xroad-database-remote-7.8.2-2.el9.noarch.rpm
postgresql
xroad-base = 7.8.2-2.el9
...
```
**Same finding as Ubuntu (§2 of the Ubuntu HA document): the CamDX RHEL 9 package declares only a generic, unversioned dependency** (`postgresql-server`/`postgresql-contrib`, or plain `postgresql` for the remote-database package) — no exact major version is pinned by the RPM itself. The resolved version depends entirely on RHEL 9's own configured repositories (AppStream default vs. an alternate PGDG/module stream) at install time — a host/repository-configuration fact, not a CamDX package fact.

**Upstream guidance, verified directly against the X-Road `7.8.2` tag (IG-XLB v1.30, dated 2026-05-22):** the same version-agnostic statement applies — "RHEL 9, Ubuntu 20.04, 22.04 and 24.04 using PostgreSQL version 12 and later the configuration has some differences," with no exact RHEL 9 version asserted. **A later, NOT-YET-RELEASED `develop`-branch revision of this guide does state "RHEL 9 uses PostgreSQL 15"** — this sentence does not exist in the X-Road 7.8.2 tag (confirmed by direct comparison) and must not be cited as authoritative for the CamDX 7.8.2 baseline; see the Ubuntu HA document §2 for the full sourcing detail (introduced in develop's own v1.30, dated 2026-02-25, "Update PostgreSQL to version 15 on RHEL").

**No separately-evidenced CamDX validated runtime version exists either** — [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md) §17 independently reached the identical finding: "no specific PostgreSQL major version is pinned by the CamDX package itself; the actual version resolved depends on RHEL 9's default `postgresql` module/package stream at install time, and this task found no direct evidence establishing a specific version number to document as authoritative."

**Conclusion, explicitly not the same as blindly reusing the Ubuntu answer:** RHEL 9 and Ubuntu resolve their default `postgresql` package differently at the OS level (a fact this document does not need to prove, since neither the CamDX package nor the 7.8.2-tagged upstream guide pins an exact version for either OS in the first place) — but no exact major version can be stated as CamDX-proven for RHEL 9 from any evidence available to this task. **CAMDX 7.8.2 VALIDATION REQUIRED:** on an actual provisioned 7.8.2 RHEL 9 HA test host, confirm the resolved version directly (e.g. `rpm -q postgresql-server` after installation, or `dnf module list postgresql` if RHEL 9's modular AppStream applies) before prescribing exact commands/paths in §5 below.

## 3. SELinux — upstream-documented mechanisms, do not disable it

**Do not disable SELinux (`setenforce 0` / `SELINUX=disabled`) as a way to make HA replication "just work."** Two of the three mechanisms below are **UPSTREAM-CONFIRMED**, verified directly against IG-XLB v1.30 (X-Road 7.8.2 tag) — this is not merely a legacy-CamDX-guide convention:

- `semanage port -a -t postgresql_port_t -p tcp 5433` — **UPSTREAM-CONFIRMED** (IG-XLB §4.2.1.2, "on RHEL 8 and 9"): labels the dedicated `serverconf` replication port so PostgreSQL is permitted to bind it under SELinux, without a blanket policy change. Upstream's own worked example uses port `5433`.
- `setsebool -P rsync_client 1` and `setsebool -P rsync_full_access 1` — **UPSTREAM-CONFIRMED** (IG-XLB §5.2.1, "RHEL only: Configure SELinux to allow `rsync` to be run as a `systemd` service"): narrowly scoped booleans permitting the `rsync`+`ssh` configuration-sync mechanism to run as a systemd-managed client, rather than disabling SELinux enforcement for the whole system. Upstream adds its own caveat: "If the applications or services running on the system are customized, updating the SELinux policy to reflect the changes may be required."
- `semanage fcontext -a -t postgresql_etc_t "/etc/xroad/postgresql/*"` followed by `restorecon -v` — **NOT found in the current upstream IG-XLB (verified absent by direct text search of the 7.8.2 tag).** This is a **CamDX/legacy-guide-only practice**, not an upstream-documented mechanism — retained here as a plausible, narrowly-scoped exception consistent with the two upstream-confirmed items above, but its correctness/necessity is **CAMDX 7.8.2 VALIDATION REQUIRED**, not assumed from upstream authority.

**CAMDX 7.8.2 VALIDATION REQUIRED, specifically:**
- Sufficiency of the two upstream-confirmed mechanisms above on the actual CamDX RHEL 9 package/runtime (they are documented by upstream as generically correct for RHEL 8/9, not independently re-verified against the CamDX 7.8.2 build specifically).
- Whether the `postgresql_etc_t` fcontext labeling (legacy-CamDX-only, not upstream-sourced) is actually necessary or correct on RHEL 9, or whether it duplicates protection the `postgresql_port_t` port label and standard PostgreSQL data-directory contexts already provide.
- Any additional filesystem contexts needed for the specific PostgreSQL major version resolved in §2.
- AVC-free live execution: confirm no SELinux denial appears in `audit.log` (`ausearch -m avc -ts recent`) during an actual replication/sync test — do not assume the documented booleans are sufficient without observing a real run.

Do not publish a blanket `setenforce 0` instruction under any circumstance, including as a "temporary" troubleshooting step.

## 4. firewalld — narrow rules, not blanket opens

**CAMDX 7.8.2 VALIDATION REQUIRED**, with the general principle already established (UPSTREAM-CONFIRMED architecturally, since the required ports themselves are architectural, not RHEL-specific):

- The dedicated `serverconf` replication port (historically `5433`) must be open **only** between the primary and secondary nodes — not the whole `public` zone. The legacy guide's own `firewall-cmd --zone=public --add-port=5433/tcp` example is broader than necessary for a genuinely narrow HA deployment; prefer a `firewalld` rich rule or a dedicated zone scoped to the specific peer node's address wherever the target environment's network segmentation allows it, rather than a blanket `public`-zone open.
- SSH (`tcp/22`) between the nodes for the `rsync`+`ssh` configuration-propagation mechanism (§5 of the Ubuntu HA document) — again, scope to the specific peer address where possible, not a blanket allow.
- The load-balancer-facing ports (`5500`/`5577`, and whichever consumer-information-system client ports this deployment uses) per [`../network-requirements.md`](../network-requirements.md) — these are legitimately open more broadly, to the load balancer/authorized peer network, consistent with the standalone RHEL guide's own firewalld posture.

**This document does not publish a complete, CamDX-validated firewalld rule set for the HA case** — that remains **CAMDX 7.8.2 VALIDATION REQUIRED**, tracked explicitly rather than invented here. Do not publish or execute a blanket `firewall-cmd --add-port=.../tcp --permanent` across an entire zone as a shortcut.

## 5. RHEL-specific PostgreSQL cluster/service mechanics

**Correction: the legacy CamDX RHEL HA guide's `postgresql-setup --initdb --unit ... --port ...` pattern is upstream's documented RHEL 7 procedure, not the current RHEL 8/9 pattern.** Verified directly against IG-XLB v1.30 (X-Road 7.8.2 tag) §4.2.1, which explicitly splits this into two RHEL-version-specific subsections:

**§4.2.1.1 "on RHEL 7" (legacy pattern — do not use for RHEL 9):**
```bash
cat <<EOF >/etc/systemd/system/postgresql-serverconf.service
.include /lib/systemd/system/postgresql.service
[Service]
Environment=PGPORT=5433
Environment=PGDATA=/var/lib/pgsql/serverconf
EOF
```
```bash
PGSETUP_INITDB_OPTIONS="--auth-local=peer --auth-host=md5" postgresql-setup initdb postgresql-serverconf
semanage port -a -t postgresql_port_t -p tcp 5433
systemctl enable postgresql-serverconf
```

**§4.2.1.2 "on RHEL 8 and 9" (the current, correct pattern — UPSTREAM-CONFIRMED) — copy the installed unit, override PGPORT/PGDATA, then `initdb` directly, rather than `postgresql-setup --initdb --unit ...`:**
```bash
cp /lib/systemd/system/postgresql.service /etc/systemd/system/postgresql-serverconf.service
```
Then edit `/etc/systemd/system/postgresql-serverconf.service` and override:
```properties
[Service]
...
Environment=PGPORT=5433
Environment=PGDATA=/var/lib/pgsql/serverconf
```
Then initialize the dedicated data directory directly, as the `postgres` user, using the `initdb` binary appropriate to the installed PostgreSQL major version:
```bash
sudo su postgres
cd /tmp
initdb --auth-local=peer --auth-host=scram-sha-256 --locale=en_US.UTF-8 --encoding=UTF8 -D /var/lib/pgsql/serverconf/
exit
```
Upstream's own note: "if PostgreSQL is not installed with the default configuration, the database creation command may be different" — e.g. a PGDG-style versioned binary path such as `/usr/pgsql-13/bin/initdb -D /var/lib/pgsql/13/serverconf/` instead of the plain `/var/lib/pgsql/serverconf/` path shown above, depending on how PostgreSQL was actually installed on this specific host.

Then, identically to the RHEL 7 pattern:
```bash
semanage port -a -t postgresql_port_t -p tcp 5433
systemctl enable postgresql-serverconf
```

**Why this matters:** `postgresql-setup --initdb --unit <name> --port <port>` is a convenience wrapper specific to the RHEL 7-era `postgresql-setup` script's `--unit` support; upstream's own RHEL 8/9 procedure does not use it at all — it copies the base unit file and initializes the data directory with a direct `initdb` invocation instead. Publishing the RHEL 7 command as if it were current RHEL 9 guidance would be citing the wrong upstream procedure.

**Exact executable commands remain gated on §2's resolved PostgreSQL major version:** the plain `/var/lib/pgsql/serverconf` path above assumes a "default configuration" PostgreSQL install; if RHEL 9's actual resolved install uses a PGDG-style versioned path (as upstream's own alternate example shows), the `PGDATA`/`initdb` binary path must be adjusted accordingly. **CAMDX 7.8.2 VALIDATION REQUIRED:** confirm which of the two path conventions applies on an actual provisioned RHEL 9 host before publishing this as an unconditional executable procedure.

## 6. `rsync`/SSH under SELinux — service-account and key-handling care

In addition to the SELinux booleans in §3, the same significant security implication noted in the Ubuntu HA document §5 applies equally here: the `rsync`+`ssh` mechanism physically copies software-token/`keyconf` key material to every secondary node. On RHEL, additionally confirm:

- The dedicated `xroad-slave`-equivalent service account (the legacy guide's `xroad-slave` system user, used so the primary need not expose the primary `xroad` account's own SSH access) has correct SELinux user/role mapping (`semanage login`) if the target policy requires it — **CAMDX 7.8.2 VALIDATION REQUIRED**, not addressed in the legacy guide.
- The systemd-managed `rsync`+`ssh` sync unit (the Ubuntu HA document's `xroad-sync.service`/`.timer` pattern) runs correctly under RHEL 9's SELinux policy with only the `rsync_client`/`rsync_full_access` booleans from §3 — confirm no additional SELinux denial appears in `audit.log` (`ausearch -m avc -ts recent`) during a live test, rather than assuming the two booleans are sufficient without observing an actual run.

## 7. systemd/service-naming differences

**CAMDX 7.8.2 VALIDATION REQUIRED**, consistent with the same open item already tracked in [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md): confirm whether any HA-specific component (the configuration-sync timer/service, the dedicated `serverconf` PostgreSQL systemd unit) needs a different unit name or `.include`/`Requires=`/`After=` ordering on RHEL 9 specifically, beyond the already-confirmed native systemd unit inventory in the RHEL standalone guide. No RHEL-specific HA service beyond what is already described above (§5's dedicated PostgreSQL unit, and an `rsync`+`ssh` sync timer/service analogous to the Ubuntu HA document's) has been identified as necessary.

## 8. Filesystem ownership / SELinux context for replicated paths

**CAMDX 7.8.2 VALIDATION REQUIRED:** beyond the `postgresql_etc_t` context labeling in §3 for `/etc/xroad/postgresql/*`, confirm whether any other path touched by the HA-specific procedure (the dedicated PostgreSQL data directory `/var/lib/pgsql/serverconf`, the `xroad-slave`-equivalent service account's home directory) requires explicit SELinux context labeling beyond RHEL's default file-context policy for those parent paths. Not addressed in the legacy guide; not invented here.

## 9. External load balancer, administration semantics, failover, backup/restore, and Operational Monitoring

Identical architecture and classification to the Ubuntu HA document's §7–§11 — no RHEL-specific difference has been identified for any of these areas beyond the SELinux/firewalld mechanics already covered in §3–§4 above (e.g., a RHEL-hosted load balancer would use `firewalld` rather than Ubuntu's `ufw`/default-open posture for its own host firewall, but the Layer-4/TLS-passthrough architectural requirement itself is identical). Do not re-derive a separate RHEL-specific failover or backup/restore model — none is warranted; see the Ubuntu HA document §9–§11 directly.

## 10. Current CamDX validation status — summary

| Area | Classification |
|---|---|
| Shared architecture (§1) | Same as Ubuntu HA document §12 |
| PostgreSQL major version for `7.8.2-2.el9` | Package metadata confirmed (§2): generic, unversioned dependency (`postgresql-server`/`postgresql-contrib`) — no exact version pinned, none separately evidenced. CAMDX 7.8.2 VALIDATION REQUIRED via a live-host check; explicitly not assumed identical to Ubuntu's own (also unresolved) finding |
| SELinux: `postgresql_port_t` port label, `rsync_client`/`rsync_full_access` booleans | **UPSTREAM-CONFIRMED**, verified directly against IG-XLB v1.30 §4.2.1.2/§5.2.1 (X-Road 7.8.2 tag); CAMDX 7.8.2 VALIDATION REQUIRED for sufficiency on the CamDX RHEL 9 runtime and AVC-free live execution |
| SELinux: `postgresql_etc_t` fcontext/`restorecon` | **CamDX/legacy-guide-only — confirmed absent from the current upstream IG-XLB** by direct text search; CAMDX 7.8.2 VALIDATION REQUIRED for necessity/correctness, not upstream-sourced |
| firewalld rule set | Architecturally UPSTREAM-CONFIRMED (which ports need to reach which peers); CAMDX 7.8.2 VALIDATION REQUIRED for a complete, narrowly-scoped rule set |
| RHEL PostgreSQL cluster/service mechanics (§5) | **UPSTREAM-CONFIRMED** as the RHEL 8/9-specific pattern (copy unit + override + direct `initdb`), verified directly against IG-XLB v1.30 §4.2.1.2 — corrected from the RHEL 7-era `postgresql-setup --initdb --unit ...` pattern the legacy CamDX guide used; CAMDX 7.8.2 VALIDATION REQUIRED for exact paths against the resolved PostgreSQL version |
| `rsync`/SSH SELinux interaction | CAMDX 7.8.2 VALIDATION REQUIRED — not addressed in the legacy guide |
| systemd/service naming | CAMDX 7.8.2 VALIDATION REQUIRED — no known difference identified, not yet independently confirmed |
| Filesystem ownership/context for replicated paths | CAMDX 7.8.2 VALIDATION REQUIRED |

## 11. Next steps to reach APPROVED status

Same process as [`../ubuntu/high-availability-installation.md`](../ubuntu/high-availability-installation.md) §13, performed independently against a RHEL 9 / `7.8.2-2.el9` HA test pair, with explicit attention to the SELinux (§3) and firewalld (§4) items above, which have no Ubuntu equivalent to fall back on.

## 12. What is safe to reuse as architectural reference only

Same caveat as the Ubuntu HA document: the historical Ansible playbook (`ansible/`) uses Ubuntu 18.04 and private lab addressing, and is retained as architectural illustration only — it does not describe a RHEL topology at all and should not be treated as RHEL-applicable guidance.

## 13. References

- Legacy source: `rhel_high_availability_security_server_installation_with_external_load_balancer.md` (this repository, `main` branch) — treated as historical evidence; its `postgresql-setup --initdb --unit ...` pattern is upstream's own documented RHEL 7 procedure, not the RHEL 8/9 pattern this document now uses (§5); its SELinux/firewalld commands otherwise retained where upstream-confirmed (§3).
- [`../ubuntu/high-availability-installation.md`](../ubuntu/high-availability-installation.md) for the full shared architectural model, the corrected state-replication-scope table, the health-check/OPMON precision detail, and the failover/backup-gap discussion this document does not repeat.
- Upstream X-Road External Load Balancer Installation Guide (IG-XLB), **verified directly against the `nordic-institute/X-Road` GitHub tag `7.8.2`** (commit `2293fe4`) — **version 1.30, dated 2026-05-22**. The primary source for every UPSTREAM-CONFIRMED classification in this document, in particular §4.2.1.2 ("on RHEL 8 and 9") and §5.2.1 (RHEL SELinux booleans for `rsync`).
- [`../deployment-models.md`](../deployment-models.md), [`../network-requirements.md`](../network-requirements.md).
- `~/TI-Director-Brain/initiatives/camdx-xroad-upgrade/CAMDX_HA_DEPLOYMENT_MODELS_REVIEW.md` — full upstream source register and design-only HA validation plan.

## 14. Change history

| Date | Change |
|---|---|
| 2026-09-24 | Created as a structured REQUIRES VERIFICATION status document as part of the CamDX-Documents 7.8.2 documentation architecture modernization. No procedural steps from the legacy guide were asserted as validated for RHEL 9/7.8.2. |
| 2026-09-30 | Full modernization pass, aligned with the same-day Ubuntu HA document rewrite. Replaced the blanket "same items as Ubuntu, all REQUIRES VERIFICATION" structure with explicit RHEL 9-specific research: PostgreSQL version explicitly *not* assumed identical to Ubuntu (§2); SELinux booleans/context labels documented as the correct narrow-exception pattern with an explicit no-disable instruction (§3); firewalld guidance narrowed from the legacy blanket `public`-zone opens to peer-scoped rules where possible (§4); RHEL-native PostgreSQL cluster/service mechanics (copy the installed PostgreSQL service unit, override `PGPORT`/`PGDATA`, initialize with direct `initdb` — no `pg_createcluster` equivalent; the RHEL 7-era `postgresql-setup --initdb --unit ...` pattern is a different, older procedure, precisely distinguished from the RHEL 8/9 mechanism in the subsequent targeted evidence-correction round below) documented as an RHEL packaging difference from Ubuntu (§5); added `rsync`/SSH SELinux-interaction and filesystem-context items not previously tracked (§6, §8). Every item classified `UPSTREAM-CONFIRMED` or `CAMDX 7.8.2 VALIDATION REQUIRED` rather than a single blanket status. No HA deployment was executed to produce this document. |
| 2026-09-30 (targeted evidence correction round, same day) | Corrected two substantive factual issues found on direct re-verification against the X-Road `7.8.2` GitHub tag and the frozen `7.8.2-2.el9` RPM artifacts: (1) **§5 corrected** — the legacy CamDX guide's `postgresql-setup --initdb --unit postgresql-serverconf --port 5433` command is upstream's own documented **RHEL 7** procedure (IG-XLB §4.2.1.1); the current **RHEL 8/9** procedure (§4.2.1.2) instead copies the installed `postgresql.service` unit, manually overrides `PGPORT`/`PGDATA`, and runs `initdb` directly as the `postgres` user — this document previously (incorrectly) presented the RHEL 7 command as the RHEL 8/9-current pattern; both upstream subsections are now quoted exactly and distinguished. (2) **§3 reclassified** — the `semanage port -a -t postgresql_port_t` and `setsebool -P rsync_client`/`rsync_full_access` commands are confirmed **UPSTREAM-CONFIRMED** (present verbatim in IG-XLB v1.30 §4.2.1.2/§5.2.1), not merely a CamDX legacy-guide convention; the `semanage fcontext -t postgresql_etc_t`/`restorecon` step was searched for directly in the same tagged document and confirmed **absent** — reclassified as CamDX/legacy-guide-only, not upstream-sourced. (3) **§2 rewritten** with the actual `rpm -qpR` finding (read-only, via the existing Rocky Linux 9 build container): the RHEL 9 package also declares only a generic, unversioned PostgreSQL dependency, consistent with the identical Ubuntu finding and the 7.8.2-tagged upstream guide's own version-agnostic wording; a later, unreleased `develop`-branch "RHEL 9 uses PostgreSQL 15" mapping is explicitly flagged as not 7.8.2-authoritative. No architecture was redesigned; this document's overall `CAMDX 7.8.2 VALIDATION REQUIRED` status is unchanged. |
| 2026-09-30 (final mechanical publication fix, same day) | Corrected a stale, internally-contradictory phrase in the **2026-09-30 "Full modernization pass"** row above — it described the RHEL-native PostgreSQL mechanic as "systemd unit override + `postgresql-setup`," which is exactly the RHEL 7-era pattern the subsequent targeted-correction round (same table, row below) later identified as the *wrong* mechanism for RHEL 8/9. That historical row's wording is now corrected to describe the actual current finding (copy installed unit, override `PGPORT`/`PGDATA`, direct `initdb`) so the table no longer contradicts itself; the already-correct §5 procedure itself was not modified. |
