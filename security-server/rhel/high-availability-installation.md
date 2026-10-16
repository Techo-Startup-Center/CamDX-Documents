# CamDX Security Server - RHEL HA Installation

This is an executable procedure for deploying a native CamDX Security Server HA pair on RHEL 9: a primary and secondary node, replicated `serverconf`, synchronized configuration state, and an external load balancer. It assumes Linux administration experience and CamDX onboarding information, but no prior X-Road HA experience. This document is deliberately self-contained; it does not assume you have the [Ubuntu HA](../ubuntu/high-availability-installation.md) guide open as well.

Existing CamDX deployments using this architecture remain supported. A new HA deployment, an upgrade of an existing one, or a topology change requires a completed [HA Deployment Profile](../high-availability-deployment-profile.md) with Checkpoint A confirmed before you start Phase 1.

Keep SELinux Enforcing throughout this procedure. Never run `setenforce 0` as a remediation step, including temporarily.

**PostgreSQL path scope:** this procedure is written for, and validated against, the standard RHEL 9/AppStream PostgreSQL packaging layout resolved by the CamDX packages (`/var/lib/pgsql/...`, the stock `postgresql.service` unit). If your organization deliberately uses a different PGDG/versioned PostgreSQL layout, treat that as a separate topology/package-layout variant requiring its own adapted procedure before you run any of this guide's destructive/data-copying steps (Phase 8 in particular) against it.

## 0. Architecture summary

A single logical Security Server, identified by one Security Server Code, runs as a **primary** and **secondary** node behind an external Layer-4 load balancer. The primary is the only node where configuration changes originate. `serverconf` replicates continuously via PostgreSQL streaming replication; the remaining shared `/etc/xroad` state (signing/authentication keys and token state) replicates via `rsync` over SSH, once as a one-time bootstrap and then on a schedule. There is no automatic failover: promoting a different node to primary is always a manual, deliberate action, not covered by this installation procedure (see §29).

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

PostgreSQL streaming replication flows from primary to secondary, but the secondary is the one that *initiates* the TCP connection to the primary (secondary to primary on TCP `5433`). The same direction applies to SSH/`rsync` (secondary to primary on TCP `22`). Keep this direction in mind in the firewall and SSH-trust phases below; it determines which node needs which inbound rule.

**Member Initial Configuration is performed on the primary only, once (Phase 18).** The secondary is never independently initialized as a second logical Security Server; it receives the shared identity through replication and a one-time bootstrap sync, not through its own registration.

## Checkpoints - where you genuinely need CamDX

The normal, successful installation path has exactly three planned CamDX checkpoints. Everything else below is self-contained.

- **Checkpoint A, before you start (Phase 0):** your [HA Deployment Profile](../high-availability-deployment-profile.md) is completed and CamDX has authorized this HA deployment (environment, member identity, Security Server Code, onboarding status).
- **Checkpoint B, normal PKI/registration (Phase 18, via [Initial Configuration](../initial-configuration.md)):** AUTH/SIGN CSR submission, certificate issuance, authentication-certificate registration approval, and subsystem registration approval. This is CamDX's normal onboarding process; HA does not add an exception to it.
- **Checkpoint C, acceptance (Phase 28):** CamDX central monitoring visibility, final registration confirmation, and production go-live authorization.

This runbook provides the PostgreSQL, SELinux, `firewalld`, SSH, `rsync`, systemd, and health-check mechanics directly. If a documented **STOP** condition occurs, additional troubleshooting or escalation may be required; see §30. Do not improvise around a **STOP** condition.

## 1. Before you start

- Two fresh RHEL 9 hosts (amd64 each), neither an existing Security Server.
- Root/sudo access on both.
- Your [HA Deployment Profile](../high-availability-deployment-profile.md), completed per Checkpoint A, including the `firewalld` zone, administrator CIDR, and backend data-plane source CIDRs (§5 of that document).
- The HA network ports open per [Network Requirements](../network-requirements.md) §8.
- A load balancer capable of Layer 4/TCP passthrough, administered by your own team.

## Phase 0 - Complete the HA Deployment Profile

Open the [HA Deployment Profile](../high-availability-deployment-profile.md). Fill in every CamDX-provided/CamDX-confirmed field (§1) and every member-owned infrastructure field (§2 and §5) you will need below.

**STOP** if any required field is unknown. Confirm CamDX-provided fields with CamDX (Checkpoint A) and resolve member-owned fields with your own network/infrastructure team before continuing.

Throughout this guide, `<PRIMARY_NODE>`, `<SECONDARY_NODE>`, `<PRIMARY_IP>`, `<SECONDARY_IP>`, and `<SECONDARY_SOURCE_CIDR>` refer to the values you just recorded. `<SECONDARY_SOURCE_CIDR>` is the secondary's replication/SSH source address as the primary actually observes it (HA Deployment Profile §2/§5); it is not always the same as `<SECONDARY_IP>` if NAT sits between the two nodes.

## Phase 1 - Provision and verify both clean RHEL 9 nodes

On **each** node, verify:

```bash
hostname -f
. /etc/os-release; echo "$ID $VERSION_ID"
timedatectl status
getenforce
ip route
```

- `$ID` is `rhel` and `$VERSION_ID` begins with `9` on **both** nodes.
- `hostname -f` returns the FQDN you recorded in the HA Deployment Profile.
- DNS resolves both nodes' FQDNs and the VIP's FQDN from each node.
- `timedatectl status` shows `System clock synchronized: yes`; both nodes use the same NTP source recorded in the profile.
- `getenforce` returns `Enforcing`. Do not disable it.
- `ip route` confirms each node can route to the other node's IP and to the load balancer.
- `firewalld` is enabled and running: `systemctl is-active firewalld` returns `active`.
- You have root/sudo on both hosts.
- Neither host has any prior X-Road package or `/etc/xroad` state (a genuinely clean host).

**STOP** if any check fails. Resolve it before continuing; do not work around a routing or DNS problem by hardcoding IPs where this guide expects a name, or vice versa.

## Phase 2 - Install CamDX Security Server and local Operational Monitoring on both nodes

Use the same validated procedure as a standalone deployment, on **each** clean node; see [RHEL Standalone Installation](./standalone-installation.md) §3-§5 for the full repository setup and install sequence:

```bash
sudo dnf install xroad-database-local xroad-securityserver
sudo xroad-add-admin-user camdx-systemadmin
```

**Install local Operational Monitoring now, as part of this installation phase, before any later stop barrier:**

```bash
sudo dnf install xroad-addon-opmonitoring
sudo systemctl restart xroad-opmonitor
sudo systemctl restart xroad-proxy
```

This matters because the package's own restart of `xroad-opmonitor`/`xroad-proxy` would otherwise undo a deliberate service-stop step if run afterward; installing it here, before Phase 3's stop barrier, avoids that conflict entirely. **Do not start the remaining X-Road services yet**, and **do not run Initial Configuration**. If you already started them while following the standalone guide's own flow, that is fine: Phase 3 below stops them again for the HA conversion.

Confirm the package installation itself is clean on each node:

```bash
rpm -qa --qf '%{name}\t%{version}-%{release}\n' 'xroad*' | sort
```

Every `xroad*` package should report the same `7.8.2-2.el9` version on both nodes.

## Phase 3 - Stop X-Road services for HA conversion

On **both** nodes, ensure the application-level X-Road services are stopped before changing anything under `/etc/xroad`:

```bash
sudo systemctl stop xroad-proxy xroad-proxy-ui-api xroad-confclient xroad-signer xroad-monitor xroad-addon-messagelog
```

Leave running: `xroad-base` (a one-shot unit; there is nothing to stop), the local PostgreSQL instance (you need it running to read from it in Phase 7), and `xroad-opmonitor` (already installed in Phase 2, independent of `serverconf`, left running on both nodes throughout this procedure).

Confirm the stop took effect:

```bash
systemctl is-active xroad-proxy xroad-proxy-ui-api xroad-confclient xroad-signer xroad-monitor xroad-addon-messagelog
```

Expect `inactive` for each.

## Phase 4 - Confirm both nodes resolve to the same PostgreSQL major version

On **each** node, confirm the actual running server version directly, with a live query. Do not rely on `psql -V`, which reports the client binary's version and may not prove what the running server actually is:

```bash
sudo -u postgres psql -p 5432 -Atc 'SHOW server_version;'
```

Record the major version number (the leading integer, for example `13` from `13.11`) from both nodes as `<PG_MAJOR>` in your HA Deployment Profile §3.

**STOP if the two nodes do not resolve to the same PostgreSQL major version.** Do not proceed with a mixed-major-version pair. Substitute your confirmed `<PG_MAJOR>` in every command below.

## Phase 5 - Create the database-replication CA and node certificates

Run this on a secure admin workstation, **not** on either cluster node.

```bash
mkdir -p ha-ca && cd ha-ca

# Certificate authority for this HA pair's serverconf replication only
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt -subj "/CN=<PRIMARY_NODE>-serverconf-ca"

# Primary node certificate
openssl genrsa -out server-primary.key 2048
openssl req -new -key server-primary.key -out server-primary.csr -subj "/CN=<PRIMARY_NODE>"
openssl x509 -req -in server-primary.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 -out server-primary.crt

# Secondary node certificate. The CN MUST match the PostgreSQL
# replication role name you create in Phase 6, since certificate-based
# authentication matches on this exact value.
openssl genrsa -out server-secondary.key 2048
openssl req -new -key server-secondary.key -out server-secondary.csr -subj "/CN=<secondary_replication_role>"
openssl x509 -req -in server-secondary.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 -out server-secondary.crt
```

Record `<secondary_replication_role>` in your HA Deployment Profile §3; you use it again in Phase 6 and Phase 8.

Each node uses the **same local filenames** for its own certificate/key, even though the certificates themselves are different per node:

```bash
# On the primary, copy ca.crt, and server-primary.crt/.key renamed to server.crt/server.key, into /etc/xroad/postgresql/:
sudo mkdir -p /etc/xroad/postgresql
sudo chown postgres:postgres /etc/xroad/postgresql/ca.crt /etc/xroad/postgresql/server.crt /etc/xroad/postgresql/server.key
sudo chmod 644 /etc/xroad/postgresql/ca.crt /etc/xroad/postgresql/server.crt
sudo chmod 600 /etc/xroad/postgresql/server.key

# On the secondary, copy ca.crt, and server-secondary.crt/.key renamed to server.crt/server.key, into /etc/xroad/postgresql/:
sudo mkdir -p /etc/xroad/postgresql
sudo chown postgres:postgres /etc/xroad/postgresql/ca.crt /etc/xroad/postgresql/server.crt /etc/xroad/postgresql/server.key
sudo chmod 644 /etc/xroad/postgresql/ca.crt /etc/xroad/postgresql/server.crt
sudo chmod 600 /etc/xroad/postgresql/server.key
```

Both nodes now have a file at `/etc/xroad/postgresql/server.crt` and `/etc/xroad/postgresql/server.key`, but the contents differ: each node's copy is its own node-specific certificate and key.

**SELinux diagnostic note, not a standard step:** if, later in this procedure, PostgreSQL fails to read a certificate or key under `/etc/xroad/postgresql` and `ausearch -m avc -ts recent` shows an AVC denial referencing that path, **STOP and capture the exact AVC denial text**. Do not invent your own `semanage fcontext` rule and do not disable SELinux enforcement. Provide the captured evidence to CamDX through the approved support channel before continuing; see [HA Troubleshooting](../troubleshooting/high-availability.md).

**CA private key lifecycle:** `ca.key` was generated only on this admin workstation. Once both nodes have their issued certificates, either move `ca.key` to your organization's approved secure key storage (if you expect to issue or replace node certificates later) or, if your organization's lifecycle plan is to replace the whole replication trust chain rather than reissue from this CA, you may retire it according to that plan. In either case, **do not leave `ca.key` on the admin workstation indefinitely, and never copy it to either Security Server node.**

## Phase 6 - Create the dedicated primary `serverconf` PostgreSQL instance

On the **primary** node, RHEL's PostgreSQL packaging does not provide a `pg_createcluster`-style helper for a second instance; copy the installed unit and initialize a second data directory directly:

```bash
sudo cp /lib/systemd/system/postgresql.service /etc/systemd/system/postgresql-serverconf.service
```

Edit `/etc/systemd/system/postgresql-serverconf.service` and override:

```properties
[Service]
...
Environment=PGPORT=5433
Environment=PGDATA=/var/lib/pgsql/serverconf
```

Initialize the new data directory as the `postgres` user:

```bash
sudo su postgres
cd /tmp
initdb --auth-local=peer --auth-host=scram-sha-256 --locale=en_US.UTF-8 --encoding=UTF8 -D /var/lib/pgsql/serverconf/
exit
```

Label the port for SELinux and open it in `firewalld`, scoped to the **secondary's** address (replication connects secondary to primary, so the primary is the one that needs an inbound allow rule):

```bash
sudo semanage port -a -t postgresql_port_t -p tcp 5433
sudo firewall-cmd --permanent --zone=<PRIMARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<SECONDARY_SOURCE_CIDR>" port port="5433" protocol="tcp" accept'
sudo firewall-cmd --reload
```

Enable and start the new instance:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now postgresql-serverconf
```

Edit `/var/lib/pgsql/serverconf/postgresql.conf` (RHEL's `initdb` places configuration inside the data directory itself, unlike Ubuntu's split `/etc/postgresql` layout):

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

Edit `/var/lib/pgsql/serverconf/pg_hba.conf`, adding:

```text
hostssl replication <secondary_replication_role> <SECONDARY_SOURCE_CIDR> cert
```

Create the replication role and the application role X-Road itself will use:

```bash
sudo -u postgres psql -p 5433 -c "CREATE ROLE <secondary_replication_role> WITH REPLICATION LOGIN;"

GENERATED_PW="$(openssl rand -base64 24)"
sudo -u postgres psql -p 5433 -c "CREATE ROLE serverconf WITH LOGIN PASSWORD '$GENERATED_PW';"
sudo -u postgres psql -p 5433 -c "CREATE DATABASE serverconf OWNER serverconf;"
printf 'serverconf role password: %s\n' "$GENERATED_PW"
unset GENERATED_PW
```

Copy the printed password immediately into your organization's secret storage. You need this exact value twice: once for the primary's `db.properties` in Phase 7, and again for the secondary's `db.properties` in Phase 10: the role is physically replicated, so both nodes must use the identical password. The replication role itself needs no password: `cert` authentication in `pg_hba.conf` matches on certificate CN.

Restart to apply the configuration changes:

```bash
sudo systemctl restart postgresql-serverconf
```

## Phase 7 - Move the primary `serverconf` into the dedicated instance

On the **primary** node, the default local instance (port `5432`, created by `xroad-database-local`) still holds the original `serverconf` and `messagelog` databases. Copy `serverconf` into the new dedicated instance:

```bash
sudo -u postgres pg_dump -p 5432 serverconf | sudo -u postgres psql -p 5433 serverconf
```

Repoint `/etc/xroad/db.properties` on the **primary** so X-Road's `serverconf` connection uses the new instance, leaving the `messagelog` entry untouched:

```ini
# Only the serverconf stanza changes. Leave messagelog pointed at port 5432.
serverconf.hibernate.connection.url = jdbc:postgresql://127.0.0.1:5433/serverconf
serverconf.hibernate.connection.username = serverconf
serverconf.hibernate.connection.password = <the password generated in Phase 6>
```

**Do not delete the original `serverconf` database on port 5432 yet.** Keep it until replication to the secondary is confirmed healthy (Phase 9) and you have completed Phase 28's acceptance checklist. `messagelog` stays on the node-local default instance permanently; it is never moved.

## Phase 8 - Seed the secondary `serverconf`

On the **secondary** node, repeat the unit setup from Phase 6 (copy the unit, override `PGPORT`/`PGDATA`, label the port), but **do not** run `initdb`: the data directory is populated from the primary's base backup instead. The secondary does not need an inbound `firewalld` rule for port `5433`; it only makes the outbound connection to the primary, which already has the matching rule from Phase 6.

```bash
sudo cp /lib/systemd/system/postgresql.service /etc/systemd/system/postgresql-serverconf.service
# Edit it with the same PGPORT=5433 / PGDATA=/var/lib/pgsql/serverconf overrides as Phase 6.
sudo semanage port -a -t postgresql_port_t -p tcp 5433
sudo systemctl daemon-reload
```

Create the (currently empty) data directory, verify the exact path before touching it, and ensure it is empty:

```bash
SERVERCONF_DATA_DIR="/var/lib/pgsql/serverconf"

case "$SERVERCONF_DATA_DIR" in
  */serverconf) ;;
  *) echo "STOP: path does not end in /serverconf - refusing to continue." >&2; exit 1 ;;
esac

sudo mkdir -p "$SERVERCONF_DATA_DIR"
sudo chown postgres:postgres "$SERVERCONF_DATA_DIR"
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
    -U <secondary_replication_role> \
    -D "$SERVERCONF_DATA_DIR" \
    -Fp -Xs -P --checkpoint=fast

sudo -u postgres touch "$SERVERCONF_DATA_DIR/standby.signal"
```

Edit `/var/lib/pgsql/serverconf/postgresql.conf` on the secondary:

```ini
listen_addresses = 'localhost'
hot_standby = on
hot_standby_feedback = on

primary_conninfo = 'host=<PRIMARY_IP> port=5433 user=<secondary_replication_role> sslmode=verify-ca sslcert=/etc/xroad/postgresql/server.crt sslkey=/etc/xroad/postgresql/server.key sslrootcert=/etc/xroad/postgresql/ca.crt'
```

Fix ownership (the base backup may have altered it) and start:

```bash
sudo chown -R postgres:postgres "$SERVERCONF_DATA_DIR"
sudo chmod 700 "$SERVERCONF_DATA_DIR"
sudo systemctl enable --now postgresql-serverconf
```

## Phase 9 - Verify PostgreSQL streaming replication

On the **primary**:

```bash
sudo -u postgres psql -p 5433 -c "select client_addr, state, sync_state from pg_stat_replication;"
```

Expect one row, `client_addr` matching the address you recorded as `<SECONDARY_SOURCE_CIDR>` (not necessarily the secondary's own configured private IP, if NAT is involved), `state` = `streaming`.

On the **secondary**:

```bash
sudo -u postgres psql -p 5433 -c "select pg_is_in_recovery();"
sudo -u postgres psql -p 5433 -c "select status, received_lsn, latest_end_lsn from pg_stat_wal_receiver;"
```

Expect `pg_is_in_recovery()` = `t`, and `pg_stat_wal_receiver.status` = `streaming`.

**STOP** if either side does not show streaming replication. Check `journalctl -u postgresql-serverconf` on both nodes for the specific connection or certificate error. If the error points to an SELinux AVC denial for a file under `/etc/xroad/postgresql`, follow the diagnostic note in Phase 5 rather than disabling SELinux.

## Phase 10 - Configure the secondary's `db.properties`

**This step is required and easy to miss: a fresh standalone installation does not leave the secondary already pointed at the replicated instance.** On the **secondary**, edit `/etc/xroad/db.properties` now, before any X-Road application service on the secondary is started:

```ini
# Only the serverconf stanza changes. Leave messagelog pointed at the
# node-local default instance (port 5432) - it is never moved.
serverconf.hibernate.connection.url = jdbc:postgresql://127.0.0.1:5433/serverconf
serverconf.hibernate.connection.username = serverconf
serverconf.hibernate.connection.password = <the same password generated on the primary in Phase 6>
```

The password must be the **identical** value used on the primary: the `serverconf` role and its password are part of the database state that PostgreSQL streaming replication physically carries to the secondary, so a different local password on the secondary will not authenticate.

Verify on both nodes before continuing:

```text
Primary:   serverconf -> 127.0.0.1:5433, messagelog -> 127.0.0.1:5432 (node-local)
Secondary: serverconf -> 127.0.0.1:5433, messagelog -> 127.0.0.1:5432 (node-local)
```

**Never synchronize `db.properties` with `rsync`.** It is excluded in both Phase 12 (scheduled) and Phase 19 (one-time bootstrap) precisely because each node's copy must independently point at its own local view of the replicated instance.

## Phase 11 - Configure SSH trust for configuration synchronization

On the **primary**, create the dedicated synchronization account. It needs a real shell (`/bin/bash`), because `rsync` over SSH works by having `sshd` execute the remote `rsync` command on the receiving end, and a `nologin` shell would break this. The account is still non-interactive/system-only in every other respect: it has no password, and its `authorized_keys` is owned and controlled by `root`, not by the account itself.

```bash
sudo useradd -r -m -g xroad -s /bin/bash xroad-slave
sudo install -d -m 0750 -o root -g xroad /home/xroad-slave/.ssh
sudo install -m 0640 -o root -g xroad /dev/null /home/xroad-slave/.ssh/authorized_keys
```

`authorized_keys` is owned by `root`, group `xroad` (the same group `xroad-slave`'s primary group membership gives it, used here only for read access, not as a separate `xroad-slave` group, which does not exist). The `xroad-slave` account itself cannot write to it. `sshd` can still read it to authenticate incoming connections.

Open SSH to the **secondary** only, using the recorded `<SECONDARY_SOURCE_CIDR>` (SSH connects secondary to primary, so the primary needs the inbound rule; do not substitute the secondary's raw private IP if NAT means the primary observes a different source address):

```bash
sudo firewall-cmd --permanent --zone=<PRIMARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<SECONDARY_SOURCE_CIDR>" port port="22" protocol="tcp" accept'
sudo firewall-cmd --reload
```

Allow `rsync` to run as a systemd-managed SSH client under SELinux, on the **secondary only**: the `rsync` client process runs there, not on the primary, so the primary does not need these booleans:

```bash
# On the secondary:
sudo setsebool -P rsync_client 1
sudo setsebool -P rsync_full_access 1
```

On the **secondary**, generate a key for the `xroad` system account, using a synchronization-specific key name. RHEL 9 FIPS-compatible environments use an ECDSA key rather than Ed25519:

```bash
sudo install -d -m 0700 -o xroad -g xroad /home/xroad/.ssh
sudo -u xroad ssh-keygen -t ecdsa -b 256 -f /home/xroad/.ssh/id_xroad_sync -N ""
sudo -u xroad cat /home/xroad/.ssh/id_xroad_sync.pub
```

As `root` on the primary, append that public key as one line to `/home/xroad-slave/.ssh/authorized_keys`.

**Verify the host key before trusting it; do not accept it merely because a connection succeeds.** Retrieve the primary's host key and compute its fingerprint:

```bash
# On the secondary:
ssh-keyscan -t ecdsa <PRIMARY_IP> > /tmp/primary-hostkey.pub
ssh-keygen -lf /tmp/primary-hostkey.pub -E sha256
```

Compare the printed `SHA256:...` fingerprint against your own trusted infrastructure record for `<PRIMARY_NODE>` (recorded in your HA Deployment Profile §5). **Only after the fingerprint matches**, install the verified key into the `xroad` account's own `known_hosts`:

```bash
sudo install -d -m 0700 -o xroad -g xroad /home/xroad/.ssh
sudo -u xroad sh -c 'cat /tmp/primary-hostkey.pub >> /home/xroad/.ssh/known_hosts'
rm -f /tmp/primary-hostkey.pub
```

Now test the connection. This should succeed with no host-key prompt, because the key is already verified and trusted:

```bash
sudo -u xroad ssh -i /home/xroad/.ssh/id_xroad_sync xroad-slave@<PRIMARY_IP> "echo connection-ok"
```

## Phase 12 - Configure and enable scheduled synchronization

On the **secondary**, create `/etc/systemd/system/xroad-sync.service`:

```ini
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
```

and `/etc/systemd/system/xroad-sync.timer`:

```ini
[Unit]
Description=Run CamDX X-Road configuration sync periodically

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=xroad-sync.service

[Install]
WantedBy=timers.target
```

The `Before=`/`WantedBy=xroad-proxy.service` pairing makes systemd run the sync before the dependent X-Road services at boot, rather than relying solely on the timer happening to fire first. Enable both units now; it is safe to do so before Initial Configuration exists on the primary, since there is nothing meaningful to sync yet and this periodic unit always excludes `/globalconf` (the one-time bootstrap sync in Phase 19 is a separate, manual command that does not exclude it):

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
sudo ausearch -m avc -ts recent
```

Expect both units `enabled`, the timer active, no SELinux denial, and after the manual run: `Result=success`, `ExecMainStatus=0`, `ActiveState=inactive`, `SubState=dead`. Do not rely on the shell exit status of `systemctl status` alone to confirm a successful run; `inactive`/`dead` is the normal resting state for this one-shot unit between runs, not a failure, and the `systemctl show` fields above are the unambiguous way to confirm the run itself actually succeeded. If a denial appears referencing `rsync` or SSH and the two booleans from Phase 11 are already set on the secondary, STOP and capture the exact AVC text for escalation through the approved CamDX support channel rather than loosening SELinux further on your own judgment.

## Phase 13 - Configure sync log rotation

On the **secondary**, create `/etc/logrotate.d/xroad-slave-sync`:

```text
/var/log/xroad/slave-sync.log {
    daily
    rotate 7
    missingok
    compress
    su xroad xroad
    nocreate
}
```

Confirm `/var/log/xroad/slave-sync.log` is writable by the `xroad`/`xroad` user/group that the `xroad-sync.service` unit (`User=xroad`, `Group=xroad`) runs as:

```bash
ls -l /var/log/xroad/slave-sync.log
```

## Phase 14 - Configure node roles

On the **primary**, `/etc/xroad/conf.d/node.ini`:

```ini
[node]
type=master
```

On the **secondary**, `/etc/xroad/conf.d/node.ini`:

```ini
[node]
type=slave
```

On both:

```bash
sudo chown xroad:xroad /etc/xroad/conf.d/node.ini
sudo chmod 640 /etc/xroad/conf.d/node.ini
```

`master` and `slave` are the literal, required X-Road configuration values; there is no `type=primary`/`type=secondary` syntax. This file is permanently excluded from `rsync` (Phase 12); it must never be synchronized between nodes.

## Phase 15 - Restrict secondary administration

On the **secondary**, for every existing Admin UI/API administrator account (including the one created during Phase 2's installation):

```bash
sudo gpasswd -d <admin-user> xroad-registration-officer
sudo gpasswd -d <admin-user> xroad-service-administrator
sudo gpasswd -d <admin-user> xroad-system-administrator
```

Retain `xroad-securityserver-observer` and `xroad-security-officer`; do not remove these.

Verify:

```bash
id <admin-user>
```

Expect the group list to include `xroad-securityserver-observer` and `xroad-security-officer`, and **not** the three removed groups.

## Phase 16 - Configure load-balancer behavior and the health check

On the **primary**, edit (do not overwrite) `/etc/xroad/conf.d/local.ini`. If it does not yet exist, create it with exactly this content; if it already has a `[message-log]` section, keep it and add the `[proxy]` section alongside it:

```ini
[message-log]
message-body-logging=false

[proxy]
server-support-clients-pooled-connections=false
health-check-interface=0.0.0.0
health-check-port=5588
```

This file is carried to the secondary by the one-time bootstrap sync (Phase 19) and the ongoing scheduled sync (Phase 12). `xroad-proxy` has not started yet on either node since Phase 3, so this takes effect on first start (Phase 17/20). If you ever edit `local.ini` again after services are running, restart `xroad-proxy`:

```bash
sudo systemctl restart xroad-proxy
```

Open the health-check port, scoped to your load-balancer health-check source CIDR(s) from the HA Deployment Profile, on **both** nodes, using each node's own zone. Run the primary's rule on the primary and the secondary's rule on the secondary; do not run both on the same node. If the profile records more than one source CIDR, add one rich rule per CIDR rather than inventing a single combined range:

```bash
# Primary:
sudo firewall-cmd --permanent --zone=<PRIMARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<LB_HEALTHCHECK_CIDR_1>" port port="5588" protocol="tcp" accept'
# Repeat with --add-rich-rule for each additional recorded health-check source CIDR (<LB_HEALTHCHECK_CIDR_2>, ...).
sudo firewall-cmd --reload
```

```bash
# Secondary:
sudo firewall-cmd --permanent --zone=<SECONDARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<LB_HEALTHCHECK_CIDR_1>" port port="5588" protocol="tcp" accept'
# Repeat with --add-rich-rule for each additional recorded health-check source CIDR (<LB_HEALTHCHECK_CIDR_2>, ...).
sudo firewall-cmd --reload
```

Also open the Admin UI port now, scoped to your administrator CIDR(s), on **both** nodes, using each node's own zone. The documented procedure uses each node's own Admin UI for setup and verification before Initial Configuration:

```bash
# Primary:
sudo firewall-cmd --permanent --zone=<PRIMARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<ADMIN_CIDR_1>" port port="4000" protocol="tcp" accept'
# Repeat with --add-rich-rule for each additional recorded administrator CIDR (<ADMIN_CIDR_2>, ...).
sudo firewall-cmd --reload
```

```bash
# Secondary:
sudo firewall-cmd --permanent --zone=<SECONDARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<ADMIN_CIDR_1>" port port="4000" protocol="tcp" accept'
# Repeat with --add-rich-rule for each additional recorded administrator CIDR (<ADMIN_CIDR_2>, ...).
sudo firewall-cmd --reload
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

Complete [Initial Configuration](../initial-configuration.md) on the **primary node only**: configuration anchor import, member/Security Server Code entry, software token PIN, timestamping service, AUTH/SIGN CSRs (Checkpoint B), certificate import, authentication-certificate registration, and subsystem registration.

**Use the HA load-balancer/VIP address as the Security Server's external address, not either node's own private hostname/IP.** Wherever Initial Configuration asks for the Security Server's DNS name/FQDN or external address (for example, the authentication-certificate CSR's CN/SAN, and the value submitted at registration), use the approved HA FQDN or external address recorded in your HA Deployment Profile. Do not register either backend node's own private/node FQDN as the logical Security Server address; consumers and providers reach this Security Server only through the load balancer, which performs Layer-4 TCP passthrough to whichever backend is healthy. Confirm the HA FQDN actually resolves to, and routes to, your load balancer/VIP before submitting the CSR.

**Do not independently initialize the secondary as a second logical Security Server.** Do not import the configuration anchor, create a software token, generate AUTH/SIGN keys, or attempt registration on the secondary at any point. The secondary receives this same identity through the bootstrap sync in the next phase, not through its own registration.

## Phase 19 - Perform the one-time initial bootstrap synchronization

Now that the primary has a real configuration, copy it to the secondary once, manually, **including** `/globalconf` (unlike the ongoing scheduled sync in Phase 12, which always excludes it; see the explanation below).

On the **secondary**:

```bash
sudo -u xroad rsync -e "ssh -i /home/xroad/.ssh/id_xroad_sync" -avz --delete \
  --exclude db.properties --exclude "/postgresql" --exclude "/conf.d/node.ini" --exclude "/gpghome" \
  xroad-slave@<PRIMARY_IP>:/etc/xroad/ /etc/xroad/
```

This bootstrap exclusion list is deliberately smaller than the ongoing scheduled sync's: it still excludes the four permanently node-local items (`db.properties`, the replication certificates under `/postgresql`, `node.ini`, and `/gpghome`), but it does **not** exclude `/globalconf`, because the secondary needs a working copy of the global configuration to start from. After this one-time copy, `xroad-confclient` running on the secondary (once started, Phase 20) independently fetches and maintains its own global configuration going forward. That is why the ongoing scheduled sync (Phase 12) permanently excludes `/globalconf`: continuing to overwrite it from the primary's copy would fight with the secondary's own `confclient` process.

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

`serverconf` (member/subsystem configuration) is already live on the secondary continuously, through PostgreSQL streaming replication. Confirm on the secondary's Admin UI (read-only) that the Clients page shows the same member/subsystem you configured on the primary.

Confirm the global configuration bootstrapped correctly and that `xroad-confclient` is now maintaining it independently on the secondary:

```bash
sudo -u xroad ls -la /etc/xroad/globalconf
```

Expect recent, valid-looking global configuration content, refreshing on its own over time.

Confirm the AUTH and SIGN certificate/key files under `/etc/xroad/signer` match the primary's.

The software token shows as present but likely **not yet logged in** on the secondary. **This must be done explicitly.** Using the retained `xroad-security-officer` role, log in via **Keys and Certificates, Token, Login**, entering the same PIN used on the primary. Do this again after any later token-state change on the primary, or after a secondary reboot.

Do not configure unattended plaintext PIN autologin (`xroad-autologin`) as the standard production path for the secondary; manual login by a security officer after each relevant event is the default here. If your organization has a specific operational reason to use autologin and wants CamDX's input on it, that is a separate decision to raise with CamDX.

## Phase 22 - Verify the health endpoint on each node

On **each** node:

```bash
curl -i http://127.0.0.1:5588/
```

Expect `HTTP/1.1 200 OK`. From the load balancer's own health-check source (already permitted through `firewalld` in Phase 16):

```bash
curl -i http://<NODE_IP>:5588/
```

`HTTP 500` means a failed check (the response body names the specific failure); `HTTP 503` means the node has been deliberately placed into maintenance mode (see Phase 26). Resolve a `500` before continuing.

## Phase 23 - Configure the external load balancer

Your own load-balancer administrator implements this using whichever product you selected in your HA Deployment Profile. This guide states the required behavior precisely rather than any one vendor's syntax, and does not require CamDX support:

- Layer 4 / TCP load balancing with TLS passthrough. The load balancer must not terminate TLS; the Security Server does that. This does not eliminate the possibility of some in-flight message loss on a node failure; it is a load-balancing architecture, not a zero-loss fault-tolerance guarantee.
- Health check: `HTTP GET` to port `5588` on each backend, expecting `200`. A backend must be removed from rotation on any other response.
- Forward TCP `5500` and `5577` to both nodes, per [Network Requirements](../network-requirements.md) §8, scoped to the actual backend data-plane source CIDR(s) recorded in your HA Deployment Profile §5. Do not assume the load balancer preserves the original client source address; use the CIDR(s) actually seen at each backend after your load balancer's own NAT/source behavior. The primary and secondary may see different source CIDRs; the profile records them as two explicit, separately numbered fields (`<PRIMARY_BACKEND_DATA_PLANE_CIDR_1>`, ...and `<SECONDARY_BACKEND_DATA_PLANE_CIDR_1>`, ...) even if their values turn out identical, and add one rich rule per CIDR if there are several:

```bash
# Primary (use the source CIDR recorded for the primary's own backend):
sudo firewall-cmd --permanent --zone=<PRIMARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<PRIMARY_BACKEND_DATA_PLANE_CIDR_1>" port port="5500" protocol="tcp" accept'
sudo firewall-cmd --permanent --zone=<PRIMARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<PRIMARY_BACKEND_DATA_PLANE_CIDR_1>" port port="5577" protocol="tcp" accept'
# Repeat for each additional recorded CIDR (<PRIMARY_BACKEND_DATA_PLANE_CIDR_2>, ...), and for the client-proxy port if used.
sudo firewall-cmd --reload
```

```bash
# Secondary (use the source CIDR recorded for the secondary's own backend):
sudo firewall-cmd --permanent --zone=<SECONDARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<SECONDARY_BACKEND_DATA_PLANE_CIDR_1>" port port="5500" protocol="tcp" accept'
sudo firewall-cmd --permanent --zone=<SECONDARY_ZONE> --add-rich-rule='rule family="ipv4" source address="<SECONDARY_BACKEND_DATA_PLANE_CIDR_1>" port port="5577" protocol="tcp" accept'
# Repeat for each additional recorded CIDR (<SECONDARY_BACKEND_DATA_PLANE_CIDR_2>, ...), and for the client-proxy port if used.
sudo firewall-cmd --reload
```

- Forward your deployment's client-proxy port to both nodes, if consumer information systems reach this Security Server through the VIP, using the same explicit per-node CIDR-scoping discipline (`<PRIMARY_BACKEND_DATA_PLANE_CIDR_1>` on `<PRIMARY_ZONE>`, `<SECONDARY_BACKEND_DATA_PLANE_CIDR_1>` on `<SECONDARY_ZONE>`, one rich rule per recorded CIDR).
- Do not load-balance TCP `4000` (Admin UI) as if both nodes were equally writable; the secondary's UI is read-only. Point administrators at the primary directly, or make the VIP's `4000` forwarding explicit about which node it reaches.
- Support connection draining, so a node you place into maintenance mode (Phase 26) finishes in-flight connections rather than dropping them abruptly.

## Phase 24 - Verify the load balancer

- Query each backend directly (bypassing the VIP) and confirm each independently reports healthy on `5500`, `5577`, the client-proxy port, and the `5588` health check.
- Query the VIP and confirm it resolves and connects, and that traffic actually reaches both backends.
- Confirm the load balancer's own status page or equivalent shows both nodes healthy and in rotation.

## Phase 25 - Real API validation

Perform one known-good, real CamDX API request through the VIP. Record:

- The request result (success/failure, and the response).
- Which backend handled it, if observable.
- That the request appears in `messagelog` on the node that handled it.
- That it appears in Operational Monitoring.
- That CamDX/peer visibility (central monitoring) shows the activity, if observable.

## Phase 26 - Backend maintenance test

Place the primary into maintenance mode:

```bash
curl -i "http://localhost:5566/maintenance?targetState=true"
```

Confirm: the primary's health check (Phase 22) now returns `503`; the load balancer removes it from rotation; a repeat of the Phase 25 real API request still succeeds, now served by the secondary.

Disable maintenance mode:

```bash
curl -i "http://localhost:5566/maintenance?targetState=false"
```

Repeat the same test on the secondary.

**Do not promote or demote the PostgreSQL `serverconf` primary during this test.**

## Phase 27 - Service restart and OS reboot recovery

Perform these tests **one node at a time**, so the other node remains available throughout. **Do not perform automatic or manual primary promotion during this phase.**

### Service restart recovery

For **each** node in turn:

1. Remove that node from load-balancer rotation (place it in maintenance mode, Phase 26, or remove it at the load balancer).
2. Restart the X-Road application services on that node:
   ```bash
   sudo systemctl restart xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog
   ```
3. Verify:
   - services return healthy: `systemctl is-active xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog xroad-opmonitor` all `active`;
   - `serverconf` remains reachable: `sudo -u postgres pg_isready -p 5433`;
   - no new SELinux denial: `sudo ausearch -m avc -ts recent`;
   - node role is still correct: `cat /etc/xroad/conf.d/node.ini`;
   - `db.properties` still points `serverconf` at `127.0.0.1:5433` (Phase 7/Phase 10);
   - on the secondary specifically, `xroad-sync.timer`/`.service` remain healthy (Phase 12);
   - global configuration is valid: `ls -la /etc/xroad/globalconf`;
   - local Operational Monitoring is healthy: `systemctl is-active xroad-opmonitor`;
   - the health endpoint returns `200` once token state is confirmed valid (re-log the token in per Phase 21 if needed).
4. Return the node to load-balancer rotation.
5. Repeat a known-good real API request through the VIP (as in Phase 25).

### Full OS reboot recovery

Test the **secondary first, then the primary**.

For **each** node in turn:

1. Remove that node from load-balancer rotation.
2. Reboot the node's operating system.
3. After boot, verify:
   - the dedicated `serverconf` PostgreSQL instance is active;
   - PostgreSQL streaming replication is healthy (repeat the Phase 9 checks);
   - no SELinux denial resulted from the boot/sync cycle: `sudo ausearch -m avc -ts recent`;
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
5. Return the node to load-balancer rotation.
6. Perform a known-good real API request through the VIP.
7. Confirm the request succeeds while the other node remains available throughout.

Only after both the service-restart and OS-reboot recovery tests pass on both nodes may you proceed to Phase 28's acceptance checklist.

## Phase 28 - Acceptance

Before handing this deployment over or declaring it production-ready, confirm every item below, and complete Checkpoint C with CamDX:

- PostgreSQL streaming replication healthy (Phase 9 checks, re-run), and both nodes still confirmed on the same PostgreSQL major version.
- Secondary `db.properties` confirmed pointed at `127.0.0.1:5433` for `serverconf` (Phase 10).
- On the secondary, scheduled `rsync` is healthy (`systemctl status xroad-sync.timer` active, last run successful) and enabled to survive a reboot; `xroad-sync.service`/`.timer` do not exist on the primary.
- No SELinux denials on either node (`ausearch -m avc -ts recent`).
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
- Operational Monitoring healthy on both nodes (local topology, the standard path this runbook covers; see [Network Requirements](../network-requirements.md) §7 if your deployment instead uses a separate, approved remote/external topology).
- `messagelog` healthy on both nodes.
- Backup responsibilities recorded (see [Deployment Model Selector](../deployment-models.md) §1).
- CamDX central monitoring visibility confirmed, final registration/onboarding status confirmed, and production go-live authorized (Checkpoint C).

Only after every item above is confirmed, and Checkpoint C is complete, is this HA deployment ready for production traffic.

## 29. Failover and primary promotion

There is no automatic failover. If the primary becomes unavailable, the secondary continues serving already-replicated configuration and can continue processing message traffic that does not require a configuration change, but it does not promote itself. Promoting the secondary to primary (changing its `node.ini`, reversing the PostgreSQL replication direction, and re-pointing the former primary as a new secondary once it returns) is a deliberate operational decision with its own procedure, not covered by this installation guide. If you need to plan for this scenario, treat it as a separate disaster-recovery runbook, raised with CamDX; do not improvise a promotion from the steps above.

## 30. If something goes wrong

See [HA Troubleshooting](../troubleshooting/high-availability.md) for the specific symptoms this procedure can produce, and the [Troubleshooting index](../troubleshooting/README.md) for everything else. Preserve the exact error text, the phase you were on, and the output of the relevant verification command before contacting CamDX. For an SELinux-related stop, preserve the exact `ausearch -m avc` output.

## 31. References

- [HA Deployment Profile](../high-availability-deployment-profile.md), [Network Requirements](../network-requirements.md) §8, [Deployment Model Selector](../deployment-models.md).
- [RHEL Standalone Installation](./standalone-installation.md), [Initial Configuration](../initial-configuration.md).
- [Ubuntu HA Installation](../ubuntu/high-availability-installation.md) for the equivalent Ubuntu procedure.
- [HA Troubleshooting](../troubleshooting/high-availability.md).
- Upstream X-Road External Load Balancer Installation Guide (`nordic-institute/X-Road`), the architecture and mechanism this procedure is adapted from, including its RHEL 8/9 PostgreSQL initialization and SELinux sections.
