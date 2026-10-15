# CamDX Security Server - RHEL High Availability Architecture and Deployment Guidance

Existing CamDX HA deployments remain supported. For a new HA deployment, an upgrade of an existing HA deployment, or a topology change, coordinate with CamDX before implementation.

This document describes the RHEL-specific operational differences from the shared HA architecture. It is not authorization to deploy or modify an HA pair independently; exact configuration values for your deployment are confirmed with CamDX during HA deployment planning.

## 1. Shared HA architecture

CamDX documents the same replicated primary/secondary, external-load-balancer HA architecture for both Ubuntu and RHEL, with OS-specific package-manager, service, and security-subsystem commands. See [Ubuntu HA](../ubuntu/high-availability-installation.md) for the full architecture: the logical-pair model, `serverconf` streaming replication, the state-replication-scope table, `node.ini` semantics, external load balancer requirements, the health-check service, failover/promotion, backup/recovery responsibilities, and Operational Monitoring. All of that applies identically on RHEL 9; this document covers only the RHEL-specific differences below.

## 2. RHEL prerequisites

RHEL 9 host; SELinux Enforcing (the supported baseline, not disabled); `firewalld` enabled; EPEL for the one confirmed dependency (`crudini`); see [RHEL Standalone Installation](./standalone-installation.md).

## 3. PostgreSQL considerations

As on Ubuntu, the CamDX RHEL package does not pin a PostgreSQL major version; `xroad-database-local` and `xroad-database-remote` each declare only a generic, unversioned dependency (`postgresql-server`/`postgresql-contrib`, or plain `postgresql`). The resolved version depends on RHEL 9's own configured repositories (the AppStream default, or an alternate PGDG/module stream). Confirm the resolved version after installation (`rpm -q postgresql-server`, or `dnf module list postgresql` if a modular stream applies), and confirm the exact value with CamDX during HA deployment planning.

RHEL 8/9 initializes the dedicated `serverconf` PostgreSQL instance differently from the older RHEL 7 pattern. Copy the installed service unit and override its port/data directory, rather than using `postgresql-setup --initdb --unit ...` (that flag combination is RHEL 7-specific):

```bash
cp /lib/systemd/system/postgresql.service /etc/systemd/system/postgresql-serverconf.service
```

Edit `/etc/systemd/system/postgresql-serverconf.service` and override:
```properties
[Service]
...
Environment=PGPORT=5433
Environment=PGDATA=/var/lib/pgsql/serverconf
```

Initialize the dedicated data directory as the `postgres` user, using the `initdb` binary matching the installed PostgreSQL major version:
```bash
sudo su postgres
cd /tmp
initdb --auth-local=peer --auth-host=scram-sha-256 --locale=en_US.UTF-8 --encoding=UTF8 -D /var/lib/pgsql/serverconf/
exit
```

If PostgreSQL was not installed with the default configuration (for example, a PGDG-style versioned package), the data directory and `initdb` binary path differ accordingly (for example `/usr/pgsql-13/bin/initdb -D /var/lib/pgsql/13/serverconf/`). Confirm which convention applies on your host with CamDX before relying on an exact path in your own runbook.

Then, on either path:
```bash
semanage port -a -t postgresql_port_t -p tcp 5433
systemctl enable postgresql-serverconf
```

## 4. SELinux

Do not disable SELinux (`setenforce 0` / `SELINUX=disabled`) to make HA replication work. Use the narrow, documented exceptions instead:

- `semanage port -a -t postgresql_port_t -p tcp 5433`: labels the dedicated `serverconf` replication port so PostgreSQL may bind it under SELinux, without a blanket policy change.
- `setsebool -P rsync_client 1` and `setsebool -P rsync_full_access 1`: permits the `rsync`+`ssh` configuration-sync mechanism to run as a systemd-managed client. If other services on the host are customized, an additional policy update may be required.
- Additional SELinux file-context labeling under `/etc/xroad/postgresql` (for example `semanage fcontext` plus `restorecon`) may be required for some CamDX deployments. This is CamDX-specific rather than part of the upstream RHEL 8/9 HA guidance. Confirm with CamDX before applying any additional fcontext rule.

After any replication or sync test, confirm there is no SELinux denial in the audit log: `ausearch -m avc -ts recent`. Do not publish or rely on a blanket `setenforce 0`, including as a temporary troubleshooting step.

## 5. firewalld

Use narrow, peer-scoped rules rather than opening an entire zone:

- The dedicated `serverconf` replication port (historically `5433`) should be open only between the primary and secondary nodes, scoped to the specific peer address with a rich rule or dedicated zone where your network segmentation allows it, not opened on the whole `public` zone.
- SSH (`tcp/22`) between the nodes, for the `rsync`+`ssh` configuration-propagation mechanism, scoped the same way.
- The load-balancer-facing ports (`5500`/`5577`, and your deployment's consumer-information-system client ports), per [Network Requirements](../network-requirements.md), are legitimately open more broadly, to the load balancer/authorized peer network.

Do not publish or execute a blanket `firewall-cmd --add-port=.../tcp --permanent` across an entire zone as a shortcut; confirm your exact rule set with CamDX during HA deployment planning.

## 6. Verification and operational checks

- `rpm -q postgresql-server` (or the module-stream equivalent) confirms the resolved PostgreSQL version.
- `systemctl status postgresql-serverconf` confirms the dedicated replication instance is running.
- `ausearch -m avc -ts recent` confirms no SELinux denial occurred during replication or sync activity.
- `firewall-cmd --zone=<zone> --list-rich-rules` confirms the firewall rules actually in effect match your intended peer scoping.
- The health-check (`5588`), failover, and Operational Monitoring checks described in the [Ubuntu HA](../ubuntu/high-availability-installation.md) guide apply identically on RHEL.

## 7. When to contact CamDX

Contact CamDX before: deploying a new HA pair, changing an existing HA pair's topology or node count, resolving which PostgreSQL version/path convention applies to your host, or finalizing your SELinux/firewalld rule set for the HA case. CamDX will confirm the exact configuration values applicable to your deployment as part of that planning.

## 8. References

- [Ubuntu HA](../ubuntu/high-availability-installation.md) for the full shared architecture, state-replication-scope table, health-check, failover, backup/recovery, and Operational Monitoring detail this document does not repeat.
- [RHEL Standalone Installation](./standalone-installation.md).
- Upstream X-Road External Load Balancer Installation Guide (`nordic-institute/X-Road`), in particular its RHEL 8/9 PostgreSQL initialization and SELinux sections.
- [Deployment Model Selector](../deployment-models.md), [Network Requirements](../network-requirements.md).
