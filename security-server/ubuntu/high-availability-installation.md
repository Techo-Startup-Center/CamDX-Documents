# CamDX Security Server - Ubuntu High Availability Architecture and Deployment Guidance

Existing CamDX HA deployments remain supported. For a new HA deployment, an upgrade of an existing HA deployment, or a topology change, coordinate with CamDX before implementation.

This document describes the architecture, operational requirements, and constraints. It is not authorization to deploy or modify an HA pair independently; exact configuration values for your deployment are confirmed with CamDX during HA deployment planning.

## 1. Architecture overview

A **primary** Security Server and one or more **secondary** Security Servers form a logical pair/cluster behind an external, member-operated load balancer. Consumers and providers see a single logical Security Server identity; the load balancer distributes connections across the underlying nodes.

What makes this one logical Security Server:

- A single Security Server Code/identity, shared configuration (`serverconf`), and shared key material (`keyconf`/software token) across all nodes.
- The external load balancer, not X-Road itself, makes the pair appear as one address to consumers/providers.

This architecture's goal is load balancing, not full fault tolerance: some in-flight X-Road messages can still be lost if a node fails, and failover (primary-to-secondary promotion) is a manual operation, not automatic; see §7.

## 2. PostgreSQL and `serverconf` replication

A separate, dedicated PostgreSQL instance is used for the `serverconf` database (historically on port `5433`), distinct from any other local database. The primary instance is the write target; streaming replication (hot standby) propagates `serverconf` to each secondary, which serves it read-only. Replication authentication uses TLS client certificates (`hostssl replication ... cert` in `pg_hba.conf`), signed by a dedicated CA.

The PostgreSQL major version available depends on your host's configured package repositories, not a version pinned by the CamDX package itself. Confirm the resolved version with `pg_lsclusters` (after install) or `apt-cache policy postgresql` (before install), and confirm the exact value and any version-specific parameter naming (for example `wal_keep_size` vs. an older `wal_keep_segments`) with CamDX during HA deployment planning.

**Reference replication parameters** (confirm exact values for your deployment with CamDX):

Primary instance:
```text
ssl = on
ssl_ca_file = '/etc/xroad/postgresql/ca.crt'
ssl_cert_file = '/etc/xroad/postgresql/server.crt'
ssl_key_file = '/etc/xroad/postgresql/server.key'

listen_addresses = '*'          # or the specific interface secondaries connect over
wal_level = replica
max_wal_senders = 3             # approximately (number of secondaries) plus headroom
wal_keep_size = 8               # confirm the parameter name for your PostgreSQL version
```

```text
# pg_hba.conf, on the primary
hostssl replication +secondarynode <secondary-node-CIDR> cert
```

Secondary instance:
```text
ssl = on
ssl_ca_file = '/etc/xroad/postgresql/ca.crt'
ssl_cert_file = '/etc/xroad/postgresql/server_<node>.crt'
ssl_key_file = '/etc/xroad/postgresql/server_<node>.key'
listen_addresses = 'localhost'  # read-only standby; do not expose beyond localhost without a specific reason

hot_standby = on
hot_standby_feedback = on

primary_conninfo = 'host=<primary-host> port=5433 user=<secondary-role> sslmode=verify-ca sslcert=/etc/xroad/postgresql/server_<node>.crt sslkey=/etc/xroad/postgresql/server_<node>.key sslrootcert=/etc/xroad/postgresql/ca.crt'
```

A `standby.signal` file (modern PostgreSQL) or a `recovery.conf` (pre-12 PostgreSQL) marks the secondary as a standby; which applies depends on the resolved PostgreSQL version.

## 3. State replication scope

| Item | Replicated? | Why |
|---|---|---|
| `serverconf` database | Yes, via PostgreSQL streaming replication (§2) | Shared logical configuration state |
| `signer/keyconf.xml` and software token state under `signer/` | Yes, via scheduled `rsync`+`ssh` | AUTH/SIGN keys must be identical across nodes for both to present the same Security Server identity. This means software-token key material is physically copied to every secondary node; treat the `rsync` transport (SSH key trust, restricted service account, file permissions on arrival) with the same care as any other private-key handling. |
| `db.properties` | No | Node-specific: each node's own file correctly points to its own local view of the replicated `serverconf` instance |
| `postgresql/*` (under `/etc/xroad/postgresql/`) | No | Node-specific TLS certificate/key pair for the replication connection; overwriting a secondary's own key material with the primary's breaks replication |
| `globalconf/` | No | Each node's own `xroad-confclient` independently fetches and maintains its own global configuration cache |
| `conf.d/node.ini` | No | This is precisely the file that tells each node whether it is `type=master` or `type=slave`; replicating it would make every node claim the same role |
| `messagelog` database | No | Each node maintains its own separate message-log database, so that `serverconf`'s streaming replication does not also have to replicate `messagelog` |
| OCSP response cache (`/var/cache/xroad`) | No | Deliberately not replicated; regenerates from a live OCSP responder query |

Reference synchronization command for the shared state above (confirm the exact flag set for your deployment with CamDX):

```bash
rsync -e "ssh -o ConnectTimeout=5 " -aqz --timeout=10 --delete-delay --exclude db.properties --exclude "/conf.d/node.ini" --exclude "*.tmp" --exclude "/postgresql" --exclude "/globalconf" --exclude "/gpghome" --delay-updates --log-file=/var/log/xroad/slave-sync.log ${XROAD_USER}@${MASTER}:/etc/xroad/ /etc/xroad/
```

If you are planning a change to what is or is not replicated, contact CamDX before implementation; this is an architecture decision, not a local configuration choice.

## 4. `node.ini` semantics

`/etc/xroad/conf.d/node.ini` determines the node's role:

```ini
[node]
type=master
```
or
```ini
[node]
type=slave
```

Current prose in this guide refers to these roles as "primary" and "secondary," but the literal configuration value is `master`/`slave`; there is no `type=primary`/`type=secondary` syntax. The primary is the only node where configuration changes should originate; secondaries treat their replicated configuration as read-only (enforced administratively, see §6).

## 5. External load balancer

- **Layer 4 / TCP-level load balancing with TLS passthrough is required.** TLS termination must be performed by the Security Server, not the load balancer. Any load balancer capable of this (nginx `stream{}`, HAProxy, a cloud network load balancer, or a hardware appliance) is acceptable.
- **Ports requiring passthrough:** `5500` (X-Road message exchange) and `5577` (peer/OCSP-related traffic), per [Network Requirements](../network-requirements.md), at minimum; plus the consumer-information-system client ports applicable to your deployment.
- **Disable pooled client HTTP connections** on the primary (`[proxy] server-support-clients-pooled-connections=false` in `/etc/xroad/conf.d/local.ini`): load balancing operates at the TCP level, and persistent connections would defeat even traffic distribution across nodes.
- **Proxy admin port `5566`** is used for maintenance-mode control (§6), separate from the health-check port `5588`.

### 5.1 Health-check service (port `5588`)

Disabled by default (`health-check-port = 0`). Once enabled (`health-check-port=5588` in `/etc/xroad/conf.d/local.ini` on the primary, replicated to all nodes), it responds over plain HTTP (not HTTPS):

| Response | Meaning |
|---|---|
| `HTTP 200 OK` | Healthy; the proxy should be able to process messages |
| `HTTP 500 Internal Server Error` | Failed health check; a short failure reason is included in the response body |
| `HTTP 503 Service Unavailable` (`Health check interface is in maintenance mode`) | The node has been deliberately placed into maintenance mode |

Checks performed: the server authentication key is accessible and the software token is logged in; the OCSP response for the certificate is `good`; the `serverconf` database is accessible; the global configuration is valid and not expired. Each check has a 5-second timeout; a timeout counts as a failure.

A successful result is cached for 2 seconds; a failed result for 30 seconds; the software-token logged-in state is cached separately for 300 seconds. Set your load balancer's health-check polling interval with these windows in mind: polling faster than 2 seconds gains nothing, and polling much slower than 30 seconds delays detecting a real failure.

## 6. Maintenance mode and secondary-node restrictions

**Maintenance mode** is enabled/disabled via an `HTTP GET` to the proxy admin port `5566` (not `5588`): `http://localhost:5566/maintenance?targetState=true` / `...=false`, returning `200 OK` with a confirmation message. It automatically resets to disabled on the next `xroad-proxy` restart.

**Secondary nodes are administratively restricted** to prevent configuration drift:

- Remove the `xroad-registration-officer`, `xroad-service-administrator`, and `xroad-system-administrator` roles from secondary-node Admin UI accounts.
- Retain only `xroad-security-officer` on a secondary; it is needed for local PIN entry/token operations.
- The management REST API on a secondary rejects configuration-modification calls; read-only access uses API keys with the `xroad-securityserver-observer` role.
- API keys are replicated from primary to secondaries but read through a per-node cache: a key revoked or changed on the primary is not reflected on a secondary until `xroad-proxy-ui-api` is restarted on that secondary.
- Installation scripts detect node type and adjust user-group creation accordingly on install; a version upgrade does not modify this configuration.

## 7. Failover and primary promotion

There is no automatic failover/promotion mechanism for the Security Server role. If the primary becomes unavailable, secondaries continue serving already-replicated configuration and can continue processing message traffic that does not require a configuration change, but no node automatically promotes itself to primary. Configuration changes cannot originate anywhere while no primary is available; promoting a different node to primary is a manual operation (changing that node's `node.ini` and re-establishing replication in the new direction), performed in coordination with CamDX.

## 8. Backup and recovery responsibilities

Backup scope must distinguish three kinds of state, per §3:

| Category | Examples | Backup responsibility |
|---|---|---|
| Durable, shared configuration state | `serverconf` database, `signer/keyconf.xml`/software token | Must be backed up; this is the member's actual identity/configuration and cannot be regenerated |
| Per-node message-log/archive state | `messagelog` database (node-local) | Must be backed up per node, independently; each node holds records the other does not |
| Rebuildable/cache state | OCSP response cache | Not a backup candidate by default; it regenerates from a live OCSP responder query |

Restoring a backup onto a rebuilt primary must not silently break the existing replication relationship with its secondaries. Contact CamDX before performing a restore or disaster-recovery procedure on an HA pair, so the replication topology can be re-established correctly afterward.

## 9. Operational Monitoring for the HA topology

CamDX Operational Monitoring policy is unchanged for HA: the capability is mandatory, local is the default, and remote/external is a supported alternative, not an HA-only mechanism; see [Network Requirements](../network-requirements.md) §7.

A single Security Server pointed at a dedicated external Operational Monitoring daemon is a standard, generally-applicable X-Road capability, independent of HA. A separate configuration, one external Operational Monitoring daemon shared by multiple clustered (primary/secondary) Security Servers, is documented by upstream X-Road but not yet treated by upstream as officially supported; confirm with CamDX during HA deployment planning before relying on it.

HTTPS is strongly advised for the connection between a Security Server and its external Operational Monitoring daemon. The mechanism: the Security Server's own internal TLS certificate (`/etc/xroad/ssl/internal.crt`, exportable via the Admin UI) is copied to the external daemon and referenced there as `[op-monitor] client-tls-certificate = <path>`; a separate TLS key/certificate pair is generated on the daemon host via `generate-opmonitor-certificate` and copied back to the Security Server as `[op-monitor] tls-certificate = <path>`. A further keystore/truststore pair is needed only if the request-traffic visualization on the Security Server UI Diagnostics page is used; it is not required for basic external Operational Monitoring data exchange.

## 10. When to contact CamDX

Contact CamDX before: deploying a new HA pair, changing an existing HA pair's topology or node count, changing what state is or is not replicated, promoting a secondary to primary outside of a planned procedure, or performing a backup restore/disaster-recovery procedure on an HA pair. CamDX will confirm the exact configuration values (PostgreSQL version, replication parameters, load-balancer and health-check wiring, Operational Monitoring topology) applicable to your deployment as part of that planning.

## 11. References

- Upstream X-Road External Load Balancer Installation Guide and Security Server User Guide (`nordic-institute/X-Road`, `docs.x-road.global`).
- [Deployment Model Selector](../deployment-models.md), [Network Requirements](../network-requirements.md).
- [Upgrade and Migration](../upgrade/README.md): HA is not covered by the standard member migration procedure; HA upgrades are coordinated separately with CamDX.
