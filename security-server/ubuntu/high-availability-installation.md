# CamDX Security Server - Ubuntu HA Installation

This is an executable procedure for deploying a native CamDX Security Server HA pair on Ubuntu: a primary and secondary node, replicated `serverconf`, synchronized configuration state, and an external load balancer. It is written as a walkthrough for a junior Linux/system engineer who knows basic Linux administration but has never built an X-Road HA Security Server before: it assumes general Linux administration experience and CamDX onboarding information, but no prior X-Road HA experience, and every step tells you where to run it, what to type, what file or screen you are changing, why, what to substitute, what success looks like, how to verify it, when to stop, and what to do next.

Existing CamDX deployments using this architecture remain supported. A new HA deployment, an upgrade of an existing one, or a topology change requires a completed [HA Deployment Profile](../high-availability-deployment-profile.md) with Checkpoint A confirmed before you start Phase 1.

## 0. Architecture summary

A single logical Security Server, identified by one Security Server Code, runs as a **primary** and **secondary** node behind an external Layer-4 load balancer. The primary is the only node where configuration changes originate. `serverconf` replicates continuously via PostgreSQL streaming replication; the remaining shared `/etc/xroad` state (signing/authentication keys and token state) replicates via `rsync` over SSH, once as a one-time bootstrap and then on a schedule. There is no automatic failover: promoting a different node to primary is always a manual, deliberate action, not covered by this installation procedure (see §30).

```text
Clean Node 1                              Clean Node 2
   standalone package install                standalone package install
   convert to HA primary                      convert to HA secondary
   Primary / master                           Secondary / slave

Primary serverconf PostgreSQL <--streaming replication-- Secondary serverconf PostgreSQL
Primary /etc/xroad selected state --rsync + SSH---------> Secondary /etc/xroad selected state

                      External L4 load balancer (TLS passthrough only)
                          /                              \
                     Primary                          Secondary
```

PostgreSQL streaming replication flows from primary to secondary, but the secondary is the one that *initiates* the TCP connection to the primary (secondary to primary on TCP `5433`). The same direction applies to SSH/`rsync` (secondary to primary on TCP `22`). Keep this direction in mind in the firewall and SSH-trust phases below.

**Member Initial Configuration is performed on the primary only, once (Phase 18).** The secondary is never independently initialized as a second logical Security Server; it receives the shared identity through replication and a one-time bootstrap sync, not through its own registration.

## Checkpoints - where you genuinely need CamDX

The normal, successful installation path has exactly three planned CamDX checkpoints. Everything else below is self-contained.

- **Checkpoint A, before you start (Phase 0):** your [HA Deployment Profile](../high-availability-deployment-profile.md) is completed and CamDX has authorized this HA deployment (environment, member identity, Security Server Code, onboarding status).
- **Checkpoint B, normal PKI/registration (Phase 18, via [Initial Configuration](../initial-configuration.md)):** AUTH/SIGN CSR submission, certificate issuance, authentication-certificate registration approval, and subsystem registration approval. This is CamDX's normal onboarding process; HA does not add an exception to it.
- **Checkpoint C, acceptance (Phase 28):** CamDX central monitoring visibility, final registration confirmation, and production go-live authorization.

This runbook provides the PostgreSQL, SSH, `rsync`, systemd, firewall, and health-check mechanics directly. If a documented **STOP** condition occurs, additional troubleshooting or escalation may be required; see §31. Do not improvise around a **STOP** condition.

## 1. Before you start

- Two fresh Ubuntu hosts, **both on the same supported release**: Ubuntu 22.04 + Ubuntu 22.04, or Ubuntu 24.04 + Ubuntu 24.04 (amd64 each). A mixed Jammy/Noble pair is not a supported standard pair.
- Root/sudo access on both.
- Your [HA Deployment Profile](../high-availability-deployment-profile.md), completed per Checkpoint A.
- The HA network ports open per [Network Requirements](../network-requirements.md) §8.
- A load balancer capable of Layer 4/TCP passthrough, administered by your own team.

## Phase 0 - Complete the HA Deployment Profile

Open the [HA Deployment Profile](../high-availability-deployment-profile.md). Fill in every CamDX-provided/CamDX-confirmed field (§1) and every member-owned infrastructure field (§2) you will need below.

**STOP** if any required field is unknown. Confirm CamDX-provided fields with CamDX (Checkpoint A) and resolve member-owned fields with your own network/infrastructure team before continuing.

Throughout this guide, `<PRIMARY_NODE>`/`<PRIMARY_FQDN>`, `<SECONDARY_NODE>`/`<SECONDARY_FQDN>`, `<PRIMARY_IP>`, `<SECONDARY_IP>`, `<VIP_FQDN>`, and `<SECONDARY_SOURCE_CIDR>` refer to the values you just recorded. `<SECONDARY_SOURCE_CIDR>` is the secondary's replication/SSH source address as the primary actually observes it (HA Deployment Profile §2); it is not always the same as `<SECONDARY_IP>` if NAT sits between the two nodes. This guide also uses one fixed, non-configurable value: the secondary's PostgreSQL replication role and certificate CN is always `xroad_replica_secondary` (profile §3); do not substitute a different name for it anywhere below.

**Two distinct accounts, do not conflate them:** `<PRIMARY_OS_ADMIN_USER>`/`<SECONDARY_OS_ADMIN_USER>` are the existing, SSH/`sudo`-capable operating-system accounts this guide uses for every privileged command (Phase 5, Phase 11). `<PRIMARY_ADMIN_USER>`/`<SECONDARY_ADMIN_USER>` are the X-Road Admin UI accounts created by Phase 2's installer. `xroad-add-admin-user` grants X-Road role-group membership only; it does not grant `wheel`/`sudo`. These two pairs may happen to name the same Linux account if your organization deliberately arranges that, but this guide never assumes it.

## Phase 1 - Provision and verify both clean Ubuntu nodes

**Prepare:** have SSH access to both nodes as a user with `sudo`, and the HA Deployment Profile's `<PRIMARY_FQDN>`, `<SECONDARY_FQDN>`, `<VIP_FQDN>`, `<PRIMARY_IP>`, `<SECONDARY_IP>` filled in.

On **each** node, verify the OS and basic host state:

```bash
hostname -f
cat /etc/os-release
timedatectl status
ip route
```

Expected result:
- Both nodes report the **same** `VERSION_CODENAME` (both `jammy`, or both `noble`). **STOP** if they differ; a mixed pair is not supported.
- `hostname -f` returns the FQDN you recorded in the HA Deployment Profile for that node.
- `timedatectl status` shows `System clock synchronized: yes`; both nodes use the same NTP source recorded in the profile.

Verify DNS resolution and routing explicitly, on **each** node:

```bash
getent hosts <PRIMARY_FQDN>
getent hosts <SECONDARY_FQDN>
getent hosts <VIP_FQDN>

ip route get <PRIMARY_IP>
ip route get <SECONDARY_IP>
```

Expected result: each `getent hosts` line prints the correct recorded IP for that name; each `ip route get` prints a route with a real outgoing interface (`dev ...`), not `unreachable` or `connect: No route to host`.

Verify each host is genuinely clean, on **each** node:

```bash
dpkg -l 'xroad*' 2>/dev/null | grep '^ii' || echo "no xroad packages installed"
sudo test -d /etc/xroad && echo "/etc/xroad exists" || echo "/etc/xroad absent (expected on a clean host)"
pg_lsclusters
```

Expected result: `no xroad packages installed`; `/etc/xroad absent (expected on a clean host)`; `pg_lsclusters` prints only its header row, or reports the command is not found. **STOP** if any `xroad*` package, `/etc/xroad`, or an existing PostgreSQL cluster is already present on a host you intend to use as a clean node; this guide assumes a genuinely clean host and does not cover converting a host with leftover state from a prior attempt.

Confirm the HA network ports from [Network Requirements](../network-requirements.md) §8 are **prepared** in the firewall. At this point, nothing is actually listening yet on `5433` (PostgreSQL `serverconf`, created in Phase 6) or `5588` (the health check, created in Phase 16-17); a prepared firewall rule with nothing behind it is not the same as a tested live connection. Record in your own notes that the rule is prepared; you test live connectivity to `5433` in Phase 9 and to `5588` in Phase 22, once the corresponding service exists.

**STOP condition:** if any check above fails, resolve it before continuing; do not work around a routing or DNS problem by hardcoding IPs where this guide expects a name, or vice versa; do not proceed on a host that is not genuinely clean.

**Continue** to Phase 2 once every check above passes on both nodes.

## Phase 2 - Install CamDX Security Server on both nodes

Use the same validated installer as a standalone deployment, on **each** clean node:

```bash
cd security-server/scripts
sudo ./install-ubuntu.sh
```

See [Ubuntu Standalone Installation](./standalone-installation.md) §2 for what the script does; it installs local Operational Monitoring automatically as part of the standard install, on both nodes. **Do not run Initial Configuration yet** on either node. The script asks for (or accepts via `--admin-user`) the X-Road Admin UI account name for that node; record the name you actually used for the primary and the secondary as `<PRIMARY_ADMIN_USER>` and `<SECONDARY_ADMIN_USER>` in your HA Deployment Profile §2 now. **This account is for the Admin UI only; it does not grant `sudo`.** Separately, confirm (or arrange with your organization) the existing, SSH/`sudo`-capable operating-system account on each node and record it as `<PRIMARY_OS_ADMIN_USER>`/`<SECONDARY_OS_ADMIN_USER>` in the same profile section; this is the account Phase 5 and Phase 11 actually use for every privileged command.

On each node, confirm the installation is readiness-clean:

```bash
sudo ./camdx-ss-check
```

Expect `Summary: PASS=... WARN=0 FAIL=0 SKIP=...` and `READY FOR INITIAL CONFIGURATION` on both nodes. No warning is expected at this point. If either node reports `ACTION REQUIRED`, resolve every listed `FAIL` before continuing to Phase 3.

## Phase 3 - Stop X-Road services for HA conversion

On **both** nodes, stop the application-level X-Road services before changing anything under `/etc/xroad`:

```bash
sudo systemctl stop xroad-proxy xroad-proxy-ui-api xroad-confclient xroad-signer xroad-monitor xroad-addon-messagelog
```

Leave running: `xroad-base` (a one-shot unit; there is nothing to stop), the local PostgreSQL instance installed by `xroad-database-local` (you need it running to read from it in Phase 7), and `xroad-opmonitor` (already installed in Phase 2, independent of `serverconf`, left running on both nodes throughout this procedure).

Confirm the stop took effect:

```bash
systemctl is-active xroad-proxy xroad-proxy-ui-api xroad-confclient xroad-signer xroad-monitor xroad-addon-messagelog
```

Expect `inactive` for each.

## Phase 4 - Confirm both nodes resolve to the same PostgreSQL major version

On **each** node, determine the installed PostgreSQL cluster:

```bash
pg_lsclusters
```

This lists `<version> <clustername> <port> <status> ...`; the default cluster from `xroad-database-local` is named `main`. Then confirm the actual running server version directly, on **each** node, with a live query (do not rely on the cluster listing alone):

```bash
sudo -u postgres psql -Atc 'SHOW server_version;'
```

Record the major version number (the leading integer, for example `16` from `16.4`) from both nodes as `<PG_MAJOR>` in your HA Deployment Profile §3.

**STOP if the two nodes do not resolve to the same PostgreSQL major version.** Do not proceed with a mixed-major-version pair; resolve the discrepancy (typically by confirming both nodes are genuinely on the same Ubuntu release per Phase 1) before continuing. Substitute your confirmed `<PG_MAJOR>` in every command below.

## Phase 5 - Create the database-replication CA and node certificates, and transfer them to both nodes

The certificate-generation commands below run on a secure admin workstation, **not** on either cluster node; the transfer and installation commands later in this phase are explicitly marked with which node they run on.

**On the workstation**, generate the CA and both node certificates:

```bash
mkdir -p ha-ca && cd ha-ca

# Certificate authority for this HA pair's serverconf replication only
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt -subj "/CN=<PRIMARY_NODE>-serverconf-ca"

# Primary node certificate
openssl genrsa -out server-primary.key 2048
openssl req -new -key server-primary.key -out server-primary.csr -subj "/CN=<PRIMARY_NODE>"
openssl x509 -req -in server-primary.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 -out server-primary.crt

# Secondary node certificate. The CN MUST be exactly xroad_replica_secondary:
# this is the fixed PostgreSQL replication role name this guide uses (Phase 6),
# and certificate-based authentication matches on this exact value.
openssl genrsa -out server-secondary.key 2048
openssl req -new -key server-secondary.key -out server-secondary.csr -subj "/CN=xroad_replica_secondary"
openssl x509 -req -in server-secondary.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 -out server-secondary.crt
```

Expected result: `ca.key`, `ca.crt`, `server-primary.key/.csr/.crt`, and `server-secondary.key/.csr/.crt` all exist in `ha-ca/`.

Verify the secondary certificate's CN before transferring it anywhere:

```bash
openssl x509 -in server-secondary.crt -noout -subject
```

Expected result: `subject=CN = xroad_replica_secondary`. **STOP** if it shows anything else; regenerate rather than transferring a mismatched certificate.

**Verify both nodes' SSH host identity before transferring anything.** Do this once per node, before the first `scp`/`ssh` command touches it. Do not accept a first-use host-key prompt merely because the connection succeeds; an unverified prompt is not a substitute for this check, since it would accept whatever key happens to answer on that address.

Still on the workstation, create a dedicated, empty `known_hosts` file scoped to this HA build (do not use your personal `~/.ssh/known_hosts` for this, so this build's trust decisions stay isolated and auditable). Initialize it explicitly empty/truncated rather than relying on `touch`, which would silently leave any pre-existing content from an earlier attempt in place:

```bash
: > ./ha-known-hosts
```

For **each** node in turn:

```bash
# Primary:
ssh-keyscan -t ed25519 <PRIMARY_IP> > /tmp/primary-hostkey.pub
ssh-keygen -lf /tmp/primary-hostkey.pub -E sha256

# Secondary:
ssh-keyscan -t ed25519 <SECONDARY_IP> > /tmp/secondary-hostkey.pub
ssh-keygen -lf /tmp/secondary-hostkey.pub -E sha256
```

Compare each printed `SHA256:...` fingerprint against the `<PRIMARY_SSH_FINGERPRINT>` / `<SECONDARY_SSH_FINGERPRINT>` value recorded in your HA Deployment Profile §2. **STOP** on any mismatch; do not transfer anything to that node until the discrepancy is resolved and the fingerprint is reconfirmed out-of-band with whoever provisioned it.

Only after both fingerprints match, add the verified keys to the dedicated `known_hosts` file and remove the staged copies:

```bash
cat /tmp/primary-hostkey.pub /tmp/secondary-hostkey.pub >> ./ha-known-hosts
rm -f /tmp/primary-hostkey.pub /tmp/secondary-hostkey.pub
```

**Transfer the files to each node**, using strict host-key checking against the file you just populated, so this still fails closed if a host key were ever to change later rather than silently re-prompting:

```bash
scp -o UserKnownHostsFile=./ha-known-hosts -o StrictHostKeyChecking=yes \
  ca.crt server-primary.crt server-primary.key \
  <PRIMARY_OS_ADMIN_USER>@<PRIMARY_IP>:/tmp/

scp -o UserKnownHostsFile=./ha-known-hosts -o StrictHostKeyChecking=yes \
  ca.crt server-secondary.crt server-secondary.key \
  <SECONDARY_OS_ADMIN_USER>@<SECONDARY_IP>:/tmp/
```

Expected result: both `scp` commands exit `0` with no host-key prompt (the key is already verified and trusted) and no error; the files exist under `/tmp` on the respective node (`ls -l /tmp/ca.crt /tmp/server-primary.crt /tmp/server-primary.key` on the primary; `ls -l /tmp/ca.crt /tmp/server-secondary.crt /tmp/server-secondary.key` on the secondary).

**On the primary**, install the primary's own certificate/key from the staged copy, owned so PostgreSQL (which runs as the `postgres` user) can read them but nothing else can read the private key:

```bash
sudo install -d -o postgres -g postgres -m 0750 /etc/xroad/postgresql

sudo install -o postgres -g postgres -m 0644 /tmp/ca.crt /etc/xroad/postgresql/ca.crt
sudo install -o postgres -g postgres -m 0644 /tmp/server-primary.crt /etc/xroad/postgresql/server.crt
sudo install -o postgres -g postgres -m 0600 /tmp/server-primary.key /etc/xroad/postgresql/server.key
```

**On the secondary**, install the secondary's own certificate/key the same way, using the secondary's own staged files:

```bash
sudo install -d -o postgres -g postgres -m 0750 /etc/xroad/postgresql

sudo install -o postgres -g postgres -m 0644 /tmp/ca.crt /etc/xroad/postgresql/ca.crt
sudo install -o postgres -g postgres -m 0644 /tmp/server-secondary.crt /etc/xroad/postgresql/server.crt
sudo install -o postgres -g postgres -m 0600 /tmp/server-secondary.key /etc/xroad/postgresql/server.key
```

Both nodes now have a file at `/etc/xroad/postgresql/server.crt` and `/etc/xroad/postgresql/server.key`, but the contents differ: each node's copy is its own node-specific certificate and key. This matches the configuration paths used in Phase 6 and Phase 8 below, and is never synchronized by `rsync` (the exclusion lists in Phase 12 and Phase 19 both cover this directory).

**Remove the staged copies from `/tmp` on each node**, now that the files are installed under `/etc/xroad/postgresql`:

```bash
# On the primary:
rm -f /tmp/ca.crt /tmp/server-primary.crt /tmp/server-primary.key

# On the secondary:
rm -f /tmp/ca.crt /tmp/server-secondary.crt /tmp/server-secondary.key
```

**Verify the installed certificates**, on **each** node:

```bash
sudo -u postgres openssl verify -CAfile /etc/xroad/postgresql/ca.crt /etc/xroad/postgresql/server.crt
sudo -u postgres openssl x509 -in /etc/xroad/postgresql/server.crt -noout -subject -issuer -dates
sudo ls -l /etc/xroad/postgresql/
```

Expected result: `openssl verify` prints `.../server.crt: OK`; the `-subject` line shows `CN = <PRIMARY_NODE>` on the primary and `CN = xroad_replica_secondary` on the secondary; `ls -l` shows `server.key` mode `600` owned `postgres:postgres`, and `ca.crt`/`server.crt` mode `644` owned `postgres:postgres`. **STOP** if the secondary's CN is not exactly `xroad_replica_secondary`; regenerate from the workstation rather than proceeding with a mismatched certificate.

**CA private key lifecycle:** `ca.key` was generated only on this admin workstation and was never transferred to either node. Once both nodes have their issued certificates, either move `ca.key` to your organization's approved secure key storage (if you expect to issue or replace node certificates later) or, if your organization's lifecycle plan is to replace the whole replication trust chain rather than reissue from this CA, you may retire it according to that plan. In either case, **do not leave `ca.key` on the admin workstation indefinitely, and never copy it to either Security Server node.**

## Phase 6 - Create the dedicated primary `serverconf` PostgreSQL instance

On the **primary** node:

```bash
sudo -u postgres pg_createcluster -p 5433 <PG_MAJOR> serverconf
sudo pg_ctlcluster <PG_MAJOR> serverconf start
```

Have PostgreSQL itself report the paths it actually created, rather than assuming the typical layout:

```bash
POSTGRESQL_CONF="$(sudo -u postgres psql -p 5433 -Atc 'SHOW config_file;')"
PG_HBA_CONF="$(sudo -u postgres psql -p 5433 -Atc 'SHOW hba_file;')"
SERVERCONF_DATA_DIR="$(sudo -u postgres psql -p 5433 -Atc 'SHOW data_directory;')"

printf 'postgresql.conf: %s\n' "$POSTGRESQL_CONF"
printf 'pg_hba.conf:      %s\n' "$PG_HBA_CONF"
printf 'data directory:   %s\n' "$SERVERCONF_DATA_DIR"
```

Expected result: typically `/etc/postgresql/<PG_MAJOR>/serverconf/postgresql.conf`, the matching `pg_hba.conf`, and `/var/lib/postgresql/<PG_MAJOR>/serverconf`, but use the values `SHOW` actually printed, not this typical example. Record all three as the primary's values in your HA Deployment Profile §3.

Back up both configuration files before editing:

```bash
sudo cp -a "$POSTGRESQL_CONF" "${POSTGRESQL_CONF}.pre-camdx-ha"
sudo cp -a "$PG_HBA_CONF" "${PG_HBA_CONF}.pre-camdx-ha"
```

Edit `postgresql.conf`:

```bash
sudoedit "$POSTGRESQL_CONF"
```

Add or change these lines (most are not present by default; `ssl` may already be set to `off`):

```ini
ssl = on
ssl_ca_file = '/etc/xroad/postgresql/ca.crt'
ssl_cert_file = '/etc/xroad/postgresql/server.crt'
ssl_key_file = '/etc/xroad/postgresql/server.key'

listen_addresses = '*'
wal_level = replica
max_wal_senders = 3
wal_keep_size = 8
```

`wal_keep_size` is the current parameter name for PostgreSQL 13 and later; if `<PG_MAJOR>` is below 13, use `wal_keep_segments` instead.

Edit `pg_hba.conf`:

```bash
sudoedit "$PG_HBA_CONF"
```

Add this line, using the exact source CIDR you recorded as `<SECONDARY_SOURCE_CIDR>`:

```text
hostssl replication xroad_replica_secondary <SECONDARY_SOURCE_CIDR> cert
```

`xroad_replica_secondary` is this guide's fixed replication role name (HA Deployment Profile §3); do not substitute a different name here or in the `CREATE ROLE` statement below, since the secondary's certificate CN (Phase 5) was generated to match it exactly.

Create the replication role and the application role X-Road itself will use:

```bash
sudo -u postgres psql -p 5433 -c "CREATE ROLE xroad_replica_secondary WITH REPLICATION LOGIN;"

GENERATED_PW="$(openssl rand -base64 24)"
sudo -u postgres psql -p 5433 -c "CREATE ROLE serverconf WITH LOGIN PASSWORD '$GENERATED_PW';"
sudo -u postgres psql -p 5433 -c "CREATE DATABASE serverconf OWNER serverconf;"
printf 'serverconf role password: %s\n' "$GENERATED_PW"
unset GENERATED_PW
```

Copy the printed password immediately into your organization's approved secret storage; do not record it in the HA Deployment Profile or any other plain-text file. You need this exact value twice: once for the primary's `db.properties` in Phase 7, and again for the secondary's `db.properties` in Phase 10: the role is physically replicated, so both nodes must use the identical password. The replication role itself needs no password: `cert` authentication in `pg_hba.conf` matches on certificate CN.

Restart the `serverconf` cluster to apply the configuration changes:

```bash
sudo pg_ctlcluster <PG_MAJOR> serverconf restart
```

Verify the effective configuration with `SHOW`, not by grepping the file (a restart can fail silently on a typo without this check):

```bash
sudo -u postgres psql -p 5433 -c "SHOW ssl;"
sudo -u postgres psql -p 5433 -c "SHOW ssl_ca_file;"
sudo -u postgres psql -p 5433 -c "SHOW ssl_cert_file;"
sudo -u postgres psql -p 5433 -c "SHOW ssl_key_file;"
sudo -u postgres psql -p 5433 -c "SHOW listen_addresses;"
sudo -u postgres psql -p 5433 -c "SHOW wal_level;"
sudo -u postgres psql -p 5433 -c "SHOW max_wal_senders;"
```

Verify the WAL-retention parameter you actually set, using the query that matches which one you used above (do not run both; `wal_keep_size` is a PostgreSQL 13+ parameter, `wal_keep_segments` is pre-13, and only one of them exists on a given server):

**If `<PG_MAJOR>` is 13 or later** (you set `wal_keep_size`), query `pg_settings` directly for the setting and its unit, rather than `SHOW`, so the check does not depend on `SHOW`'s own display formatting:

```bash
sudo -u postgres psql -p 5433 -Atc "SELECT setting, unit FROM pg_settings WHERE name = 'wal_keep_size';"
```

Expected result: `8|MB`. Do not instead run `SHOW wal_keep_size;` and expect it to print the bare number `8`: PostgreSQL's `SHOW` appends the parameter's unit when displaying it (typically `8MB`), so requiring the literal string `8` would fail even when the value is actually correct.

**If `<PG_MAJOR>` is below 13** (you set `wal_keep_segments`):

```bash
sudo -u postgres psql -p 5433 -Atc "SHOW wal_keep_segments;"
```

Expected result: `8` (this parameter has no unit, so `SHOW` prints a bare integer here).

**STOP** if `pg_ctlcluster ... restart` reported an error, or if any value above does not match what you set; fix `postgresql.conf` and restart again before continuing. Do not proceed on an assumption that the file content you wrote took effect.

## Phase 7 - Move the primary `serverconf` into the dedicated instance

On the **primary** node, the default local cluster (port `5432`, created by `xroad-database-local`) still holds the original `serverconf` and `messagelog` databases. Before copying, confirm the source exists and the target is reachable:

```bash
sudo -u postgres psql -p 5432 -lqt | cut -d'|' -f1 | grep -qw serverconf && echo "source serverconf found on 5432" || echo "STOP: serverconf not found on 5432"
sudo -u postgres pg_isready -p 5433
```

Expected result: `source serverconf found on 5432`; `pg_isready -p 5433` reports `accepting connections`. **STOP** if either check fails.

Copy `serverconf` into the new dedicated instance. Make the restore side stop on the first SQL error, not only make the pipeline's own plumbing visible: `psql` does not otherwise terminate on a failed statement, so `-v ON_ERROR_STOP=1` is required for the exit status to actually mean what it looks like it means:

```bash
set -o pipefail
sudo -u postgres pg_dump -p 5432 serverconf | sudo -u postgres psql -v ON_ERROR_STOP=1 -p 5433 serverconf
echo "pg_dump|psql pipeline exit status: $?"
```

Expected result: exit status `0`. **STOP** if the printed exit status is nonzero. A failed restore may have partially populated the target database; do not assume it is still empty, and do not simply repeat the copy on top of it. Before any retry, return the target to a known-clean state with this guarded reset, which only touches the `serverconf` database you created in Phase 6 (nothing else yet depends on it, since `db.properties` is not repointed until later in this same phase):

```bash
sudo -u postgres psql -p 5433 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'serverconf' AND pid <> pg_backend_pid();"
sudo -u postgres psql -p 5433 -c "DROP DATABASE IF EXISTS serverconf;"
sudo -u postgres psql -p 5433 -c "CREATE DATABASE serverconf OWNER serverconf;"
```

Only after this reset succeeds, repeat the `pg_dump | psql -v ON_ERROR_STOP=1` command above once. **STOP and escalate** if it fails a second time; do not retry in a loop or investigate further on your own past this point.

**The strict restore's `0` exit status above (`ON_ERROR_STOP=1`) is the primary copy-integrity gate; it already means every statement in the dump applied.** As a supplementary sanity check only, not a substitute for that gate, compare a row count between source and target for `databasechangelog`, the Liquibase migration-bookkeeping table that is guaranteed present in every `serverconf` database regardless of whether any member/client has been configured yet (at this point in the procedure, before Initial Configuration, business tables such as `client` or `service` may still legitimately be empty on a fresh install, which would make a count comparison on them pass vacuously without proving anything; `databasechangelog` always has one row per applied schema migration, so its count is both guaranteed nonzero and a genuine indicator that the whole database, including its full schema history, copied completely):

```bash
sudo -u postgres psql -p 5432 -Atc "select count(*) from databasechangelog;" serverconf
sudo -u postgres psql -p 5433 -Atc "select count(*) from databasechangelog;" serverconf
```

Expected result: the two counts match. **STOP** if they do not, even though the restore reported success; do not proceed to repoint `db.properties` until you understand why, since this would indicate a tool or environment problem beyond what the exit status alone can catch.

Back up and repoint `/etc/xroad/db.properties` on the **primary**:

```bash
sudo cp -a /etc/xroad/db.properties /etc/xroad/db.properties.pre-ha
sudoedit /etc/xroad/db.properties
```

Change only these three `serverconf` properties; **do not change the `messagelog` properties**:

```ini
serverconf.hibernate.connection.url = jdbc:postgresql://127.0.0.1:5433/serverconf
serverconf.hibernate.connection.username = serverconf
serverconf.hibernate.connection.password = <the password generated in Phase 6>
```

Verify the change without printing the password:

```bash
grep -E 'serverconf\.hibernate\.connection\.(url|username)|messagelog\.hibernate\.connection\.url' /etc/xroad/db.properties
```

Expected result: `serverconf.hibernate.connection.url` shows `127.0.0.1:5433`; `serverconf.hibernate.connection.username` shows `serverconf`; the `messagelog` URL line is unchanged (still port `5432`). This command never prints `serverconf.hibernate.connection.password`; do not add a line that would.

**Do not delete the original `serverconf` database on port 5432 yet.** Keep it until replication to the secondary is confirmed healthy (Phase 9) and you have completed Phase 28's acceptance checklist; its final disposition (keep as rollback material, not delete) is covered explicitly in Phase 29. `messagelog` stays on the node-local default instance permanently; it is never moved. Port `5432` is the original rollback copy; port `5433` is the new authoritative primary `serverconf` instance this HA pair uses going forward.

## Phase 8 - Seed the secondary `serverconf`

On the **secondary** node:

```bash
sudo -u postgres pg_createcluster -p 5433 <PG_MAJOR> serverconf
sudo pg_ctlcluster <PG_MAJOR> serverconf start
```

Before stopping this newly-created cluster, have PostgreSQL report its own actual paths, the same way as Phase 6 on the primary:

```bash
POSTGRESQL_CONF="$(sudo -u postgres psql -p 5433 -Atc 'SHOW config_file;')"
SERVERCONF_DATA_DIR="$(sudo -u postgres psql -p 5433 -Atc 'SHOW data_directory;')"

printf 'postgresql.conf: %s\n' "$POSTGRESQL_CONF"
printf 'data directory:   %s\n' "$SERVERCONF_DATA_DIR"
```

Record both as the secondary's values in your HA Deployment Profile §3. (The secondary needs no `pg_hba.conf` entry of its own for replication, since it only makes the outbound connection to the primary; mark that profile field "not applicable" for this topology.)

Now stop the cluster to seed it from the primary's base backup:

```bash
sudo pg_ctlcluster <PG_MAJOR> serverconf stop
```

Clear the new, still-empty data directory before basebackup, using the path PostgreSQL itself just reported, not an assumed path:

```bash
case "$SERVERCONF_DATA_DIR" in
  */serverconf) ;;
  *) echo "STOP: path does not end in /serverconf - refusing to continue." >&2; exit 1 ;;
esac
sudo test -d "$SERVERCONF_DATA_DIR" || { echo "STOP: $SERVERCONF_DATA_DIR does not exist." >&2; exit 1; }

sudo -u postgres find "$SERVERCONF_DATA_DIR" -mindepth 1 -delete
```

Take the base backup from the primary, authenticating with the secondary's own replication certificate (the primary's `pg_hba.conf` requires `cert` authentication, so a plain `pg_basebackup` without these variables will fail; do not fall back to a password):

```bash
sudo -u postgres \
  PGSSLMODE=verify-ca \
  PGSSLROOTCERT=/etc/xroad/postgresql/ca.crt \
  PGSSLCERT=/etc/xroad/postgresql/server.crt \
  PGSSLKEY=/etc/xroad/postgresql/server.key \
  pg_basebackup \
    -h <PRIMARY_IP> \
    -p 5433 \
    -U xroad_replica_secondary \
    -D "$SERVERCONF_DATA_DIR" \
    -Fp -Xs -P --checkpoint=fast

sudo -u postgres touch "$SERVERCONF_DATA_DIR/standby.signal"
```

Back up, then edit, `postgresql.conf` for the secondary's `serverconf` cluster:

```bash
sudo cp -a "$POSTGRESQL_CONF" "${POSTGRESQL_CONF}.pre-camdx-ha"
sudoedit "$POSTGRESQL_CONF"
```

Add or change:

```ini
listen_addresses = 'localhost'
hot_standby = on
hot_standby_feedback = on

primary_conninfo = 'host=<PRIMARY_IP> port=5433 user=xroad_replica_secondary sslmode=verify-ca sslcert=/etc/xroad/postgresql/server.crt sslkey=/etc/xroad/postgresql/server.key sslrootcert=/etc/xroad/postgresql/ca.crt'
```

Fix ownership (the base backup may have altered it) and start:

```bash
sudo chown -R postgres:postgres "$SERVERCONF_DATA_DIR"
sudo chmod 700 "$SERVERCONF_DATA_DIR"
sudo pg_ctlcluster <PG_MAJOR> serverconf start
```

Verify the effective standby configuration after startup, with `SHOW`, not by grepping the file:

```bash
sudo -u postgres psql -p 5433 -c "select pg_is_in_recovery();"
sudo -u postgres psql -p 5433 -c "SHOW hot_standby;"
sudo -u postgres psql -p 5433 -c "SHOW primary_conninfo;"
```

Expected result: `pg_is_in_recovery()` = `t`; `hot_standby` = `on`; `primary_conninfo` shows the host/port/user you set. Full replication-stream verification continues in Phase 9.

## Phase 9 - Verify PostgreSQL streaming replication

On the **primary**:

```bash
sudo -u postgres psql -p 5433 -c "select client_addr, state, sync_state from pg_stat_replication;"
```

Expected result: one row; `client_addr` is an IP address (not a CIDR), so compare it by containment, not literal string equality: it must fall within the `<SECONDARY_SOURCE_CIDR>` you recorded in the HA Deployment Profile (for example, a profile value of `10.20.30.41/32` is satisfied by an observed `client_addr` of `10.20.30.41`); `state` = `streaming`.

On the **secondary**:

```bash
sudo -u postgres psql -p 5433 -c "select pg_is_in_recovery();"
sudo -u postgres psql -p 5433 -c "select status, received_lsn, latest_end_lsn from pg_stat_wal_receiver;"
```

Expected result: `pg_is_in_recovery()` = `t`, and `pg_stat_wal_receiver.status` = `streaming`.

**STOP** if either side does not show streaming replication. Check the PostgreSQL logs on both nodes (`/var/log/postgresql/postgresql-<PG_MAJOR>-serverconf.log`) for the specific connection or certificate error before continuing; see [HA Troubleshooting](../troubleshooting/high-availability.md) for the common causes.

## Phase 10 - Configure the secondary's `db.properties`

**This step is required and easy to miss: a fresh standalone installation does not leave the secondary already pointed at the replicated instance.** On the **secondary**, back up and edit `/etc/xroad/db.properties` now, before any X-Road application service on the secondary is started:

```bash
sudo cp -a /etc/xroad/db.properties /etc/xroad/db.properties.pre-ha
sudoedit /etc/xroad/db.properties
```

Change only these three `serverconf` properties; **do not change the `messagelog` properties**:

```ini
serverconf.hibernate.connection.url = jdbc:postgresql://127.0.0.1:5433/serverconf
serverconf.hibernate.connection.username = serverconf
serverconf.hibernate.connection.password = <the same password generated on the primary in Phase 6>
```

The password must be the **identical** value used on the primary: the `serverconf` role and its password are part of the database state that PostgreSQL streaming replication physically carries to the secondary, so a different local password on the secondary will not authenticate.

Verify the change without printing the password:

```bash
grep -E 'serverconf\.hibernate\.connection\.(url|username)|messagelog\.hibernate\.connection\.url' /etc/xroad/db.properties
```

Expected result, on both nodes (re-run the same command on the primary to compare): `serverconf.hibernate.connection.url` shows `127.0.0.1:5433`, `serverconf.hibernate.connection.username` shows `serverconf`, on each node; the `messagelog` URL line is unchanged on each node (still port `5432`). This command never prints `serverconf.hibernate.connection.password`; do not add a line that would.

**Never synchronize `db.properties` with `rsync`.** It is excluded in both Phase 12 (scheduled) and Phase 19 (one-time bootstrap) precisely because each node's copy must independently point at its own local view of the replicated instance.

## Phase 11 - Configure SSH trust for configuration synchronization

On the **primary**, create the dedicated synchronization account. It needs a real shell (`/bin/bash`), because `rsync` over SSH works by having `sshd` execute the remote `rsync` command on the receiving end, and a `nologin` shell would break this. The account is still non-interactive/system-only in every other respect: it has no password, and its `authorized_keys` is owned and controlled by `root`, not by the account itself.

```bash
sudo adduser --system --shell /bin/bash --ingroup xroad --home /home/xroad-slave xroad-slave
sudo install -d -m 0750 -o root -g xroad /home/xroad-slave/.ssh
sudo install -m 0640 -o root -g xroad /dev/null /home/xroad-slave/.ssh/authorized_keys
```

`authorized_keys` is owned by `root`, group `xroad` (the same group `xroad-slave`'s primary group membership gives it, used here only for read access, not as a separate `xroad-slave` group, which does not exist). The `xroad-slave` account itself cannot write to it (group read, no group write). `sshd` can still read it to authenticate incoming connections. The account's membership in the `xroad` group is also what lets it read the `/etc/xroad` tree that `rsync` serves.

On the **secondary**, generate a key for the `xroad` system account, using a synchronization-specific key name (not the default `id_ed25519`, to keep this key's purpose unambiguous if the `xroad` account is ever used for anything else):

```bash
sudo install -d -m 0700 -o xroad -g xroad /home/xroad/.ssh
sudo -u xroad ssh-keygen -t ed25519 -f /home/xroad/.ssh/id_xroad_sync -N ""
sudo -u xroad cat /home/xroad/.ssh/id_xroad_sync.pub
```

**Verify the primary's SSH host identity before using it for this administrative connection too; do not accept a first-use host-key prompt merely because the connection succeeds.** On the **secondary**, as `<SECONDARY_OS_ADMIN_USER>` (not yet as `xroad`):

```bash
ssh-keyscan -t ed25519 <PRIMARY_IP> > /tmp/primary-hostkey-admin.pub
ssh-keygen -lf /tmp/primary-hostkey-admin.pub -E sha256
```

Compare the printed fingerprint against `<PRIMARY_SSH_FINGERPRINT>` recorded in your HA Deployment Profile §2 (the same value Phase 5 already verified). **STOP** on any mismatch. Once it matches, initialize a fresh, empty, dedicated file for this administrative work (do not rely on a prior attempt's file; truncate it explicitly rather than assuming it starts empty), then add the verified key:

```bash
# On the secondary, as <SECONDARY_OS_ADMIN_USER>:
: > /tmp/admin-known-hosts
cat /tmp/primary-hostkey-admin.pub >> /tmp/admin-known-hosts
rm -f /tmp/primary-hostkey-admin.pub
```

This ensures the file contains only the fingerprint you just verified, never silently reused trust data left over from an earlier, possibly interrupted attempt.

**Step 1a: stage the public key locally first.** Do not assume `<SECONDARY_OS_ADMIN_USER>` can read directly into `/home/xroad/.ssh` to run the transfer from there: that directory stays mode `0700`, owned `xroad:xroad`, exactly as Phase 11 created it, and this step never relaxes that. Instead, use `sudo` once to copy only the public key out to an exactly-named staging file that `<SECONDARY_OS_ADMIN_USER>` can read on its own:

```bash
# On the secondary:
sudo install -o root -g root -m 0444 /home/xroad/.ssh/id_xroad_sync.pub /tmp/id_xroad_sync.pub.stage
```

This touches only `id_xroad_sync.pub`, the public key; the private key `id_xroad_sync` is never copied, read, or exposed by this step, and `/home/xroad/.ssh` itself is untouched. The staged file is world-readable, which is appropriate here because it holds only public key material.

**Step 1b: transfer the staged public key to the primary**, using `<PRIMARY_OS_ADMIN_USER>` recorded in your HA Deployment Profile, with strict host-key checking against the file you already verified:

```bash
# On the secondary:
scp -o UserKnownHostsFile=/tmp/admin-known-hosts -o StrictHostKeyChecking=yes \
  /tmp/id_xroad_sync.pub.stage \
  <PRIMARY_OS_ADMIN_USER>@<PRIMARY_IP>:/tmp/id_xroad_sync.pub
```

Once the transfer succeeds, remove the local staged copy immediately; it has no further use. This file is owned `root:root` (from the `install` command above), and `/tmp` normally has the sticky bit set, so `<SECONDARY_OS_ADMIN_USER>` cannot remove it without `sudo`; do not change the file's ownership merely to avoid using `sudo` here, since root ownership at mode `0444` is deliberate and still safe to remove via `sudo`:

```bash
# On the secondary:
sudo rm -f /tmp/id_xroad_sync.pub.stage
```

**Step 2: open an interactive, host-key-verified administrative session on the primary**, so that a normal, password-requiring `sudo` can prompt as it would at the console. Do not pipe key material through a non-interactive `ssh ... 'sudo ...'` command for this: that pattern has no interactive terminal and already has stdin occupied by the piped data, so `sudo` cannot reliably prompt there, and the only configuration that would make it work silently is passwordless `sudo`, which this guide does not require or assume:

```bash
# On the secondary:
ssh -o UserKnownHostsFile=/tmp/admin-known-hosts -o StrictHostKeyChecking=yes -t \
  <PRIMARY_OS_ADMIN_USER>@<PRIMARY_IP>
```

**Step 3: from that same interactive shell, on the primary**, install the staged key as the final `authorized_keys` content in one atomic step (this replaces any prior content rather than appending, so a repeated attempt after a partial failure cannot leave a duplicate or stale key line behind):

```bash
sudo install -o root -g xroad -m 0640 /tmp/id_xroad_sync.pub /home/xroad-slave/.ssh/authorized_keys
```

**Step 4: remove the staged copy, still in the same session:**

```bash
rm -f /tmp/id_xroad_sync.pub
```

**Step 5: before ending the session, verify the final file has exactly the intended key and the expected ownership/mode**, still on the primary:

```bash
sudo ls -ld /home/xroad-slave/.ssh
sudo ls -l /home/xroad-slave/.ssh/authorized_keys
sudo cat /home/xroad-slave/.ssh/authorized_keys
```

Expected result: the directory is `drwxr-x---` owned `root:xroad`; the file is `-rw-r-----` owned `root:xroad`; the file contains exactly one line, the secondary's public key transferred in step 1b. Also confirm both staged public-key copies are gone now that the installation succeeded: `/tmp/id_xroad_sync.pub.stage` on the secondary (removed in step 1b) and `/tmp/id_xroad_sync.pub` on the primary (removed in step 4, confirm with `ls /tmp/id_xroad_sync.pub` reporting no such file). Now end the session and clean up the secondary's one-time trust file:

```bash
exit
# Back on the secondary:
rm -f /tmp/admin-known-hosts
```

Verify the local staged public-key copy is actually gone, now that the procedure has returned to the secondary:

```bash
test ! -e /tmp/id_xroad_sync.pub.stage && echo "local-stage-removed"
```

Expected result: `local-stage-removed`. Together with Step 5's primary-side check, this confirms both staged copies of the public key are gone, and that no private key material was ever staged or transferred: only `id_xroad_sync.pub` (the public key) appears anywhere in this phase's `scp`/`install`/`rm` commands; `id_xroad_sync` (the private key) stays under `/home/xroad/.ssh`, mode `0700`, owned `xroad:xroad`, untouched throughout.

**Step 6: continue with the dedicated `xroad` sync-user SSH trust**, a separate, permanent trust store from the one-time administrative session above. Verify the host key before trusting it; do not accept it merely because a connection succeeds. Retrieve the primary's host key and compute its fingerprint:

```bash
# On the secondary:
ssh-keyscan -t ed25519 <PRIMARY_IP> > /tmp/primary-hostkey.pub
ssh-keygen -lf /tmp/primary-hostkey.pub -E sha256
```

Compare the printed `SHA256:...` fingerprint against the `<PRIMARY_SSH_FINGERPRINT>` you recorded in your HA Deployment Profile §2 (for example, a fingerprint recorded when that host was provisioned, or confirmed out-of-band with whoever provisioned it). **Only after the fingerprint matches**, install the verified key into the `xroad` account's own `known_hosts`:

```bash
sudo install -d -m 0700 -o xroad -g xroad /home/xroad/.ssh
sudo -u xroad sh -c 'cat /tmp/primary-hostkey.pub >> /home/xroad/.ssh/known_hosts'
rm -f /tmp/primary-hostkey.pub
```

Now test the connection. This should succeed with no host-key prompt, because the key is already verified and trusted:

```bash
sudo -u xroad ssh -i /home/xroad/.ssh/id_xroad_sync xroad-slave@<PRIMARY_IP> "echo connection-ok"
```

Expected result: the command prints `connection-ok`, with no password prompt and no host-key prompt.

## Phase 12 - Configure and enable scheduled synchronization

On the **secondary**, create the sync log file first, so the service has somewhere to write from its very first run:

```bash
sudo install -o xroad -g xroad -m 0640 /dev/null /var/log/xroad/slave-sync.log
```

Create `/etc/systemd/system/xroad-sync.service`:

```bash
sudo tee /etc/systemd/system/xroad-sync.service >/dev/null <<'EOF'
[Unit]
Description=X-Road Sync Task
After=network.target
Before=xroad-proxy.service
Before=xroad-signer.service
Before=xroad-confclient.service
Before=xroad-proxy-ui-api.service

[Service]
User=xroad
Group=xroad
Type=oneshot
ExecStartPre=/usr/bin/test ! -f /var/tmp/xroad/sync-disabled
ExecStart=/usr/bin/rsync -e "ssh -i /home/xroad/.ssh/id_xroad_sync -o ConnectTimeout=5" -aqz --timeout=10 --delete-delay --exclude db.properties --exclude "/conf.d/node.ini" --exclude "*.tmp" --exclude "/postgresql" --exclude "/globalconf" --exclude "/gpghome" --delay-updates --log-file=/var/log/xroad/slave-sync.log xroad-slave@<PRIMARY_IP>:/etc/xroad/ /etc/xroad/

[Install]
WantedBy=multi-user.target
WantedBy=xroad-proxy.service
EOF
```

Create `/etc/systemd/system/xroad-sync.timer`:

```bash
sudo tee /etc/systemd/system/xroad-sync.timer >/dev/null <<'EOF'
[Unit]
Description=Run CamDX X-Road configuration sync periodically

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=xroad-sync.service

[Install]
WantedBy=timers.target
EOF
```

The `Before=`/`WantedBy=xroad-proxy.service` pairing makes systemd run the sync before the dependent X-Road services at boot, rather than relying solely on the timer happening to fire first.

Validate both unit files before enabling them:

```bash
sudo systemd-analyze verify /etc/systemd/system/xroad-sync.service /etc/systemd/system/xroad-sync.timer
```

Expected result: no output (a syntax or reference error would print a warning/error line naming the problem). **STOP** and fix the unit file if `systemd-analyze verify` prints anything.

Enable both units now; it is safe to do so before Initial Configuration exists on the primary, since there is nothing meaningful to sync yet and this periodic unit always excludes `/globalconf` (the one-time bootstrap sync in Phase 19 is a separate, manual command that does not exclude it):

```bash
sudo systemctl daemon-reload
sudo systemctl enable xroad-sync.service
sudo systemctl enable --now xroad-sync.timer
```

Verify:

```bash
systemctl is-enabled xroad-sync.service xroad-sync.timer
systemctl list-timers xroad-sync.timer
sudo systemctl start xroad-sync.service
systemctl show xroad-sync.service -p Result -p ExecMainStatus -p ActiveState -p SubState
```

Expected result: both units `enabled`, the timer listed as active, and after the manual run: `Result=success`, `ExecMainStatus=0`, `ActiveState=inactive`, `SubState=dead`. Do not rely on the shell exit status of `systemctl status` alone to confirm a successful run; `inactive`/`dead` is the normal resting state for this one-shot unit between runs, not a failure, and the `systemctl show` fields above are the unambiguous way to confirm the run itself actually succeeded.

## Phase 13 - Configure sync log rotation

On the **secondary**, create `/etc/logrotate.d/xroad-slave-sync`:

```bash
sudo tee /etc/logrotate.d/xroad-slave-sync >/dev/null <<'EOF'
/var/log/xroad/slave-sync.log {
    daily
    rotate 7
    missingok
    compress
    su xroad xroad
    nocreate
}
EOF
```

Validate the configuration with a dry run:

```bash
sudo logrotate -d /etc/logrotate.d/xroad-slave-sync
```

Expected result: the dry-run output describes what it would do (for example, that the log does not yet need rotating) without reporting a syntax/parse error. **STOP** and fix the file if `logrotate -d` reports an error parsing it.

Confirm the log file (created in Phase 12) remains writable by the `xroad`/`xroad` user/group that the `xroad-sync.service` unit (`User=xroad`, `Group=xroad`) runs as:

```bash
ls -l /var/log/xroad/slave-sync.log
```

Expected result: owned `xroad:xroad`, mode `640`.

## Phase 14 - Configure node roles

On the **primary**, create `/etc/xroad/conf.d/node.ini`:

```bash
sudo tee /etc/xroad/conf.d/node.ini >/dev/null <<'EOF'
[node]
type=master
EOF
```

On the **secondary**, create `/etc/xroad/conf.d/node.ini`:

```bash
sudo tee /etc/xroad/conf.d/node.ini >/dev/null <<'EOF'
[node]
type=slave
EOF
```

On both:

```bash
sudo chown xroad:xroad /etc/xroad/conf.d/node.ini
sudo chmod 640 /etc/xroad/conf.d/node.ini
```

Verify, on each node:

```bash
sudo cat /etc/xroad/conf.d/node.ini
sudo stat -c '%U:%G %a %n' /etc/xroad/conf.d/node.ini
```

Expected result: the primary prints `type=master`; the secondary prints `type=slave`; both print `xroad:xroad 640 /etc/xroad/conf.d/node.ini`. `master` and `slave` are the literal, required X-Road configuration values; there is no `type=primary`/`type=secondary` syntax. "Primary" and "secondary" are the explanatory terms this guide and CamDX documentation use for the same two roles. This file is permanently excluded from `rsync` (Phase 12); it must never be synchronized between nodes.

## Phase 15 - Restrict secondary administration

**First, discover who currently has writable Admin UI/API access on the secondary, before changing anything.** On the **secondary**:

```bash
getent group xroad-registration-officer xroad-service-administrator xroad-system-administrator
```

Expected normal case: each line lists only `<SECONDARY_ADMIN_USER>` (recorded in your HA Deployment Profile §2), the X-Road Admin UI account created during Phase 2's installation. **STOP** if any other account name appears; it did not come from this guide's own Phase 2, so confirm with your own organization whether that account is expected before changing its access, since an unexpected account may indicate a configuration you did not intend. Do not remove anything until you have confirmed the complete set of accounts you intend to restrict.

**Once the set of accounts to restrict is confirmed** (normally just `<SECONDARY_ADMIN_USER>`; otherwise that account plus every other one you confirmed with your organization), remove each of them from the three writable role groups:

```bash
sudo deluser <SECONDARY_ADMIN_USER> xroad-registration-officer
sudo deluser <SECONDARY_ADMIN_USER> xroad-service-administrator
sudo deluser <SECONDARY_ADMIN_USER> xroad-system-administrator
```

Repeat this same three-command block, substituting the account's name for `<SECONDARY_ADMIN_USER>`, for each additional confirmed account.

Retain `xroad-securityserver-observer` and `xroad-security-officer`; do not remove these, as they are needed for read-only diagnostics and local token/PIN operations respectively.

**Verify each restricted account individually:**

```bash
id <SECONDARY_ADMIN_USER>
```

Expect the group list to include `xroad-securityserver-observer` and `xroad-security-officer`, and **not** `xroad-registration-officer`, `xroad-service-administrator`, or `xroad-system-administrator`. Repeat this `id` check for every other account you restricted above.

**Finally, re-run the discovery command to confirm the restriction actually took effect:**

```bash
getent group xroad-registration-officer xroad-service-administrator xroad-system-administrator
```

Expected result now: none of the accounts you just restricted appears in any of the three lines (the three groups may now be empty, or may list only accounts you deliberately did not restrict, if any). Do not expect `<SECONDARY_ADMIN_USER>` to still appear here; that would mean the removal did not take effect. If any restricted account still appears in a given group, repeat the `deluser` command for that specific group and verify again.

## Phase 16 - Configure load-balancer behavior and the health check

On the **primary**, check whether `/etc/xroad/conf.d/local.ini` already exists:

```bash
sudo test -f /etc/xroad/conf.d/local.ini && echo "exists" || echo "does not exist yet"
```

**If it does not exist yet**, create it directly with the required content:

```bash
sudo tee /etc/xroad/conf.d/local.ini >/dev/null <<'EOF'
[message-log]
message-body-logging=false

[proxy]
server-support-clients-pooled-connections=false
health-check-interface=0.0.0.0
health-check-port=5588
EOF
sudo chown xroad:xroad /etc/xroad/conf.d/local.ini
sudo chmod 640 /etc/xroad/conf.d/local.ini
```

**If it already exists** (for example, from a prior standalone installation that already set `message-body-logging`), do not overwrite it blindly. Back it up and inspect its existing sections first:

```bash
sudo cp -a /etc/xroad/conf.d/local.ini /etc/xroad/conf.d/local.ini.pre-ha
sudo cat /etc/xroad/conf.d/local.ini
sudoedit /etc/xroad/conf.d/local.ini
```

Ensure the file contains exactly one `[message-log]` section with `message-body-logging=false` (do not duplicate this section if it is already present; add the line inside the existing section instead), and add a `[proxy]` section (or add these three lines inside an existing one, if it already exists for an unrelated reason):

```ini
server-support-clients-pooled-connections=false
health-check-interface=0.0.0.0
health-check-port=5588
```

`message-body-logging=false` is CamDX's required setting regardless of HA; `server-support-clients-pooled-connections=false` is required specifically for load-balanced HA, because load balancing happens at the TCP level and a pooled/persistent connection would defeat even traffic distribution. `health-check-port=5588` enables the health-check service used from Phase 22 onward.

Verify there is exactly one of each section, with no duplicate:

```bash
grep -n '^\[' /etc/xroad/conf.d/local.ini
```

Expected result: `[message-log]` appears exactly once and `[proxy]` appears exactly once. **STOP** and remove the duplicate manually if either section name appears twice; a duplicated INI section silently shadows one of its own settings depending on parse order, which is not safe to leave in place.

This file is carried to the secondary by the one-time bootstrap sync (Phase 19) and the ongoing scheduled sync (Phase 12). `xroad-proxy` has not started yet on either node (Phase 3 stopped it, Phase 17/20 start it for the first time since), so this takes effect on first start. If you ever edit `local.ini` again after services are running, restart `xroad-proxy` for the change to take effect:

```bash
sudo systemctl restart xroad-proxy
```

## Phase 17 - Start the PRIMARY application services only

On the **primary only**:

```bash
sudo systemctl start xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog
```

Do **not** start these services on the secondary yet; it does not have a usable configuration until after Initial Configuration and the one-time bootstrap sync (Phase 18-19).

Verify on the primary:

```bash
systemctl is-active xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog xroad-opmonitor
```

Expect `active` for each.

## Phase 18 - Perform Initial Configuration on the PRIMARY ONLY

Complete [Initial Configuration](../initial-configuration.md) on the **primary node's Admin UI only** (`https://<PRIMARY_FQDN>:4000`): configuration anchor import, member/Security Server Code entry, software token PIN, timestamping service, AUTH/SIGN CSRs (Checkpoint B), certificate import, authentication-certificate registration, and subsystem registration. [Initial Configuration](../initial-configuration.md) §9 covers the HA-specific addressing in full; read it before submitting the CSR.

**Use `<VIP_FQDN>` as the Security Server's external address, not either node's own private hostname/IP.** Wherever Initial Configuration asks for the Security Server's DNS name/FQDN or external address (the authentication-certificate CSR's CN/SAN, and the value submitted at registration), use `<VIP_FQDN>`. Do not register either backend node's own private/node FQDN as the logical Security Server address; consumers and providers reach this Security Server only through the load balancer, which performs Layer-4 TCP passthrough to whichever backend is healthy. Confirm `<VIP_FQDN>` actually resolves to, and routes to, your load balancer/VIP before submitting the CSR.

**Do not independently initialize the secondary as a second logical Security Server.** Do not open its Admin UI's first-time setup sequence, import the configuration anchor, create a software token, generate AUTH/SIGN keys, or attempt registration on the secondary at any point. The secondary receives this same identity through the bootstrap sync in the next phase, not through its own registration.

## Phase 19 - Perform the one-time initial bootstrap synchronization

Now that the primary has a real configuration, copy it to the secondary once, manually, **including** `/globalconf` (unlike the ongoing scheduled sync in Phase 12, which always excludes it; see the explanation below).

On the **secondary**:

```bash
sudo -u xroad rsync -e "ssh -i /home/xroad/.ssh/id_xroad_sync" -avz --delete \
  --exclude db.properties --exclude "/postgresql" --exclude "/conf.d/node.ini" --exclude "/gpghome" \
  xroad-slave@<PRIMARY_IP>:/etc/xroad/ /etc/xroad/
```

This bootstrap exclusion list is deliberately smaller than the ongoing scheduled sync's: it still excludes the four permanently node-local items (`db.properties`, the replication certificates under `/postgresql`, `node.ini`, and `/gpghome`), but it does **not** exclude `/globalconf`, because the secondary needs a working copy of the global configuration to start from. After this one-time copy, `xroad-confclient` running on the secondary (once started, Phase 20) independently fetches and maintains its own global configuration going forward; it does not depend on further `rsync` updates for this. That is why the ongoing scheduled sync (Phase 12) permanently excludes `/globalconf`: continuing to overwrite it from the primary's copy would fight with the secondary's own `confclient` process.

## Phase 20 - Start the SECONDARY application services

On the **secondary**:

```bash
sudo systemctl start xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog
```

Verify:

```bash
systemctl is-active xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog xroad-opmonitor
```

Expect `active` for each.

## Phase 21 - Verify configuration, key, and global-configuration propagation

`serverconf` (member/subsystem configuration) is already live on the secondary continuously, through PostgreSQL streaming replication. Confirm on the secondary's Admin UI (`https://<SECONDARY_FQDN>:4000`, read-only) that the **CLIENTS** view shows the same member/subsystem you configured on the primary.

Confirm the global configuration bootstrapped correctly and that `xroad-confclient` is maintaining it on the secondary, using non-secret service/log/file evidence rather than a subjective "looks correct" judgment:

```bash
systemctl is-active xroad-confclient
sudo -u xroad ls -la /etc/xroad/globalconf
sudo journalctl -u xroad-confclient --since "-10 min" | grep -i -E 'download|refresh|error' || echo "no matching recent confclient log lines"
curl -i http://127.0.0.1:5588/
```

Expected result: `xroad-confclient` is `active`; `/etc/xroad/globalconf` contains files (not empty); recent `xroad-confclient` log activity shows a successful download/refresh with no error (or no matching lines yet, which is acceptable immediately after the bootstrap sync); the health endpoint's response body does not name a global-configuration-related failure. These four items, not file timestamps, are what determine PASS here: `/etc/xroad/globalconf`'s file timestamps may optionally be displayed again a few minutes later as supplementary, illustrative evidence that `xroad-confclient` is independently refreshing it, but an unchanged timestamp must not by itself fail this check; this guide has not established exactly when a refresh is guaranteed to touch every file's timestamp for this exact build, and does not ask you to wait on an unconfirmed timing assumption.

Confirm the AUTH and SIGN certificate/key files under `/etc/xroad/signer` exist on the secondary and match the primary, without printing or checksumming any private-key content:

```bash
sudo -u xroad find /etc/xroad/signer -maxdepth 1 -printf '%f %s\n' | sort
```

Expected result: the secondary's listing of filenames and sizes matches the primary's equivalent listing (run the same command on the primary to compare). Do not expect the secondary's modification timestamps to be at or after the Phase 19 bootstrap sync time: the sync runs `rsync -a`, which preserves the source's original modification times, so the secondary's copy legitimately carries the primary's original timestamp, which may be well before the sync ran. Filename/size matching, not timestamps, is the evidence here. This command prints filenames and sizes only; it never prints or hashes private-key content, so it is safe to include in evidence/escalation records.

The software token shows as present but likely **not yet logged in** on the secondary. **This must be done explicitly**: replicating the token file does not automatically unlock it. Using the retained `xroad-security-officer` role, log in via **Keys and Certificates, Token, Login**, entering the same PIN used on the primary. **A successful login here is itself confirming evidence that the signer/token state propagated correctly**: if the PIN that works on the primary is rejected on the secondary, that indicates the token/key state did not propagate as expected, and you should treat it as a STOP condition per [HA Troubleshooting](../troubleshooting/high-availability.md) rather than retrying the PIN. Do this login again after any later token-state change on the primary, or after a secondary reboot.

Do not configure unattended plaintext PIN autologin (`xroad-autologin`) as the standard production path for the secondary; manual login by a security officer after each relevant event is the default here. If your organization has a specific operational reason to use autologin and wants CamDX's input on it, that is a separate decision to raise with CamDX, not part of this standard procedure.

## Phase 22 - Verify the health endpoint on each node

On **each** node:

```bash
curl -i http://127.0.0.1:5588/
```

Expect `HTTP/1.1 200 OK`. From the load balancer's own health-check source (or another host inside the health-check source CIDR from your HA Deployment Profile), run this once against each node's own address:

```bash
curl -i http://<PRIMARY_IP>:5588/
curl -i http://<SECONDARY_IP>:5588/
```

`HTTP 500` means a failed check (the response body names the specific failure: token not logged in, OCSP not good, `serverconf` unreachable, or global configuration invalid/expired); `HTTP 503` means the node has been deliberately placed into maintenance mode (see Phase 26). Resolve a `500` before continuing; it is not expected at this point in a correctly completed procedure.

## Phase 23 - Configure the external load balancer

Your own load-balancer administrator implements this using whichever product you selected in your HA Deployment Profile. This guide states the required behavior precisely rather than any one vendor's syntax, and does not require CamDX support:

- Layer 4 / TCP load balancing with TLS passthrough. The load balancer must not terminate TLS; the Security Server does that. This does not eliminate the possibility of some in-flight message loss on a node failure; it is a load-balancing architecture, not a zero-loss fault-tolerance guarantee.
- Health check: `HTTP GET` to port `5588` on each backend, expecting `200`. A backend must be removed from rotation on any other response.
- Forward TCP `5500` and `5577` to both nodes, per [Network Requirements](../network-requirements.md) §8.
- Forward your deployment's client-proxy port (`<CLIENT_PROXY_PORT>`) to both nodes, **only if** your HA Deployment Profile §2 records "Client-proxy traffic forwarded through VIP" as `YES`. If it records `NO`, skip this VIP client-proxy forwarding step. This HA procedure does not define an alternate consumer-to-client-proxy path. If your deployment requires one, it must be separately defined and approved as stated in the HA Deployment Profile §2. Do not infer or invent that path here.
- Do not load-balance TCP `4000` (Admin UI) as if both nodes were equally writable; the secondary's UI is read-only. Point administrators at the primary directly, or make the VIP's `4000` forwarding explicit about which node it reaches, per your own administration network's needs.
- Support connection draining, so a node you place into maintenance mode (Phase 26) finishes in-flight connections rather than dropping them abruptly.

**Reference implementation example: HAProxy.** This is an educational reference implementation, not a requirement to use HAProxy in production. It shows how the requirements above map onto a concrete Layer-4, TLS-passthrough configuration; your own load-balancer product may be entirely different.

```text
# /etc/haproxy/haproxy.cfg (excerpt - educational reference only)
# Always required: X-Road peer interfaces (message transport on 5500, OCSP response relay on 5577).

frontend ft_xroad_5500
    bind *:5500
    mode tcp
    default_backend bk_xroad_5500

backend bk_xroad_5500
    mode tcp
    option httpchk GET /
    http-check expect status 200
    server primary   <PRIMARY_IP>:5500   check port 5588
    server secondary <SECONDARY_IP>:5500 check port 5588

frontend ft_xroad_5577
    bind *:5577
    mode tcp
    default_backend bk_xroad_5577

backend bk_xroad_5577
    mode tcp
    option httpchk GET /
    http-check expect status 200
    server primary   <PRIMARY_IP>:5577   check port 5588
    server secondary <SECONDARY_IP>:5577 check port 5588
```

`option httpchk GET /` plus `http-check expect status 200` makes HAProxy's health probe implement the documented requirement exactly: HAProxy opens a separate check connection to `check port 5588` and sends a real `HTTP GET /`, keeping a backend in rotation only on a literal `200` response; a `500` (failed check) or `503` (maintenance mode) removes it, the same as the health endpoint's own documented contract. This check connection is independent of the backend's own `mode tcp` data-plane connections on `5500`/`5577`, which still never get HTTP semantics applied to them and are passed through unmodified; a bare TCP connect (`option tcp-check`) is not sufficient here, since it would leave an unhealthy backend (`500`) or a deliberately maintenance-mode backend (`503`) in rotation as long as the TCP port itself still accepts connections. No `bind ... ssl` or `mode http` directive appears anywhere in this excerpt; HAProxy only passes the data-plane TCP stream through unmodified, consistent with the Layer-4/TLS-passthrough requirement above.

**Include the block below only if your HA Deployment Profile §2 records "Client-proxy traffic forwarded through VIP" as `YES`.** If it records `NO`, do not add this block to your HAProxy configuration at all: the client-proxy port is not forwarded through this load balancer in your deployment, and the two `frontend`/`backend` pairs above are the complete reference configuration for you.

```text
# /etc/haproxy/haproxy.cfg (excerpt - educational reference only)
# Only if HA Deployment Profile §2 "Client-proxy traffic forwarded through VIP" = YES.

frontend ft_xroad_clientproxy
    bind *:<CLIENT_PROXY_PORT>
    mode tcp
    default_backend bk_xroad_clientproxy

backend bk_xroad_clientproxy
    mode tcp
    option httpchk GET /
    http-check expect status 200
    server primary   <PRIMARY_IP>:<CLIENT_PROXY_PORT>   check port 5588
    server secondary <SECONDARY_IP>:<CLIENT_PROXY_PORT> check port 5588
```

The same health-check semantics described above apply to this block: `check port 5588` keeps a backend in rotation only on a literal `200`, and the client-proxy port's own `mode tcp` data-plane connections are passed through unmodified here as well, never terminated or inspected by HAProxy.

## Phase 24 - Verify the load balancer

The reference HAProxy configuration in Phase 23 has no listener for `5588` on the VIP; the health-check port is reached directly on each backend, by the load balancer itself, never through the VIP. Do not add a VIP-facing `5588` listener merely to make a test convenient; verify each piece from the host that is actually meant to reach it.

**First, validate each backend's health endpoint from the load balancer's own health-check source.** Run this from a host inside the load-balancer health-check source CIDR recorded in your HA Deployment Profile §2 (ideally the load-balancer host itself, since that is the actual health-check source in production):

```bash
curl -i http://<PRIMARY_IP>:5588/
curl -i http://<SECONDARY_IP>:5588/
```

Expected result: both return `HTTP/1.1 200 OK`. A `curl` from an arbitrary administration workstation outside this CIDR may be blocked by the firewall rule from Phase 16/23 even when the backend is healthy; that is the firewall working as designed, not a defect, so run this specific check from the permitted source.

**Second, confirm the load balancer's own operational/status view**, on the load-balancer host itself (not the Security Server nodes): the method you recorded in your HA Deployment Profile §6 (for example, an HAProxy stats page, a vendor API/CLI command, or an equivalent status interface). Expected result: both backends shown healthy and in rotation.

**Third, validate the VIP on its real forwarded data-plane port(s)**, from a source permitted by the backend firewall/source-CIDR policy for `5500`/`5577` (per your HA Deployment Profile §5's backend data-plane CIDRs). Use `<VIP_FQDN>` (the mandatory logical external address, HA Deployment Profile §2), not `<VIP_IP>` (which is optional and recorded for infrastructure documentation only): testing the FQDN also proves DNS resolution of the actual registered HA logical address, not merely IP-level connectivity. Prefer the load-balancer host or an equivalent test context your network actually permits; do not use an arbitrary administration workstation that the backend firewall rules were never scoped to allow:

```bash
nc -vz <VIP_FQDN> 5500
nc -vz <VIP_FQDN> 5577
```

**If your HA Deployment Profile §2 records "Client-proxy traffic forwarded through VIP" as `YES`**, also run the equivalent `nc -vz <VIP_FQDN> <CLIENT_PROXY_PORT>` for your deployment's client-proxy port, from an authorized consumer-network test host. Expected result: `succeeded` or `open`. If that field records `NO`, skip this check; the client-proxy port is not forwarded through the VIP in your deployment.

Direct per-backend `5500`/`5577` checks, if you also want them, are subject to the same source restriction (the backend data-plane CIDRs, not an arbitrary workstation):

```bash
nc -vz <PRIMARY_IP> 5500
nc -vz <PRIMARY_IP> 5577
nc -vz <SECONDARY_IP> 5500
nc -vz <SECONDARY_IP> 5577
```

**STOP condition:** if either backend's `5588` check fails, or the load balancer's own status view does not show both backends healthy and in rotation, or the VIP's data-plane ports do not respond, resolve the failure (see [HA Troubleshooting](../troubleshooting/high-availability.md)) before proceeding. End-to-end validation of the VIP itself, with a real request rather than a bare port check, continues in Phase 25.

## Phase 25 - Real API validation

**Where to run this:** the "Test client/source" recorded in your HA Deployment Profile §6, through the VIP (`<VIP_FQDN>`), not directly against either backend.

**Which profile field contains the exact procedure:** HA Deployment Profile §6, the "Exact approved test command / procedure / script" row. That field, not this runbook, is the source of truth for the actual transaction: your member's real test may be a `curl` command, an application-level test script, a manual action in your own client application, or another approved procedure. Do not assume this runbook requires a generic `curl` example; it does not, because the correct command depends on your own registered client/service.

**How to execute it:** run the exact command/procedure/script recorded in that profile field, from the recorded test client/source, targeting `<VIP_FQDN>` and the known-good test subsystem/service recorded in the same §6. If that field records that a secret or token is required, retrieve it from your organization's approved secret storage as the field directs; never read it from the profile itself.

**Expected result:** the exact response/result recorded in HA Deployment Profile §6's "Expected success result" field. Compare the actual result against that defined expectation; do not accept a subjective "looks like it worked" in its place.

**Evidence to record**, capturing the correlation value per the method recorded in HA Deployment Profile §6's "How you capture the correlation value" field, in the field (`QUERYID` or `XREQUESTID`) recorded as the "Standard correlation field":

- The request result (success/failure), compared against the expected result recorded in the profile.
- Which backend handled it, if your load balancer or application logs let you observe this.
- The request's own correlation identifier, captured per the profile's recorded capture method. This confirms the mechanism works; the per-node acceptance evidence itself is captured separately, from the forced-backend transactions in Phase 26.
- That CamDX/peer visibility (central monitoring) shows the activity, if observable from your side.

**STOP condition:** if your HA Deployment Profile §6 does not yet record the exact test command/procedure, its expected result, or its evidence/correlation method, define and confirm all three now, with a real registered client and service, before performing this step. Do not reach Phase 28's acceptance checklist having never defined what a successful test transaction looks like, or how to execute it, for your deployment.

**Next step:** Phase 26.

## Phase 26 - Backend maintenance test

This phase both tests X-Road's own maintenance mechanism and produces the two backend-specific transactions Phase 28 later verifies per node in `messagelog`/DIAGNOSTICS, Traffic: while the primary is in maintenance, the request the secondary serves becomes the **SECONDARY acceptance transaction**; while the secondary is in maintenance, the request the primary serves becomes the **PRIMARY acceptance transaction**. This is what lets Phase 28 prove each node specifically, rather than guessing which backend handled a single VIP request from load-balancer logs.

**On the primary**, place it into maintenance mode:

```bash
curl -i "http://localhost:5566/maintenance?targetState=true"
```

Confirm: the primary's health check (Phase 22) now returns `503`; the load balancer removes it from rotation. With the primary unavailable, the secondary must serve the next request; execute the exact Phase 25 test procedure (from HA Deployment Profile §6) now, confirm it succeeds, and capture its correlation identifier (per the profile's "How you capture the correlation value" field) as the **SECONDARY acceptance transaction**. **Only after** this transaction has succeeded and its identifier is captured, disable maintenance mode on the primary.

**On the primary**, disable maintenance mode:

```bash
curl -i "http://localhost:5566/maintenance?targetState=false"
```

Confirm: the primary's health check returns `200` again once its normal health/token state is restored; the load balancer returns it to rotation.

**Then, on the secondary**, run the equivalent sequence explicitly (do not assume the primary's steps above transfer without restating them):

```bash
curl -i "http://localhost:5566/maintenance?targetState=true"
```

Confirm: the secondary's health check (Phase 22) now returns `503`; the load balancer removes it from rotation. With the secondary unavailable, the primary must serve the next request; execute the exact Phase 25 test procedure now, confirm it succeeds, and capture its correlation identifier as the **PRIMARY acceptance transaction**. **Only after** this transaction has succeeded and its identifier is captured, disable maintenance mode on the secondary.

```bash
curl -i "http://localhost:5566/maintenance?targetState=false"
```

Confirm: the secondary's health check returns `200` again once its normal health/token state is restored; the load balancer returns it to rotation.

**Do not promote or demote the PostgreSQL `serverconf` primary during this test.** Maintenance mode only affects which node the load balancer sends traffic to; it has no effect on database replication direction.

## Phase 27 - Service restart and OS reboot recovery

Perform these tests **one node at a time**, so the other node remains available throughout. **Do not perform automatic or manual primary promotion during this phase.**

**Do not use X-Road's own maintenance mode (Phase 26) to keep a node out of rotation for this phase.** Maintenance mode resets automatically on the next `xroad-proxy` restart; this phase deliberately restarts `xroad-proxy` (service restart recovery) and reboots the whole OS (full reboot recovery), either of which would silently clear maintenance mode before your post-restart/post-reboot verification is complete, no longer guaranteeing the node is actually out of rotation while you test it. Instead, use the **persistent, load-balancer-side** drain method recorded in your HA Deployment Profile §6: "Backend disable/drain method" (to remove a node) and "Backend re-enable/return-to-rotation method" (to return it). **STOP** if either field is not yet defined in your profile; define and confirm both with your load-balancer administrator before starting this phase. Maintenance mode remains the correct mechanism for Phase 26, where the maintenance mechanism itself is what is being tested; it is not used in this phase.

### Service restart recovery

For **each** node in turn:

1. Execute your HA Deployment Profile §6's recorded backend disable/drain method against that node.
2. Confirm from the load-balancer's own operational/status interface (HA Deployment Profile §6) that the backend is actually out of rotation. **STOP** if it is not; do not proceed to restart services on a node the load balancer still considers in rotation.
3. Restart the X-Road application services on that node:
   ```bash
   sudo systemctl restart xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog
   ```
4. Verify:
   - services return healthy: `systemctl is-active xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog xroad-opmonitor` all `active`;
   - `serverconf` remains reachable: `sudo -u postgres pg_isready -p 5433`;
   - node role is still correct: `cat /etc/xroad/conf.d/node.ini`;
   - `db.properties` still points `serverconf` at `127.0.0.1:5433` (Phase 7/Phase 10);
   - on the secondary specifically, `xroad-sync.timer`/`.service` remain healthy (Phase 12);
   - global configuration is valid: `ls -la /etc/xroad/globalconf`;
   - local Operational Monitoring is healthy: `systemctl is-active xroad-opmonitor`;
   - the health endpoint returns `200` once token state is confirmed valid (re-log the token in per Phase 21 if needed).
5. Only after all checks in step 4 pass, execute your HA Deployment Profile §6's recorded backend re-enable/return-to-rotation method against that node.
6. Confirm from the load-balancer's own operational/status interface that the backend is healthy and in rotation again.
7. Repeat a known-good real API request through the VIP (as in Phase 25).

### Full OS reboot recovery

Test the **secondary first, then the primary**.

For **each** node in turn:

1. Execute your HA Deployment Profile §6's recorded backend disable/drain method against that node, and confirm from the load-balancer's own operational/status interface that it is actually out of rotation. **STOP** if it is not.
2. Reboot the node's operating system:
   ```bash
   sudo reboot
   ```
   The SSH session disconnects immediately; this is expected.

   Reconnect from the same secure admin workstation and directory you used in Phase 5 (where `ha-ca/ha-known-hosts` was created and still exists), using strict host-key checking against that same retained file, and the OS deployment administrator account for the node you just rebooted:

   For the **secondary** pass:
   ```bash
   cd ha-ca
   ssh -o UserKnownHostsFile=./ha-known-hosts -o StrictHostKeyChecking=yes <SECONDARY_OS_ADMIN_USER>@<SECONDARY_IP>
   ```

   For the **primary** pass:
   ```bash
   cd ha-ca
   ssh -o UserKnownHostsFile=./ha-known-hosts -o StrictHostKeyChecking=yes <PRIMARY_OS_ADMIN_USER>@<PRIMARY_IP>
   ```

   The node will not accept SSH connections for some period while it boots; retry the `ssh` command above every 30 seconds or so until it connects. ICMP reachability (`ping <SECONDARY_IP>`/`ping <PRIMARY_IP>`) is not a prerequisite for SSH and is not required before retrying; you may check it as optional supplementary information, but a blocked ping is not a STOP condition and must not be used to decide the node is unreachable. The authoritative recovery signal is the SSH connection itself succeeding on TCP `22`, with the host key matching `./ha-known-hosts` exactly as it already does (do not expect a prompt here: `StrictHostKeyChecking=yes` against the file you already populated in Phase 5 means this either connects silently or fails closed, never prompts). **If you are reconnecting from a different workstation or directory** where `ha-ca/ha-known-hosts` does not exist, do not fall back to an unverified connection: repeat the independent host-key fingerprint verification from Phase 5 for this node, add the verified key to a dedicated file on that workstation, and use that file with the same `-o UserKnownHostsFile=...` /`-o StrictHostKeyChecking=yes` options instead. Once reconnected, run the verification commands in step 3 below.
3. After boot, verify:
   - the dedicated `serverconf` PostgreSQL instance is active;
   - PostgreSQL streaming replication is healthy (repeat the Phase 9 checks);
   - **on the secondary only**, `xroad-sync.service`/`.timer` are enabled and the boot-time sync completed successfully:
     ```bash
     systemctl is-enabled xroad-sync.service xroad-sync.timer
     systemctl show xroad-sync.service -p Result -p ExecMainStatus -p ActiveState -p SubState
     ```
     expect `Result=success`, `ExecMainStatus=0`, `ActiveState=inactive`, `SubState=dead` (this is the correct resting state for a successful one-shot unit, not a failure);
   - **on the primary, this check does not apply.** `xroad-sync.service` and `xroad-sync.timer` exist only on the secondary; do not create or enable either unit on the primary, and do not expect them when verifying the primary's reboot;
   - `node.ini`'s role survived the reboot;
   - `db.properties` still points `serverconf` at `127.0.0.1:5433`;
   - the X-Road application services recovered: `systemctl is-active xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog xroad-opmonitor`;
   - global configuration is valid;
   - local Operational Monitoring is healthy.
4. **Expected post-reboot token behavior:** because this procedure uses manual secondary token login by default, the software token may be locked after a reboot (on either node). The health endpoint may therefore return `500` until a security officer logs the token in again. This is expected, not a fault. Log the token in (Phase 21's method on the secondary; the Admin UI directly on the primary), then confirm the health endpoint returns `200`.
5. Only after all checks in steps 3-4 pass, execute your HA Deployment Profile §6's recorded backend re-enable/return-to-rotation method against that node.
6. Confirm from the load-balancer's own operational/status interface that the backend is healthy and in rotation again.
7. Perform a known-good real API request through the VIP.
8. Confirm the request succeeds while the other node remains available throughout.

Only after both the service-restart and OS-reboot recovery tests pass on both nodes may you proceed to Phase 28's acceptance checklist.

## Phase 28 - Acceptance

Before handing this deployment over or declaring it production-ready, confirm every item below, and complete Checkpoint C with CamDX:

- PostgreSQL streaming replication healthy (Phase 9 checks, re-run), and both nodes still confirmed on the same PostgreSQL major version.
- Secondary `db.properties` confirmed pointed at `127.0.0.1:5433` for `serverconf` (Phase 10).
- On the secondary, scheduled `rsync` is healthy and enabled to survive a reboot: `systemctl is-enabled xroad-sync.service xroad-sync.timer` reports `enabled` for both; `systemctl list-timers xroad-sync.timer` shows it active; `systemctl show xroad-sync.service -p Result -p ExecMainStatus -p ActiveState -p SubState` reports `Result=success`, `ExecMainStatus=0`, `ActiveState=inactive`, `SubState=dead` for the last completed run (this resting state is a successful oneshot unit, not a failure; do not rely on the shell exit status of `systemctl status` alone, per Phase 12). `xroad-sync.service`/`.timer` do not exist on the primary.
- Node roles correct on both nodes (`node.ini`).
- Global configuration valid and independently refreshing on both nodes.
- Secondary administrative restrictions correct (Phase 15, re-verified).
- Software token active and logged in on both nodes.
- Health endpoint returns `200` on both nodes.
- VIP healthy, both backends in rotation, traffic observed reaching both.
- The Phase 25 real API request succeeds through the VIP.
- The Phase 26 request succeeds with either node individually removed from service.
- The Phase 27 service-restart recovery test passed on both nodes.
- The Phase 27 OS-reboot recovery test passed on both nodes (secondary, then primary), including the expected post-reboot token-login behavior.
- **`messagelog` evidence, per node, using each node's own Phase 26 forced-backend transaction** (not a single Phase 25 transaction guessed from load-balancer logs): on each node, `systemctl is-active xroad-addon-messagelog` reports `active`; no relevant recent error in `journalctl -u xroad-addon-messagelog --since "-1 hour"`; and that node's own forced-backend transaction (the **PRIMARY acceptance transaction** on the primary; the **SECONDARY acceptance transaction** on the secondary) is actually present in the local `messagelog` database. There is no Admin UI message-log search; verify it with a read-only, non-secret database query instead. Use the branch matching your HA Deployment Profile §6's "Standard correlation field"; the two fields are not interchangeable, so run only the one that field actually names:

  **If the profile says `QUERYID`:**
  ```bash
  sudo -u postgres psql -p 5432 -Atc \
    "select id, time, queryid, memberclass, membercode, subsystemcode, response from logrecord where queryid = '<the correlation value captured for this node's transaction>' order by time desc;" \
    messagelog
  ```

  **If the profile says `XREQUESTID`:**
  ```bash
  sudo -u postgres psql -p 5432 -Atc \
    "select id, time, xrequestid, memberclass, membercode, subsystemcode, response from logrecord where xrequestid = '<the correlation value captured for this node's transaction>' order by time desc;" \
    messagelog
  ```

  Expected result, on each node: at least one row, with the queried column matching that node's own captured correlation value (the PRIMARY transaction's value on the primary, the SECONDARY transaction's value on the secondary, never the other node's value), and `memberclass`/`membercode`/`subsystemcode` matching the known-good test subsystem recorded in HA Deployment Profile §6. Both query branches select only non-secret identifying metadata; neither ever selects `message`, `signature`, or any other payload/cryptographic column, so either is safe to run and to include in acceptance evidence. `messagelog` is node-local, not replicated between the primary and secondary; this is exactly why each node needs its own forced-backend transaction from Phase 26 rather than one shared transaction.
- **Operational Monitoring evidence, per node, as supporting evidence alongside (not a replacement for) the `messagelog` evidence above** (local topology, the standard path this runbook covers; see [Network Requirements](../network-requirements.md) §7 if your deployment instead uses a separate, approved remote/external topology): on each node, `systemctl is-active xroad-opmonitor` reports `active`; no relevant recent error in `journalctl -u xroad-opmonitor --since "-1 hour"`. Then, on that node, open the Admin UI's **DIAGNOSTICS, Traffic** view (the verified X-Road 7.8.2 traffic-visualization screen; this requires `xroad-addon-opmonitoring`, already installed in Phase 2). **Traffic displays aggregate request counts grouped into time intervals, filtered by Period, Party, Exchange role, and Status; it has no `QUERYID`/`XREQUESTID` filter and cannot uniquely identify one request.** Set **Period** to a deliberately narrow window around that node's own Phase 26 forced-backend transaction; set **Party** to the known-good test subsystem recorded in HA Deployment Profile §6; set **Exchange role** to **Producer** or **Consumer** depending on which side this Security Server played for that test; set **Status** to **Success**. Expected result (PASS), on each node: the Traffic view shows successful request activity in that narrow interval, consistent with that node's forced-backend transaction. **This confirms aggregate traffic activity in the test window; it does not uniquely identify the transaction.** Exact transaction identity and per-node backend attribution come from that node's `messagelog` result above, not from this Traffic view. If your deployment uses remote/external Operational Monitoring instead of local: use the approved CamDX-provided monitoring interface for that topology, and record genuine per-node monitoring evidence from it only if that interface provides an explicit Security Server/node filter or equivalent dimension letting you isolate activity to this specific node. If it does not provide such a filter, record its result only as aggregate ingestion/activity evidence for the test window, not as per-node proof; per-node backend attribution still comes from the forced load-balancer state in Phase 26 plus that node's own `messagelog` result, never from a node filter the deployed interface does not actually have.
- Backup responsibilities recorded: who backs up `serverconf` (from the primary), who backs up each node's own `messagelog`, and how (see [Deployment Model Selector](../deployment-models.md) §1 for the durable-state categories this covers).
- CamDX central monitoring visibility confirmed, final registration/onboarding status confirmed, and production go-live authorized (Checkpoint C).

Only after every item above is confirmed, and Checkpoint C is complete, is this HA deployment ready for production traffic. Continue to Phase 29 for post-acceptance cleanup.

## Phase 29 - Post-acceptance cleanup and handover

After Phase 28's acceptance checklist is complete and Checkpoint C is confirmed, classify and handle the material this procedure created. Do not decide any of this independently without the required retained-material items; where this guide says keep something, keep it.

| Item | Disposition |
|---|---|
| `/tmp` certificate staging files on the primary (Phase 5) | **DELETE** if not already removed in Phase 5. Check first with `ls /tmp/ca.crt /tmp/server-primary.crt /tmp/server-primary.key`; if any are still present, remove exactly those three named files: `sudo rm -f /tmp/ca.crt /tmp/server-primary.crt /tmp/server-primary.key`. Then verify: `test ! -e /tmp/ca.crt && test ! -e /tmp/server-primary.crt && test ! -e /tmp/server-primary.key && echo "primary-stage-removed"`, expecting `primary-stage-removed`. Do not run a broad `ls`/`rm` with a `/tmp/*.crt`/`/tmp/*.key` wildcard for this check; it can match files unrelated to this installation. Do not authorize deleting any other `/tmp/*.crt` or `/tmp/*.key` file on that basis. |
| `/tmp` certificate staging files on the secondary (Phase 5) | **DELETE** if not already removed in Phase 5. Check first with `ls /tmp/ca.crt /tmp/server-secondary.crt /tmp/server-secondary.key`; if any are still present, remove exactly those three named files: `sudo rm -f /tmp/ca.crt /tmp/server-secondary.crt /tmp/server-secondary.key`. Then verify: `test ! -e /tmp/ca.crt && test ! -e /tmp/server-secondary.crt && test ! -e /tmp/server-secondary.key && echo "secondary-stage-removed"`, expecting `secondary-stage-removed`. Same restriction: do not use a broad wildcard, and do not delete any other `/tmp/*.crt`/`/tmp/*.key` file. |
| Installed node private keys (`/etc/xroad/postgresql/server.key` on each node) | **KEEP PERMANENTLY**; PostgreSQL needs these in place for `serverconf` TLS. Never delete these. |
| Workstation copies of the node private keys (`ha-ca/server-primary.key`, `ha-ca/server-secondary.key`) | **DELETE** (or move to approved secure key storage if your organization's lifecycle plan expects to reissue from these specific files later), using your organization's approved secure secret/key-material handling process, once both nodes' installed copies are in place and verified (Phase 5's `openssl verify`/`x509` check). Do not leave these extra workstation copies in place indefinitely after a successful transfer; the installed copies under `/etc/xroad/postgresql/` are the ones this deployment actually uses going forward. |
| Workstation node certificate copies (`ha-ca/server-primary.crt`, `ha-ca/server-secondary.crt`) | **KEEP FOR ROLLBACK** until your organization's own post-acceptance retention period has elapsed, then dispose of per your organization's standard retention policy. These files are not required to issue a replacement certificate later; the CA can reissue a node certificate from its own key regardless. Retain these copies only for rollback, audit, evidence, or comparison against a future certificate, per your organization's own policy, not because they are needed for reissuance. Certificates are not secret; this is a lower-sensitivity item than the private keys above. |
| Workstation host-key trust file (`ha-ca/ha-known-hosts`) | **KEEP WITH DEPLOYMENT RECORDS**; it records the exact, independently verified SSH host-key fingerprints trusted for both nodes during this build, which is useful evidence if a host key's provenance is ever questioned later. It contains only public host keys, never a secret. |
| Workstation CSR files (`ha-ca/*.csr`) | **DELETE**; CSRs have no further use once the corresponding certificate is issued. |
| Replication CA certificate (`ha-ca/ca.crt`, and the copies under `/etc/xroad/postgresql/ca.crt` on both nodes) | **KEEP PERMANENTLY**; required for ongoing replication TLS validation. |
| Replication CA private key (`ha-ca/ca.key`) | **ARCHIVE SECURELY**, per the Phase 5 CA private-key lifecycle note; never on either node. This rule is separate from, and stricter than, the node private-key rule above: the CA key can reissue every node certificate, so its handling requirement does not relax even after a successful one-time transfer. |
| Pre-HA configuration backups (`*.pre-camdx-ha`, `db.properties.pre-ha`, `local.ini.pre-ha`) | **KEEP FOR ROLLBACK** until your organization's own post-acceptance retention period for this change has elapsed, then follow your organization's standard backup-retention policy. |
| Original port-`5432` `serverconf` database | **KEEP FOR ROLLBACK**, retained as rollback material until your organization's approved post-acceptance retention/cleanup decision is completed. Do not drop it as part of this guide; this guide does not authorize independently deciding to drop it. Port `5432` is the original rollback copy; port `5433` is the new authoritative primary `serverconf` instance this HA pair uses going forward. |
| `rsync` SSH key (`/home/xroad/.ssh/id_xroad_sync{,.pub}` on the secondary) | **KEEP PERMANENTLY**; required for the ongoing scheduled sync (Phase 12). |
| `known_hosts` entry for the primary (on the secondary) | **KEEP PERMANENTLY**; required for the ongoing scheduled sync to continue trusting the primary's host key. |
| HA Deployment Profile (completed copy) | **KEEP PERMANENTLY** with your deployment records. |
| Acceptance evidence (Phase 28 checklist results, Phase 27 recovery-test results, Phase 25 real API request record) | **KEEP PERMANENTLY** with your deployment records; this is what you show CamDX or an auditor if asked to demonstrate this deployment's HA readiness. |

**STOP** before dropping the original port-`5432` `serverconf` database; that decision belongs to your organization's own change-management process, not to this installation guide.

## 30. Failover and primary promotion

There is no automatic failover. If the primary becomes unavailable, the secondary continues serving already-replicated configuration and can continue processing message traffic that does not require a configuration change, but it does not promote itself. Promoting the secondary to primary (changing its `node.ini`, reversing the PostgreSQL replication direction, and re-pointing the former primary as a new secondary once it returns) is a deliberate operational decision with its own procedure, not covered by this installation guide. If you need to plan for this scenario, treat it as a separate disaster-recovery runbook, raised with CamDX; do not improvise a promotion from the steps above.

## 31. If something goes wrong

See [HA Troubleshooting](../troubleshooting/high-availability.md) for the specific symptoms this procedure can produce, and the [Troubleshooting index](../troubleshooting/README.md) for everything else. Preserve the exact error text, the phase you were on, and the output of the relevant verification command before contacting CamDX.

## 32. References

- [HA Deployment Profile](../high-availability-deployment-profile.md), [Network Requirements](../network-requirements.md) §8, [Deployment Model Selector](../deployment-models.md).
- [Ubuntu Standalone Installation](./standalone-installation.md), [Initial Configuration](../initial-configuration.md).
- [RHEL HA Installation](../rhel/high-availability-installation.md) for the equivalent RHEL 9 procedure.
- [HA Troubleshooting](../troubleshooting/high-availability.md).
- Upstream X-Road External Load Balancer Installation Guide and Security Server User Guide (`nordic-institute/X-Road`, version 7.8.2): the architecture, mechanism, and UI terminology this procedure is adapted from and grounded in.
