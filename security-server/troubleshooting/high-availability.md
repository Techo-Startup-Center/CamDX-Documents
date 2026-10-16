# CamDX Security Server - HA Troubleshooting

Symptoms specific to a replicated native HA pair ([Ubuntu HA](../ubuntu/high-availability-installation.md), [RHEL HA](../rhel/high-availability-installation.md)). For anything not listed here, see the [Troubleshooting index](./README.md).

Before changing anything, identify which node (primary or secondary) is affected, and which phase of the installation guide you were on or are operating after. No step below performs a destructive database action, an automatic promotion, or a blanket SELinux/firewall disable; where a repair requires one of those, this document says to stop and escalate instead.

## PostgreSQL secondary not streaming / `pg_stat_replication` empty

**Check:** on the primary, `sudo -u postgres psql -p 5433 -c "select * from pg_stat_replication;"`. On the secondary, `sudo -u postgres psql -p 5433 -c "select pg_is_in_recovery();"` and the PostgreSQL log for the `serverconf` instance (`/var/log/postgresql/postgresql-<PG_MAJOR>-serverconf.log` on Ubuntu, `journalctl -u postgresql-serverconf` on RHEL).

**Expected result:** one row in `pg_stat_replication` with `state = streaming`; `pg_is_in_recovery()` returns `t` on the secondary.

**Safe remediation:** confirm `primary_conninfo` on the secondary points at the correct `<PRIMARY_IP>` and port, and references `/etc/xroad/postgresql/server.crt`/`server.key`/`ca.crt` (the local filenames are identical on both nodes; only the content differs); confirm the secondary's certificate files exist and are readable by `postgres` (`ls -l /etc/xroad/postgresql/`); confirm `pg_hba.conf` on the primary has the exact `hostssl replication <role> <SECONDARY_SOURCE_CIDR> cert` line, using the recorded source CIDR (HA Deployment Profile §2), not necessarily the secondary's raw private IP; restart the secondary's `serverconf` instance after any configuration fix.

**When to STOP:** if the log shows an authentication or certificate error you cannot resolve from the installation guide's Phase 5/6/8 steps, or if you are tempted to recreate the replication role with a password-based method instead of fixing the certificate: do not improvise an alternate authentication method; confirm the certificate CN/role name match exactly instead.

## `pg_basebackup` TLS failure

**Check:** the exact error `pg_basebackup` printed when run in Phase 8. Confirm the command actually set `PGSSLMODE=verify-ca`, `PGSSLROOTCERT`, `PGSSLCERT`, and `PGSSLKEY` as documented; a plain `pg_basebackup` without these environment variables will fail against the primary's certificate-only `hostssl` rule, and does not fall back to a password.

**Expected result:** a clean base backup with no TLS/certificate error.

**Safe remediation:** confirm the secondary's `PGSSLCERT`/`PGSSLKEY`/`PGSSLROOTCERT` paths in the command resolve to `/etc/xroad/postgresql/server.crt`, `server.key`, and `ca.crt`; confirm file permissions (`600` on the key, `644` on the certs, owned by `postgres`); confirm the certificate's CN matches the PostgreSQL replication role actually created on the primary (Phase 6); confirm the primary's `pg_hba.conf` has the matching `hostssl replication` line; confirm the network path to the primary's TCP `5433` is open from the secondary.

**When to STOP:** if the error is an SELinux AVC denial on RHEL (see the dedicated RHEL SELinux entry below): do not disable SELinux to get past it.

## Certificate CN / replication-user mismatch

**Check:** compare the CN in the secondary's client certificate (`openssl x509 -in /etc/xroad/postgresql/server.crt -noout -subject`, run on the secondary) against the role name in the primary's `pg_hba.conf` `hostssl replication` line and the role actually created in Phase 6.

**Expected result:** the CN and the role name are character-for-character identical.

**Safe remediation:** if they differ, either regenerate the certificate with the correct CN (Phase 5) or rename the PostgreSQL role to match, consistently on both ends. Pick one side to be authoritative and make the other match it; do not create a second role as a workaround.

**When to STOP:** if you are unsure which of several previously created roles is the one actually referenced in `pg_hba.conf` and `primary_conninfo`, confirm both files directly rather than guessing.

## Secondary cannot SSH to primary

**Check:** `sudo -u xroad ssh -i /home/xroad/.ssh/id_xroad_sync xroad-slave@<PRIMARY_IP> "echo connection-ok"` from the secondary, and `/home/xroad-slave/.ssh/authorized_keys` on the primary.

**Expected result:** `connection-ok` printed, no password prompt, no host-key prompt (the host key should already be trusted via the verified `known_hosts` entry from Phase 11).

**Safe remediation:** confirm the secondary's public key is present, on one line, in the primary's `authorized_keys`; confirm `authorized_keys` is owned by `root`, group `xroad` (not a separate `xroad-slave` group, which does not exist), mode `0640` (the `xroad-slave` account itself must not be able to write to it); confirm the `xroad-slave` account's shell is `/bin/bash`, not a `nologin` shell, since `rsync` over SSH requires `sshd` to execute the remote `rsync` command, which a `nologin` shell would block; re-verify the primary's host-key fingerprint (`ssh-keygen -lf <keyfile> -E sha256`) against your trusted record before re-adding it to `known_hosts` if it changed for a legitimate reason (for example, the primary was rebuilt).

**When to STOP:** never accept a host-key prompt you cannot independently verify merely to make the error go away.

## `rsync` service fails / `xroad-sync.timer` not running / files not propagating

**Check:** `systemctl is-enabled xroad-sync.service xroad-sync.timer`; `systemctl list-timers xroad-sync.timer`; `systemctl show xroad-sync.service -p Result -p ExecMainStatus -p ActiveState -p SubState` on the secondary; the log at `/var/log/xroad/slave-sync.log`.

**Expected result:** both units `enabled`; the timer `active`; the `systemctl show` output reports `Result=success`, `ExecMainStatus=0`, `ActiveState=inactive`, `SubState=dead` after the last run. Do not rely on the shell exit status of `systemctl status` alone; `inactive`/`dead` is the normal resting state for a successful one-shot unit between runs, not a failure.

**Safe remediation:** run the service manually (`sudo systemctl start xroad-sync.service`) and read the log for the specific `rsync`/SSH error; confirm the unit file's `ExecStart` references the correct SSH identity file (`/home/xroad/.ssh/id_xroad_sync`) and the current validated exclusion list; confirm the `Before=xroad-proxy.service` (and the other `Before=`/`WantedBy=` lines) are present so the sync runs ahead of the X-Road services at boot, not only when the one-minute timer happens to fire first; confirm SSH trust (above) still works independently of the timer.

**When to STOP:** on RHEL, if the log or `ausearch -m avc -ts recent` shows an SELinux denial for `rsync` or SSH, see the dedicated RHEL SELinux entry below rather than disabling SELinux.

## `node.ini` accidentally synchronized / wrong node role

**Check:** `cat /etc/xroad/conf.d/node.ini` on both nodes.

**Expected result:** `type=master` on the primary, `type=slave` on the secondary, never the same value on both.

**Safe remediation:** confirm the `rsync`/`xroad-sync.service` exclusion list includes `--exclude "/conf.d/node.ini"` exactly as documented; if it was already synchronized incorrectly, manually correct `node.ini` on the affected node and restart `xroad-confclient`/`xroad-signer`/`xroad-proxy` on that node, then re-check immediately after the next sync cycle to confirm the exclusion is actually working.

**When to STOP:** if both nodes show `type=master` (or both `type=slave`) and you are not certain which one is actually serving as the registered primary, do not guess; confirm against `serverconf`'s actual write/replication direction (above) before correcting either file.

## Secondary's `db.properties` still points at the wrong database

**Check:** `grep serverconf /etc/xroad/db.properties` on the secondary.

**Expected result:** `serverconf.hibernate.connection.url` points at `127.0.0.1:5433`, not `127.0.0.1:5432`. A fresh standalone installation does not set this automatically; it is a required, explicit step (installation guide Phase 10), easy to miss.

**Safe remediation:** edit `/etc/xroad/db.properties` on the secondary directly (it is excluded from `rsync`, so this is always a manual, node-local edit) and set the `serverconf` URL/username/password to match the primary's dedicated instance exactly, including the identical password: the `serverconf` role's password is physically replicated from the primary, so a locally-chosen different password will not authenticate. Leave the `messagelog` stanza untouched; it stays node-local permanently.

**When to STOP:** never attempt to "fix" this by synchronizing `db.properties` with `rsync`; each node's copy must independently point at its own local view of the replicated instance.

## Secondary token inactive after `keyconf`/signer sync

**Check:** the secondary's Admin UI, Keys and Certificates, Token status.

**Expected result:** eventually `active`, after a security officer logs in with the same PIN used on the primary.

**Safe remediation:** log in via **Keys and Certificates, Token, Login** on the secondary using the retained `xroad-security-officer` role, per [Initial Configuration](../initial-configuration.md) §14. This is expected manual behavior after every sync that changes token state, or after a secondary reboot; not a fault to engineer around with autologin.

**When to STOP:** if the PIN that worked on the primary is rejected on the secondary, do not repeatedly guess the PIN; confirm the signer/`keyconf` file state actually propagated (compare file listings/timestamps per the installation guide's bootstrap/scheduled sync phases) before assuming the PIN itself is wrong.

## Secondary has no (or a stale) global configuration

**Check:** `ls -la /etc/xroad/globalconf` on the secondary, and whether its timestamps advance over time.

**Expected result:** valid global configuration present after the one-time bootstrap synchronization (installation guide, the phase immediately after primary Initial Configuration), and independently refreshing afterward via the secondary's own `xroad-confclient` process.

**Safe remediation:** confirm the **one-time bootstrap** `rsync` (run manually, once, after Initial Configuration on the primary) did not exclude `/globalconf`. This is different from the **ongoing scheduled** `xroad-sync.service`, which always excludes `/globalconf` by design, so that it does not fight with the secondary's own `confclient`. If the bootstrap step was skipped or run with the wrong exclusion list, re-run it manually with the bootstrap exclusion set (excluding only `db.properties`, `/postgresql`, `/conf.d/node.ini`, and `/gpghome`, not `/globalconf`).

**When to STOP:** never tell the secondary to independently import the CamDX configuration anchor as a way to "fix" this; that would initialize it as a separate logical Security Server, which this architecture does not use.

## Health endpoint returns `500`

**Check:** `curl -i http://127.0.0.1:5588/` on the affected node; the response body names the specific failed check (token/login, OCSP, `serverconf` reachability, or global configuration validity).

**Expected result:** `200`.

**Safe remediation:** resolve the specific failure named in the response body using the relevant section of this document or the [Error Reference](./error-reference.md): for example, log the token in if that is the named failure, or resolve the `serverconf` connectivity issue described above if that is.

**When to STOP:** if the response body does not clearly identify one of the four known checks, capture the full response and escalate with that text rather than guessing at the cause.

## Health endpoint returns `503`

**Check:** `curl -i http://127.0.0.1:5588/`; the response body says `Health check interface is in maintenance mode`.

**Expected result:** this is expected and correct while the node is deliberately in maintenance mode (installation guide's maintenance test, or any time you have intentionally placed it there).

**Safe remediation:** if you did not intend this node to be in maintenance mode, disable it: `curl -i "http://localhost:5566/maintenance?targetState=false"`. Maintenance mode also resets automatically on the next `xroad-proxy` restart.

**When to STOP:** not applicable; this is a normal, reversible state.

## Load balancer leaves an unhealthy backend active

**Check:** the load balancer's own backend health status, compared against each node's own `curl -i http://127.0.0.1:5588/` result.

**Expected result:** the load balancer's view matches each node's actual health state.

**Safe remediation:** confirm the load balancer's health-check configuration actually targets port `5588` over plain HTTP (not HTTPS), with a polling interval compatible with the health check's own caching (a successful result is cached 2 seconds, a failed one 30 seconds, token-login state 300 seconds): a check polling much slower than 30 seconds will be slow to detect a real failure. This is your own load-balancer configuration; CamDX does not operate it.

**When to STOP:** not applicable to CamDX escalation; this is your load-balancer administrator's own configuration to correct.

## API works directly on a node but fails through the VIP

**Check:** repeat the same real API request directly against each node's own address, then through the VIP.

**Expected result:** identical success on both paths.

**Safe remediation:** if direct access succeeds but the VIP fails, the problem is in the load balancer or network path, not the Security Server: confirm Layer 4/TCP passthrough is actually configured (no TLS termination at the load balancer), confirm the relevant ports are forwarded to both backends using the actual observed backend source CIDR(s), and confirm the VIP's DNS/routing is correct and matches the address registered with CamDX at Initial Configuration.

**When to STOP:** if direct node access also fails, this is not an HA/load-balancer problem; see [Connectivity Troubleshooting](./connectivity.md) instead.

## Secondary configuration differs from primary

**Check:** compare `serverconf`-backed state (Clients, services) via each node's Admin UI, and compare `/etc/xroad/signer` file listings on both nodes.

**Expected result:** `serverconf` state matches continuously (streaming replication); signer/token state matches after the next sync cycle.

**Safe remediation:** if `serverconf` state differs, check PostgreSQL streaming replication health (above) first, since a lagging or broken replication connection is the most likely cause. If only signer/token state differs, check the sync timer (above).

**When to STOP:** never make a manual, one-off edit to the secondary's `serverconf`-backed configuration to "match" the primary. All configuration changes originate on the primary only, per [Initial Configuration](../initial-configuration.md) §14.

## RHEL: SELinux AVC denial

**Check:** `sudo ausearch -m avc -ts recent` on the affected node.

**Expected result:** no denials, during normal operation, replication, or sync activity.

**Safe remediation:** if the denial references the two documented booleans' own scope (`rsync_client`, `rsync_full_access`) and they are not yet set on the **secondary** (the node that actually runs the `rsync` client), set them there. These booleans are not needed on the primary.

**When to STOP:** if the denial references a path under `/etc/xroad/postgresql` (a certificate or key file PostgreSQL cannot read), **STOP and capture the exact `ausearch` output**. Do not invent your own `semanage fcontext` rule and do not run `setenforce 0`, even temporarily. Provide the captured evidence to CamDX through the approved support channel before continuing.

## RHEL: `firewalld` blocking `22`/`5433`/`5588`/`4000`/`5500`/`5577`

**Check:** `sudo firewall-cmd --zone=<ZONE> --list-rich-rules` on the affected node, compared against the HA Deployment Profile §5 fields and the installation guide's firewall commands.

**Expected result:** confirm the direction matches how each protocol actually connects:

| Port | Who connects to whom | Rule belongs on |
|---|---|---|
| `22` (SSH/`rsync`) | Secondary connects to primary | Primary only, source = `<SECONDARY_SOURCE_CIDR>` |
| `5433` (replication) | Secondary connects to primary | Primary only, source = `<SECONDARY_SOURCE_CIDR>` |
| `4000` (Admin UI) | Administrator connects to each node | Both nodes, source = administrator CIDR(s) |
| `5588` (health check) | Load balancer connects to each node | Both nodes, source = health-check CIDR(s) |
| `5500`/`5577`/client-proxy | Load balancer connects to each node | Both nodes, source = backend data-plane CIDR(s) actually observed |

**Safe remediation:** add the missing rich rule exactly as shown in the relevant installation-guide phase, scoped to the correct source address(es) from your HA Deployment Profile §5, one rich rule per distinct source CIDR, not a single combined range and not a bare `--add-port` across an entire zone, then `firewall-cmd --reload`. A secondary-side inbound rule for `5433` is never required; only the primary accepts that connection.

**When to STOP:** if you are tempted to open a port to the whole zone "to get past" a connectivity problem, don't; narrow the source address instead, and re-test.

## References

- [Ubuntu HA Installation](../ubuntu/high-availability-installation.md), [RHEL HA Installation](../rhel/high-availability-installation.md).
- [HA Deployment Profile](../high-availability-deployment-profile.md), [Network Requirements](../network-requirements.md) §8, [Initial Configuration](../initial-configuration.md) §14.
- [Connectivity Troubleshooting](./connectivity.md), [Error Reference](./error-reference.md).
