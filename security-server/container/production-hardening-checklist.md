# CamDX Security Server - Container Production-Hardening Checklist

This is a companion checklist to [Container Deployment](./deployment.md), for a member preparing a container Security Server for production use. It does not change that guide's supported status; container standalone deployment is supported for teams with mature container operations. Use this checklist to confirm your deployment is production-ready, and to identify which items require coordination with CamDX before going live.

## 1. Checklist

| Requirement | What to confirm | Status / CamDX coordination |
|---|---|---|
| Docker host hardening | Is the Docker host hardened per your organization's standard (a separate `/var/lib/docker` partition, audit logging of Docker paths, `userns-remap`, `live-restore`, `userland-proxy=false`, `icc=false`, dropped `NET_RAW` capability, user-defined bridge networks)? | Member responsibility. Coordinate with CamDX if you need guidance specific to the CamDX image. |
| `docker.sock` access | Is access to `docker.sock` restricted (`chown root:docker` / `chmod 660`, never mounted inside a container), and is remote daemon access, if any, protected with TLS? | Member responsibility. |
| Resource limits | Are `--memory`, `--cpus`, and `--pids-limit` bounds set for the Security Server container? The reference Compose scaffold in [Container Deployment](./deployment.md) does not set these by default. | Member responsibility. |
| Secrets protection | Are `.env` files `chmod 600` and excluded from version control, per [Container Deployment](./deployment.md) Secrets Handling? | Member responsibility. |
| PostgreSQL backup | Is the external `postgres:16` database backed up on a schedule that meets your organization's recovery requirements? | Member responsibility. CamDX has not published a validated immutable PostgreSQL digest; see [Container Deployment](./deployment.md) Database Model. |
| Restore tested | Has a full backup-then-restore-onto-a-new-host rehearsal been performed for this deployment? | Member responsibility. Coordinate with CamDX before a production restore if you are unsure of the correct procedure. |
| External log retention | Are container logs retained externally, outside the container's own filesystem (no log-rotation/retention policy is configured by default)? | Member responsibility. |
| `/var/lib/xroad` backup/archive persistence | The reference deployment persists `/etc/xroad` and the external PostgreSQL database, but does not mount a separate persistent volume for `/var/lib/xroad`, which holds messagelog archive files and backups. If these files must survive container recreation, this is required. | Contact CamDX for the approved persistence/backup treatment before production use. |
| Monitoring | Is Operational Monitoring configured and is its data reaching your intended destination (local or remote)? | See [Container Deployment](./deployment.md) Operational Monitoring. CamDX has not yet published a supported container configuration mechanism for remote/external Operational Monitoring; contact CamDX for the applicable container configuration. |
| Organizational backup/DR coverage | Is this deployment included in your organization's existing backup and disaster-recovery processes, not only in Security-Server-specific backups? | Member responsibility. |
| HSM/PKCS#11 | Does your deployment require a hardware security module via PKCS#11? | Contact CamDX; this has not been validated in CamDX's container deployment and should not be assumed to work without confirmation. |
| Standalone or HA | Is this a standalone deployment, or are you requesting HA? | Container/Kubernetes HA is not currently a standard CamDX deployment option; see [Deployment Model Selector](../deployment-models.md). Contact CamDX if you need HA. |
| Image-upgrade rehearsal | Has upgrading this deployment to a future CamDX container image version been rehearsed? | Coordinate with CamDX before your first production image upgrade. |
| Upgrade rollback/recovery | Before a future CamDX container image upgrade is used in production, has rollback/recovery against that target version been rehearsed? | Coordinate with CamDX before the first production image upgrade. Do not assume that simply switching back to an older image is a safe rollback; database, volume, and configuration compatibility must be considered. |

## 2. References

- [Container Deployment](./deployment.md): the supported container standalone deployment guide this checklist accompanies.
- [Deployment Model Selector](../deployment-models.md): deployment-model comparison.
