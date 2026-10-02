# CamDX Security Server — Ubuntu High Availability Installation

## Status: CAMDX 7.8.2 VALIDATION REQUIRED

**This document is an architecture + validation-readiness document, not an approved 7.8.2 installation procedure.** It replaces the previous minimal placeholder with a full description of the replicated external-load-balancer HA architecture, corrected against current upstream X-Road documentation and against this initiative's own re-derived evidence. Standalone 7.8.2 Ubuntu package validation (`7.8.2-1.ubuntu22.04` / `7.8.2-1.ubuntu24.04`) does **not** automatically validate this HA procedure — no 7.8.2-specific HA runtime evidence exists yet.

**Do not treat this document as authorization to deploy an HA Security Server pair on 7.8.2 in production.** Every claim below is explicitly classified as either **UPSTREAM-CONFIRMED** (verified directly against current upstream X-Road documentation) or **CAMDX 7.8.2 VALIDATION REQUIRED** (not yet independently re-verified against the actual `7.8.2-1.ubuntu22.04`/`7.8.2-1.ubuntu24.04` packages). This architecture is CamDX's **supported existing architecture** — real members use it today — and is **upstream-aligned**: it is not being removed, replaced, or deprecated by the existence of container or independent-Security-Server redundancy models. See [`../deployment-models.md`](../deployment-models.md) for how this model compares to those alternatives.

## 1. Architecture overview

A **primary** Security Server and one or more **secondary** Security Servers form a logical pair/cluster behind an external, member-operated load balancer. Consumers and providers see a single logical Security Server identity; the load balancer distributes connections across the underlying nodes.

**Terminology note (UPSTREAM-CONFIRMED):** current upstream documentation uses "primary"/"secondary" in prose, but the actual `/etc/xroad/conf.d/node.ini` configuration value is unchanged — it is still literally `type=master` or `type=slave`. This document uses "primary"/"secondary" in prose (matching current upstream terminology) while preserving the exact, unchanged configuration key/value syntax in every executable example. Do not invent a new `node.ini` syntax — none has been introduced upstream.

**What makes this "one logical Security Server":**
- A single Security Server Code/identity, shared configuration (`serverconf`), and shared key material (`keyconf`/software token) across all nodes.
- The external load balancer, not X-Road itself, is what makes the pair appear as one address to consumers/providers.

**What this architecture explicitly does not guarantee (UPSTREAM-CONFIRMED — state directly, do not overclaim):** upstream's own external-load-balancer documentation states this design's primary goal is **load balancing**, not fault tolerance — "a clustered environment increases fault tolerance but some X-Road messages can still be lost if a Security Server node fails." Primary-to-secondary failover is a **manual** operation, not automatic. Do not present this architecture as eliminating message loss on node failure.

## 2. PostgreSQL version — resolved from package metadata, still not a single fixed number

**CAMDX 7.8.2 VALIDATION REQUIRED for a live-host confirmation; the package-metadata question itself is now resolved by direct, read-only inspection.** The legacy CamDX HA guide hard-coded PostgreSQL 14 for every case. **This is not correct as a universal statement for 7.8.2.**

**CamDX package dependency, confirmed directly (read-only, no install/rebuild) against the frozen `7.8.2-1.ubuntu22.04`/`7.8.2-1.ubuntu24.04` `.deb` artifacts:**
```text
$ dpkg-deb -f xroad-database-local_7.8.2-1.ubuntu22.04_all.deb Depends
xroad-base (= 7.8.2-1.ubuntu22.04), postgresql | postgresql-9.4, postgresql-contrib | postgresql-contrib-9.4

$ dpkg-deb -f xroad-database-local_7.8.2-1.ubuntu24.04_all.deb Depends
xroad-base (= 7.8.2-1.ubuntu24.04), postgresql | postgresql-9.4, postgresql-contrib | postgresql-contrib-9.4
```
**Both Jammy and Noble declare an identical, generic, unversioned dependency** (`postgresql | postgresql-9.4` — an alternative-package clause naming only the OS's default `postgresql` meta-package, with a very old fallback, never a specific modern major version). **The CamDX package itself does not pin a PostgreSQL major version on either track.** The resolved major version instead depends entirely on what the target host's own configured package repositories currently define as the OS default at install time — a host/repository-configuration fact, not a CamDX package fact.

**Upstream guidance, verified directly against the X-Road `7.8.2` tag (`nordic-institute/X-Road`, tag `7.8.2`, commit `2293fe4`) — IG-XLB version 1.30, dated 2026-05-22:** the guide is explicitly version-agnostic for this exact case, stating "RHEL 9, Ubuntu 20.04, 22.04 and 24.04 using PostgreSQL version 12 and later the configuration has some differences" and, for the Ubuntu `pg_createcluster` step specifically, instructing the operator to run `pg_lsclusters` to determine which major version(s) are actually available on that host before proceeding — upstream's own worked example uses `16` purely as an illustrative value, not a prescription. **The X-Road 7.8.2 release does not map an exact PostgreSQL major version to any specific OS track.**

**Distinct from the above — a later, NOT-YET-RELEASED `develop`-branch revision of this same guide** (this task's research found the exact wording "RHEL 9 uses PostgreSQL 15, RHEL 10 uses PostgreSQL 16, Ubuntu 22.04 uses version 14, and Ubuntu 24.04 uses version 16," introduced by that branch's own v1.30 dated 2026-02-25 and extended by v1.32 dated 2026-04-22, both dated *after* the `7.8.2` tag) **does** state an explicit per-track mapping. **This sentence does not exist in the X-Road 7.8.2 tag and must not be cited as authoritative for the CamDX 7.8.2 baseline** — it reflects forward-looking upstream intent for a future X-Road release, recorded here only so a future reader does not mistake it for already-released 7.8.2 guidance.

**No separately-evidenced CamDX validated runtime version exists either** — [`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md) §13 independently reached the identical finding for the standalone (non-HA) case: "this task found no direct 7.8.2 package evidence establishing a specific version number to document as authoritative; inventing one would not be supported by evidence."

**Conclusion:** no single exact PostgreSQL major version can be stated as proven for either Ubuntu track from any evidence available to this task. **CAMDX 7.8.2 VALIDATION REQUIRED:** on an actual provisioned 7.8.2 Ubuntu HA test host, run `pg_lsclusters` (post-install) or `apt-cache policy postgresql` (pre-install) against that host's own configured repositories — exactly as upstream itself recommends — before prescribing an exact version in an executable procedure. Do not assume Ubuntu's own well-known distribution defaults (historically PostgreSQL 14 for 22.04, PostgreSQL 16 for 24.04) apply here without that live confirmation, since neither the CamDX package nor the 7.8.2-tagged upstream guide independently proves it.

## 3. `serverconf` streaming replication architecture

**UPSTREAM-CONFIRMED (architecture), CAMDX 7.8.2 VALIDATION REQUIRED (CamDX-specific parameters/values):**

- A **separate, dedicated PostgreSQL cluster/instance** is used for the `serverconf` database — not the same instance/port as any other local database — historically via `pg_createcluster -p 5433 <version> serverconf` on Ubuntu.
- The primary instance is the write target; streaming replication (hot standby) propagates `serverconf` to each secondary, which serves it read-only.
- TLS-certificate-based replication authentication (`hostssl replication ... cert` in `pg_hba.conf`, per-node client certificates signed by a dedicated CA) is the documented pattern, both in the legacy CamDX guide and consistent with current upstream guidance.

**Not yet re-verified for 7.8.2:** whether port `5433` remains the correct convention, whether the CamDX-specific `pg_createcluster` invocation needs adjustment for whatever PostgreSQL major version §2 ultimately confirms, and whether the exact `pg_hba.conf`/`postgresql.conf` structure below needs adjustment for that version's syntax (e.g. `wal_keep_size` vs. an older `wal_keep_segments` naming, which differs by PostgreSQL major version).

## 4. Replication settings — current parameter names, no invented CamDX values

**UPSTREAM-CONFIRMED**, current parameter names (verified against current upstream X-Road documentation — this section corrects the legacy guide's already-current naming rather than replacing it with something new):

**Primary instance:**
```text
ssl = on
ssl_ca_file = '/etc/xroad/postgresql/ca.crt'
ssl_cert_file = '/etc/xroad/postgresql/server.crt'
ssl_key_file = '/etc/xroad/postgresql/server.key'

listen_addresses = '*'          # or the specific interface secondaries connect over
wal_level = replica             # 'hot_standby' is accepted as a legacy synonym on older PostgreSQL; 'replica' is the current name
max_wal_senders = 3             # approximately (number of secondaries) + headroom — do not invent a CamDX-specific fixed value beyond upstream's own "approximately number of secondaries plus overhead" guidance
wal_keep_size = 8               # current parameter name (post-PostgreSQL 13); pre-13 uses wal_keep_segments instead — confirm which applies to the PostgreSQL major version §2 resolves
```

```text
# pg_hba.conf, on the primary
hostssl replication +secondarynode <secondary-node-CIDR> cert
```

**Secondary instance:**
```text
ssl = on
ssl_ca_file = '/etc/xroad/postgresql/ca.crt'
ssl_cert_file = '/etc/xroad/postgresql/server_<node>.crt'
ssl_key_file = '/etc/xroad/postgresql/server_<node>.key'
listen_addresses = 'localhost'  # read-only standby — do not expose beyond localhost unless a specific reason requires it

hot_standby = on
hot_standby_feedback = on

primary_conninfo = 'host=<primary-host> port=5433 user=<secondary-role> sslmode=verify-ca sslcert=/etc/xroad/postgresql/server_<node>.crt sslkey=/etc/xroad/postgresql/server_<node>.key sslrootcert=/etc/xroad/postgresql/ca.crt'
```

A `standby.signal` file (modern PostgreSQL) or a `recovery.conf` (older PostgreSQL, pre-12) marks the secondary as a standby — which mechanism applies depends on the PostgreSQL major version resolved in §2; do not assume one without checking.

**No CamDX-specific override values are invented here** — every value above is either a direct upstream example or an explicitly-flagged "confirm against the resolved PostgreSQL version" item. **CAMDX 7.8.2 VALIDATION REQUIRED** for the exact final values used in a real CamDX HA deployment.

## 5. State replication scope — corrected against upstream (important correction)

**This corrects a real inconsistency found in the legacy CamDX HA guide, verified directly against the X-Road `7.8.2`-tagged upstream documentation.** The legacy guide's own high-level summary (§2 of the historical document) listed `db.properties`, `postgresql/*`, `globalconf/`, and `conf.d/node.ini` as part of the replicated `/etc/xroad` state — but the guide's own actual `rsync` command **excluded** every one of those paths. **The command was correct; the prose summary was wrong.** Upstream's IG-XLB v1.30 (X-Road 7.8.2 tag) §2.3.1.3 confirms the exclusions are the correct, intentional behavior, each for a specific, upstream-stated technical reason — not an oversight to "fix" by replicating them:

| Item | Replicated? | Why (upstream's own stated reason, IG-XLB §2.3.1.3) |
|---|---|---|
| `serverconf` database | **Yes** — PostgreSQL streaming replication (§3–§4), not `rsync` | Shared logical configuration state; this is the actual replication mechanism for `serverconf`, distinct from the `rsync`-based state below |
| `signer/keyconf.xml` and the software token state under `signer/` | **Yes** — `rsync`+`ssh`, scheduled | This is genuinely shared cryptographic identity — AUTH/SIGN keys and their configuration must be identical across primary and secondary for both nodes to present the same Security Server identity. **This has a significant security implication: software-token key material is physically copied to every secondary node.** Treat the `rsync` transport (SSH key trust, restricted service account, file permissions on arrival) with the same care as any other private-key handling. |
| `db.properties` | **No** | Upstream: "(node-specific)" — each node's own `db.properties` correctly points to its own local view of the replicated `serverconf` instance, so this file **must** differ per node, not be overwritten by the primary's copy |
| `postgresql/*` (under `/etc/xroad/postgresql/`) | **No** | Upstream: "(node-specific keys and certs)" — each node has its own TLS certificate/key pair for the PostgreSQL replication connection itself (§3–§4); overwriting a secondary's own key material with the primary's would break, not help, replication |
| `globalconf/` | **No** | Upstream: "(syncing globalconf could conflict with `confclient`)" — each node's own `xroad-confclient` independently fetches and maintains its own global configuration cache |
| `conf.d/node.ini` | **No** | Upstream: "(specifies node type: primary or secondary)" — this is precisely the file that tells each node whether it is `type=master` or `type=slave`; replicating it would make every node claim the same role, which is self-defeating by construction |
| `messagelog` database | **No** | Each node maintains its own separate message-log database instance, not a shared/replicated one — upstream states this explicitly (§2.3.2.1) and gives the reason: `serverconf` and `messagelog` must be on **separate** PostgreSQL instances specifically so `serverconf`'s streaming replication does not also try to replicate `messagelog` |
| OCSP response cache (`/var/cache/xroad`) | **No** | Upstream (§2.3.2.2): not replicated by design — replicating it "could make the cluster more fault tolerant but the replication cannot simultaneously create a single point of failure," and a distributed cache would be needed to do so safely; none is implemented |

**If this document is ever revised to claim any of the "No" rows above should be replicated, that is a substantive architecture change requiring its own explicit decision — it must not be silently reintroduced by copying the legacy guide's prose summary instead of its actual command.**

### 5.1 Architecture-level exclusions vs. command-level implementation exclusions — do not conflate them

The table above lists the **architecture-level exclusions** — the four items upstream explicitly names and explains a reason for (§2.3.1.3). Upstream's actual executable `rsync` commands additionally exclude a small number of **implementation-level** items that upstream does not individually explain, and this document does not invent an explanation for them either:

- `*.tmp` — excluded only in the scheduled/systemd-timer variant of the sync command, not the one-time initial sync.
- `/gpghome` — excluded in both the initial and scheduled sync commands.

Upstream's own two commands, quoted exactly (IG-XLB v1.30, X-Road 7.8.2 tag):

**Initial one-time sync (§3.3, secondary installation, step 6):**
```bash
sudo -u xroad rsync -e ssh -avz --delete --exclude db.properties --exclude "/postgresql" --exclude "/conf.d/node.ini" --exclude "/gpghome" xroad-slave@<primary>:/etc/xroad/ /etc/xroad/
```

**Scheduled `xroad-sync.service` (systemd timer, §5.2.1):**
```bash
rsync -e "ssh -o ConnectTimeout=5 " -aqz --timeout=10 --delete-delay --exclude db.properties --exclude "/conf.d/node.ini" --exclude "*.tmp" --exclude "/postgresql" --exclude "/globalconf" --exclude "/gpghome" --delay-updates --log-file=/var/log/xroad/slave-sync.log ${XROAD_USER}@${MASTER}:/etc/xroad/ /etc/xroad/
```

Adapt the **scheduled** variant (the one CamDX has historically operationalized via a systemd timer) as the reference command for this document — it is the more complete of the two upstream examples and includes `/globalconf` explicitly. **CAMDX 7.8.2 VALIDATION REQUIRED:** confirm this exact flag set still applies unchanged against the CamDX 7.8.2 package's actual `/etc/xroad` layout before treating it as an executable procedure.

## 6. `node.ini` semantics

**UPSTREAM-CONFIRMED:** the configuration key and its accepted values are unchanged — `/etc/xroad/conf.d/node.ini`:
```ini
[node]
type=master
```
or
```ini
[node]
type=slave
```
Current upstream prose refers to these roles as "primary" and "secondary," but the literal configuration value remains `master`/`slave` — **do not invent `type=primary`/`type=secondary`**, upstream has not introduced that syntax. The primary is the only node where configuration changes should originate; secondaries treat their replicated configuration as read-only (see §8 for how this is enforced administratively, not merely by convention).

**CAMDX 7.8.2 VALIDATION REQUIRED:** confirm this key/value pair is unchanged in the actual `7.8.2-1.ubuntu22.04`/`7.8.2-1.ubuntu24.04` packages (expected to be unchanged, since it is core upstream behavior, but not yet independently re-verified against the frozen 7.8.2 packages the way the standalone guide's systemd unit inventory was).

## 7. External load balancer

**UPSTREAM-CONFIRMED architectural requirements**, verified directly against IG-XLB v1.30 (X-Road 7.8.2 tag) — documented here as requirements, not a specific vendor's exact configuration; the legacy `nginx` example is retained separately in §7.2 as one worked example, not the only supported option:

- **Layer 4 / TCP-level load balancing with TLS passthrough is required** — "the load balancer must be configured to use TLS passthrough so that TLS termination is performed by the Security Server and not by the load balancer." Any load balancer capable of this (nginx `stream{}`, HAProxy, a cloud NLB, or a hardware appliance) is acceptable; none is CamDX-mandated over another.
- **Ports requiring passthrough:** `5500` (X-Road message exchange) and `5577` (peer/OCSP-related traffic, per [`../network-requirements.md`](../network-requirements.md)) at minimum; the consumer-information-system client ports (`8080`/`8443` per current upstream default, or CamDX's historically-documented `80`/`443` — see the standalone guide's own open `client-http-port`/`client-https-port` item) depending on what this specific deployment's consumer traffic model requires. **Also disable client-side pooled/persistent HTTP connections** (`[proxy] server-support-clients-pooled-connections=false` in `/etc/xroad/conf.d/local.ini` on the primary) — upstream states this explicitly, because load balancing operates at the TCP level and persistent connections would defeat even traffic distribution across nodes.
- **Proxy admin port `5566`:** used for maintenance-mode control (see below), separate from the `5588` health-check port.

### 7.1 Health-check service (`5588`) — application-aware, not a bare TCP probe

**UPSTREAM-CONFIRMED (IG-XLB v1.30 §3.4, X-Road 7.8.2 tag).** The health-check service is disabled by default (`health-check-port = 0`) and, once enabled (`health-check-port=5588` in `/etc/xroad/conf.d/local.ini` on the primary, replicated to all nodes), responds over **plain HTTP** (not HTTPS) with:

| Response | Meaning |
|---|---|
| `HTTP 200 OK` | Healthy — the proxy should be able to process messages |
| `HTTP 500 Internal Server Error` | Failed health check — a short failure-reason message is included in the response body |
| `HTTP 503 Service Unavailable` (message: `Health check interface is in maintenance mode`) | The node has been deliberately placed into maintenance mode |

**Checks actually performed** (upstream's own list): the server authentication key is accessible and the software token is logged in (via a running `xroad-signer`); the OCSP response for the certificate is `good` (also via `xroad-signer`); the `serverconf` database is accessible; the global configuration is valid and not expired. Each individual check has its own 5-second timeout; a timeout counts as a failure.

**Caching behavior — the health check is not an instantaneous, perfect oracle:** a successful result is cached for 2 seconds before the next real check runs; a failed result is cached for 30 seconds (to let the server recover after a restart before being re-queried); the software-token logged-in/out state specifically is cached separately for 300 seconds. This makes `5588` substantially more informative than a bare TCP probe, but a load balancer relying on it can still act on a result that is up to several seconds — or, for the token-state component specifically, up to 300 seconds — stale.

**Maintenance mode:** enabled/disabled via `HTTP GET` to the **proxy admin port `5566`** (not `5588`) — `http://localhost:5566/maintenance?targetState=true` / `...=false` — returns `200 OK` with a confirmation message; automatically resets to disabled on the next `xroad-proxy` restart.

**CAMDX 7.8.2 VALIDATION REQUIRED:** confirm this exact behavior (response codes, checks performed, caching windows) is unchanged in the CamDX 7.8.2 Ubuntu build, and confirm the external load balancer's own health-check polling interval is compatible with the caching windows above (a poll faster than 2 seconds gains nothing; a poll much slower than 30 seconds delays detecting a real failure).

### 7.2 Worked nginx example (illustrative only, not CamDX-mandated)

The legacy CamDX guide's `nginx stream{}` passthrough configuration for `5500`/`5577` (and, if applicable, the client ports) remains a valid worked example of the Layer-4/TLS-passthrough requirement above and is retained as illustrative reference material — see `high_availability_security_server_installation_with_external_load_balancer.md` (this repository, historical). It is not the only conformant configuration, and its specific IP/FQDN placeholders must never be copied verbatim into a real deployment.

## 8. Administration semantics on secondary nodes

**UPSTREAM-CONFIRMED**, verified directly against IG-XLB v1.30 (X-Road 7.8.2 tag) §3.3, step 8: secondary nodes must be administratively restricted to prevent configuration drift, not merely left alone by convention:

- Remove the `xroad-registration-officer`, `xroad-service-administrator`, and `xroad-system-administrator` groups/roles from secondary-node Admin UI accounts.
- Retain only `xroad-security-officer` (needed for local PIN entry/token operations) on a secondary — upstream: "otherwise you will not be able to enter token PIN codes."
- The management REST API on a secondary rejects configuration-modification calls; read-only access uses API keys associated with the `xroad-securityserver-observer` role (also usable, together with `xroad-security-officer`, for entering token PIN codes via the API). Keys not associated with `xroad-securityserver-observer` have no access to the secondary at all.
- **API-key caching caveat (upstream-stated):** API keys are replicated from primary to secondaries but are read through a cache on each node. If a key is revoked or its permissions changed on the primary, that change is **not** reflected on a secondary's own cache until `xroad-proxy-ui-api` is restarted on that secondary — do not assume an API-key revocation takes effect on secondaries immediately.
- Upstream also notes Security Server installation scripts detect node type and adjust user-group creation accordingly on **install**; a version **upgrade** does not overwrite or modify this configuration.

**CAMDX 7.8.2 VALIDATION REQUIRED:** confirm these exact role/group names and the API-key-caching behavior are unchanged in the 7.8.2 package baseline, and document the specific administrative steps (Admin UI role removal, API key scoping) as an executable procedure once a 7.8.2 HA test pair is available — this document states the current upstream requirement, it does not yet provide a CamDX-tested step-by-step for it.

## 9. Failover and primary promotion — do not invent a procedure

**UPSTREAM-CONFIRMED, stated plainly rather than smoothed over:**

- There is **no automatic failover/promotion mechanism** for the Security Server role itself. If the primary becomes unavailable, secondaries continue serving already-replicated configuration and can continue processing message traffic that does not require a configuration change, but **no node automatically promotes itself to primary**.
- **Configuration changes cannot originate anywhere while no primary is available** — by design, only the primary accepts configuration changes; if it is down, configuration changes must wait for it to return or for an operator to manually designate a different node as the new primary (by changing that node's own `node.ini` and re-establishing the replication topology in the new direction) — a manual, not automated, operational procedure.
- **What CamDX must still validate before this can be called APPROVED:** the exact operator runbook for manual promotion (which upstream does not prescribe as a turnkey script), the behavior of in-flight messages during a primary outage, and how the external load balancer's own health-check configuration should react during a primary outage (routing all traffic to secondaries for read/serve-only behavior, vs. some other policy) — none of this is invented here.

## 10. Backup, restore, and disaster recovery — closing a genuine documentation gap

**This is a genuine gap in both the legacy CamDX guide and current upstream's own external-load-balancer documentation** — upstream's guide covers installation, replication setup, and version upgrades, but explicitly contains no backup/restore/disaster-recovery section for the clustered case. This section does not invent a procedure to fill that gap; it defines what must be validated before one can be written.

**Backup scope must distinguish three different kinds of state (§5), not treat all non-replicated data identically:**

| Category | Examples | Backup implication |
|---|---|---|
| Durable/shared configuration state | `serverconf` database, `signer/keyconf.xml`/software token | Must be backed up — this is the member's actual identity/configuration and cannot be regenerated |
| Per-node message-log/archive state | `messagelog` database (node-local, per §5) | Must be backed up **per node**, independently — each node holds records the other does not, since `messagelog` is explicitly not replicated |
| Rebuildable/cache state | OCSP response cache (`/var/cache/xroad/`) | **Not a backup candidate by default** — upstream states this cache is deliberately not replicated/made fault-tolerant, and it is expected to regenerate itself from a live OCSP responder query rather than from a restored backup. **CAMDX 7.8.2 VALIDATION REQUIRED:** confirm regeneration/recovery time and behavior after a cold start with an empty cache (e.g. whether message processing stalls waiting for a fresh OCSP response, or proceeds and backfills the cache), rather than assuming this cache needs to be part of the backup set. Do not add it to the backup scope unless a specific piece of authoritative X-Road evidence is found requiring that. |

**CAMDX 7.8.2 VALIDATION REQUIRED — none of the following currently has a documented, tested procedure for the HA case specifically:**

- Confirm the three-category backup scope above against real HA runtime behavior — does a backup need to be taken from the primary only for the shared state, plus independently from each node for its own `messagelog`?
- Restore semantics: restoring a backup onto a rebuilt primary must not silently break the existing replication relationship with its secondaries (stale replication slots/certificates, a `serverconf` state that no longer matches what secondaries expect).
- Full disaster-recovery scenario: both the shared `serverconf` database and one or more secondaries' `rsync`-replicated state (`keyconf`/software token) are lost or corrupted simultaneously — what is recoverable, and from what.
- Interaction with the standalone guides' own backup guidance (§19 of the standalone documents' reboot-validation split) — the HA case has not yet had an equivalent full-deployment-level checkpoint defined.

This gap is tracked explicitly in the design-only HA validation plan (`CAMDX_HA_DEPLOYMENT_MODELS_REVIEW.md`, initiative workspace) — no destructive backup/restore test has been executed as part of this documentation round.

## 11. Operational Monitoring for the HA/external-LB topology

Canonical CamDX policy is unchanged: OPMON capability **MANDATORY**, **local = default**, **remote/external = supported alternative, not HA-only**.

**Two distinct claims — keep them separate, do not classify them identically:**

**(a) Basic external-OPMON architecture (a single Security Server pointed at a dedicated external Opmonitor daemon): UPSTREAM-CONFIRMED, no caveat.** This is a standard, generally-applicable X-Road capability — the primary/secondary Security Servers are pointed at the Opmonitor host via `[op-monitor] host = <opmonitor-host>` / `scheme = <scheme>` / `port = <port>` in `local.ini` (defaults: `host = localhost`, `port = 2080`, `scheme = HTTP`), with local OPMON stopped/disabled on the Security Server once the external Opmonitor is confirmed working. This part carries no support caveat and applies equally to non-HA standalone deployments.

**(b) The cluster-specific extension actually used by this HA topology — one external Opmonitor shared by multiple clustered (primary/secondary) Security Servers: UPSTREAM-DOCUMENTED / CLUSTER-SPECIFIC CONFIGURATION NOT OFFICIALLY SUPPORTED BY UPSTREAM / CAMDX 7.8.2 VALIDATION REQUIRED.** Upstream describes this exact configuration (UG-SS §15.2.4) — it is not undocumented — but immediately qualifies it (see the caveat below). **Do not classify (b) as plain "UPSTREAM-CONFIRMED"** — that wording could be misread as "officially supported," which upstream itself explicitly denies for this specific cluster arrangement.

**HTTPS/TLS trust for external OPMON: UPSTREAM-CONFIRMED / STRONGLY ADVISED BY UPSTREAM.** This question is now closed by direct verification against the X-Road Security Server User Guide (UG-SS) §15.2.4, at the `7.8.2` tag: **"It is strongly advised to use HTTPS for requests between a Security Server and the associated external operational monitoring daemon."** §15.2.5 continues: "As advised, the scheme parameter should be set to 'https'. For communication over HTTPS, the Security Server and the operational monitoring daemon must know each other's TLS certificates to enable the Security Server to authenticate to the monitoring daemon successfully." **Do not retain "unknown whether upstream recommends HTTPS" — it is resolved: upstream explicitly and strongly advises HTTPS, not bare HTTP over TCP `2080`.**

The upstream-documented mechanism, exactly: the Security Server's own internal TLS certificate (`/etc/xroad/ssl/internal.crt`, exportable via the Admin UI per UG-SS §10.4) is copied to the external Opmonitor host and referenced there as `[op-monitor] client-tls-certificate = <path>` in its own `local.ini`; separately, a TLS key/certificate pair is generated **on the Opmonitor host itself** via the `generate-opmonitor-certificate` script, and the resulting `opmonitor.crt` is copied back to the Security Server and referenced there as `[op-monitor] tls-certificate = <path>`. This is a genuine bidirectional certificate exchange, not a one-way trust relationship.

**gRPC keystore/truststore — narrowly scoped, not a blanket OPMON requirement.** Upstream states this requirement applies **specifically** to "the request traffic visualization on the Security Server UI Diagnostics page" — a separate keystore/truststore pair (managed via `keytool`/`openssl`, not the `internal.crt`/`opmonitor.crt` exchange above) is needed only if that specific UI visualization feature is used. Do not require gRPC keystore/truststore configuration for basic external-OPMON data exchange itself.

**The basis for classification (b)'s caveat, quoted exactly:** UG-SS §15.2.4 states plainly, immediately after describing this exact configuration (one external Opmonitor serving multiple clustered Security Servers): **"The setup of clustered Security Servers is not officially supported yet and has been implemented for future compatibility."** This is a direct upstream statement about the specific combination this document covers (a shared external Opmonitor serving a primary/secondary cluster) — it does not, by itself, mean the underlying primary/secondary replication architecture (IG-XLB) is unsupported; IG-XLB is upstream's own dedicated, detailed installation guide for that architecture. But it is the direct, sourced reason classification (b) above is worded as "not officially supported by upstream" rather than plain "UPSTREAM-CONFIRMED," and it must not be omitted from this document.

**CamDX 7.8.2 implementation/runtime: CAMDX VALIDATION REQUIRED.** None of the mechanism above (bidirectional TLS certificate exchange, `scheme=https`, gRPC keystore/truststore where the UI Diagnostics feature is used) has yet been independently exercised against the actual CamDX 7.8.2 `xroad-opmonitor`/`xroad-addon-opmonitoring` packages. **Do not reproduce the legacy "port 2080, plain HTTP, no further security guidance" pattern** — it is now confirmed inconsistent with upstream's own strong HTTPS advisory.

## 12. Current CamDX validation status — summary

| Area | Classification |
|---|---|
| Overall replicated-primary/secondary + external-LB architecture | UPSTREAM-CONFIRMED (architecture exists and is documented by upstream, IG-XLB v1.30 / X-Road 7.8.2 tag); CAMDX 7.8.2 VALIDATION REQUIRED (runtime). See the OPMON rows below — upstream additionally notes the shared-external-Opmonitor-for-a-cluster *configuration* specifically is "not officially supported yet" (§11(b)) — a further reason this stays VALIDATION REQUIRED, not a contradiction of IG-XLB's own dedicated guide for the replication architecture itself. |
| PostgreSQL major version for CamDX 7.8.2 Ubuntu tracks | Package metadata confirmed (§2): both tracks declare only a generic, unversioned dependency — no exact version pinned by the CamDX package on either track, and none separately evidenced as a validated runtime value. CAMDX 7.8.2 VALIDATION REQUIRED via a live `pg_lsclusters`/`apt-cache policy` check, per upstream's own recommended method. |
| Replication parameter names (§4) | UPSTREAM-CONFIRMED (current naming, IG-XLB v1.30); CAMDX 7.8.2 VALIDATION REQUIRED (exact values for this deployment) |
| State replication scope (§5) | UPSTREAM-CONFIRMED (IG-XLB v1.30 §2.3.1.3/§2.3.2 — this section corrects the prior inconsistency); architecture-level vs. command-level exclusions now explicitly distinguished (§5.1) |
| `node.ini` semantics | UPSTREAM-CONFIRMED (syntax, IG-XLB v1.30 §3.2/§3.3); CAMDX 7.8.2 VALIDATION REQUIRED (confirm unchanged in the 7.8.2 package) |
| External load balancer requirements | UPSTREAM-CONFIRMED (architecture, IG-XLB v1.30 §2.1); CAMDX 7.8.2 VALIDATION REQUIRED (this deployment's specific ports/health-check wiring) |
| Health-check-port 5588 (§7.1) | UPSTREAM-CONFIRMED in full detail (response codes, checks performed, caching windows — IG-XLB v1.30 §3.4); CAMDX 7.8.2 VALIDATION REQUIRED (native `health-check-port` behavior remains open per the standalone guides) |
| Secondary-node administrative restriction (§8) | UPSTREAM-CONFIRMED (requirement and API-key-caching behavior, IG-XLB v1.30 §3.3 step 8); CAMDX 7.8.2 VALIDATION REQUIRED (exact 7.8.2 role names, tested procedure) |
| Failover/promotion | UPSTREAM-CONFIRMED (manual, no automatic promotion) |
| Backup/restore/DR (§10) | Genuine gap — neither upstream nor CamDX has a documented procedure; three-category backup scope now distinguished (durable/shared, per-node message-log, rebuildable/cache); CAMDX 7.8.2 VALIDATION REQUIRED from first principles |
| External OPMON basic architecture — single SS + dedicated Opmonitor (§11(a)) | UPSTREAM-CONFIRMED, no caveat — standard, generally-applicable capability, not HA-specific |
| External OPMON cluster-specific configuration — shared Opmonitor for a primary/secondary cluster (§11(b)) | **UPSTREAM-DOCUMENTED / CLUSTER-SPECIFIC CONFIGURATION NOT OFFICIALLY SUPPORTED BY UPSTREAM / CAMDX 7.8.2 VALIDATION REQUIRED** — do not read as plain "UPSTREAM-CONFIRMED" |
| External OPMON HTTPS/TLS trust (§11) | UPSTREAM-CONFIRMED / STRONGLY ADVISED BY UPSTREAM — resolved this round (UG-SS §15.2.4/§15.2.5, X-Road 7.8.2 tag); no longer an open question; applies to both (a) and (b) equally |
| External OPMON CamDX implementation/runtime (§11) | CAMDX VALIDATION REQUIRED — bidirectional TLS certificate exchange and `scheme=https` not yet exercised against the CamDX 7.8.2 packages |

## 13. Next steps to reach APPROVED status

1. **On the actual provisioned 7.8.2 Ubuntu HA test host(s)**, determine the PostgreSQL major version actually resolved by that host's configured repositories/runtime — via `pg_lsclusters` (post-install) or `apt-cache policy postgresql` (pre-install), exactly as upstream itself recommends — and record the result as runtime validation evidence. **Do not repeat this as a package-metadata lookup** — §2 already establishes, from direct read-only inspection of the frozen `.deb` artifacts, that neither Jammy nor Noble's CamDX package pins an exact major version; the open action is a live-host confirmation, not a metadata re-check.
2. Provision a 7.8.2 Ubuntu HA test pair and independently re-verify every §12 "CAMDX 7.8.2 VALIDATION REQUIRED" row against the actual packages, capturing evidence, not merely re-transcribing this document.
3. Execute the design-only validation plan in `CAMDX_HA_DEPLOYMENT_MODELS_REVIEW.md` (initiative workspace) — covering cluster establishment, replication, failover, backup/restore, and the full item list there — and record results as evidence.
4. Only after the above, convert this document's status from `CAMDX 7.8.2 VALIDATION REQUIRED` to `APPROVED`.

## 14. What is safe to reuse as architectural reference only

The historical Ansible playbook (`ansible/`) illustrates this architecture but uses an obsolete Ubuntu/Ansible baseline and private lab addressing — retained as architectural illustration only, never as current operational guidance, and never carried into [`../network-requirements.md`](../network-requirements.md) or [`../provider-connectivity.md`](../provider-connectivity.md).

## 15. References

- Legacy source: `high_availability_security_server_installation_with_external_load_balancer.md`, `ansible/README.md` (this repository, `main` branch) — treated as historical evidence, corrected where inconsistent with current upstream (§5).
- Upstream X-Road External Load Balancer Installation Guide (IG-XLB), **verified directly against the `nordic-institute/X-Road` GitHub tag `7.8.2`** (commit `2293fe4`) — **version 1.30, dated 2026-05-22**. This is the release-specific, authoritative version for the CamDX 7.8.2 baseline; it is the primary source for every UPSTREAM-CONFIRMED classification in this document except where otherwise noted. A later, unreleased `develop`-branch revision (as of this research, version 1.33) differs in one respect noted explicitly in §2 (PostgreSQL-version-to-OS-track mapping) — that later material is not cited as 7.8.2-authoritative anywhere in this document.
- Upstream X-Road Security Server User Guide (UG-SS), same tag (`7.8.2`) — §10.4, §15.2.3–15.2.5, the source for §11's OPMON HTTPS/TLS-trust/gRPC-scope findings.
- [`../deployment-models.md`](../deployment-models.md) for how this architecture compares to the independent-Security-Server and container/Kubernetes redundancy models.
- [`../network-requirements.md`](../network-requirements.md) for the generic TCP `5500`/`5577` peer-connectivity requirement referenced above.
- `~/TI-Director-Brain/initiatives/camdx-xroad-upgrade/CAMDX_HA_DEPLOYMENT_MODELS_REVIEW.md` — full upstream source register and design-only HA validation plan.

## 16. Change history

| Date | Change |
|---|---|
| 2026-09-24 | Created as a structured REQUIRES VERIFICATION status document as part of the CamDX-Documents 7.8.2 documentation architecture modernization. No procedural steps from the legacy guide were asserted as validated for 7.8.2. |
| 2026-09-30 | Full modernization pass. Replaced the minimal placeholder with a complete architecture + validation-readiness document, researched directly against current upstream X-Road documentation. Corrected the legacy guide's state-replication-scope inconsistency (§5) — the legacy prose claimed `db.properties`/`postgresql/*`/`globalconf/`/`conf.d/node.ini` were replicated, while its own `rsync` command (and current upstream guidance) correctly excludes all four for specific, now-documented reasons. Removed the hard-coded PostgreSQL 14 assumption (§2) pending confirmation of the actual per-track dependency. Updated replication parameter names to current upstream naming (§4) without inventing CamDX-specific values. Added administrative-restriction requirements for secondary nodes (§8), explicit no-automatic-failover statement (§9), a new backup/restore/disaster-recovery gap section (§10), and application-aware health-check guidance for port `5588` (§7, §12) rather than the prior bare-TCP-only framing. Reclassified overall status from `REQUIRES VERIFICATION` to the more precise `CAMDX 7.8.2 VALIDATION REQUIRED`, with every individual claim now explicitly labeled `UPSTREAM-CONFIRMED` or `CAMDX 7.8.2 VALIDATION REQUIRED` rather than a single blanket status. No HA deployment was executed to produce this document. |
| 2026-09-30 (targeted evidence correction round, same day) | Corrected several factual issues found on direct re-verification against the X-Road `7.8.2` GitHub tag: (1) IG-XLB cited as version **1.30** (2026-05-22), not a later `develop`-only version — the tag's own version history was directly inspected. (2) §2 rewritten with the actual CamDX package-metadata finding (`dpkg-deb -f ... Depends`, read-only, against the frozen `.deb` artifacts): both Jammy and Noble declare only a generic, unversioned PostgreSQL dependency, matching the 7.8.2-tagged IG-XLB's own version-agnostic guidance (`pg_lsclusters`-based, not a fixed mapping); a later, unreleased `develop`-branch mapping (RHEL9→15 etc.) is explicitly flagged as not 7.8.2-authoritative. (3) §5 gained an explicit architecture-level-vs-command-level exclusion distinction (§5.1), with both upstream `rsync` commands quoted exactly as they appear in the 7.8.2 tag. (4) §7 restructured: fixed a broken "§9 below" cross-reference and added a full application-aware health-check subsection (§7.1) with the exact HTTP 200/500/503 codes, the four checks performed, and the caching windows (2s success / 30s failure / 300s token-state), verified against IG-XLB v1.30 §3.4. (5) §8 gained the upstream API-key-caching caveat. (6) §10's backup scope no longer treats the OCSP cache as an implicit backup candidate — a three-category distinction (durable/shared, per-node message-log, rebuildable/cache) now applies, with OCSP explicitly pointed at regeneration-behavior validation instead. (7) §11 rewritten: the external-OPMON HTTPS question is now resolved — UG-SS (same tag) explicitly and strongly advises HTTPS, with the exact bidirectional TLS-certificate-exchange mechanism now documented and the gRPC keystore/truststore requirement correctly scoped only to the UI Diagnostics traffic-visualization feature; also surfaced upstream's own caveat that the shared-external-Opmonitor-for-a-cluster configuration specifically is "not officially supported yet." No architecture was redesigned; the six-model framework and this document's overall `CAMDX 7.8.2 VALIDATION REQUIRED` status are unchanged. |
| 2026-09-30 (final narrow publication-cleanup round, same day) | §13 corrected: no longer instructs re-confirming the PostgreSQL major version "from package metadata" (§2 already proved this generic/unversioned on every track) — replaced with the correct live-host action. §11 OPMON classification sharpened: split into (a) basic single-SS-plus-external-Opmonitor architecture (plain UPSTREAM-CONFIRMED, no caveat) and (b) the cluster-specific shared-Opmonitor-for-a-primary/secondary-pair configuration (reclassified to UPSTREAM-DOCUMENTED / CLUSTER-SPECIFIC CONFIGURATION NOT OFFICIALLY SUPPORTED BY UPSTREAM / CAMDX 7.8.2 VALIDATION REQUIRED, not a bare "UPSTREAM-CONFIRMED" that could read as officially supported); §12's table updated to match. HTTPS guidance unchanged, not weakened. No architecture redesigned. |
| 2026-09-30 (final mechanical publication fix, same day) | §14 corrected: removed a literal RFC1918/private lab address range from this public canonical document — reworded to describe only an obsolete Ubuntu/Ansible baseline and private lab addressing, with no private address/range published. No other content changed. |
