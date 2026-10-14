# CamDX Security Server - Container Deployment

This document is for new container deployments. If this is an existing CamDX Security Server, do not use this fresh-deployment procedure. Contact CamDX for coordinated migration guidance. This document is not an HA guide; if your organization requires HA, contact CamDX before deployment.

This guide gets a fresh Security Server deployed and ready for [Initial Configuration](../initial-configuration.md). It does not configure your member identity, Security Server Code, token, keys, certificates, or registration, that is a separate step, covered there.

**Before production handoff:** CamDX requires `message-body-logging=false` (see [Initial Configuration](../initial-configuration.md)). Applying this on a container deployment currently requires CamDX-provided container configuration guidance. Contact CamDX for this before going to production.

## 1. Image identity

| Field | Value |
|---|---|
| Repository | `ghcr.io/techo-startup-center/camdx/security-server` |
| Approved tags | `7.8.2`, `noble-7.8.2` (both resolve to the digest below) |
| Immutable digest | `sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b` |
| Image ID | `sha256:c4f62f32d57f7cfbeba4ecdfe825a7ea5c8daa4e70e1d7f986a54b518f27e1ce` |
| Platform | `linux/amd64` only |
| Visibility | Public, anonymous pull |

`:latest` is not published. Do not rebuild or republish this image; pull and deploy the existing artifact.

## 2. Before you start

- Docker Engine and Docker Compose v2. (Validated at `28.4.0`/`v2.39.2`; no other version independently established as a minimum.)
- `x86_64`/`linux/amd64` host, the only platform the published image supports.
- Outbound HTTPS access to `ghcr.io` to pull the image (public, no authentication required).
- A synchronized system clock, required before certificate/registration/timestamping operations.
- The Security Server's public-facing FQDN prepared and resolvable.
- CamDX runtime connectivity reachable from the host running the container, see [`../network-requirements.md`](../network-requirements.md).
- External PostgreSQL connectivity, if using the recommended default pattern (§6), either co-located on the same Docker host/network or reachable over the network.

The native Ubuntu/RHEL package-install prerequisites (EPEL, SELinux tooling, `firewalld`, `dnf`/`apt` bootstrap) do not apply here; the container's runtime dependencies are already in the image.

## 3. Pull and verify the image

For a controlled deployment, pin the immutable digest, do not deploy against a mutable tag.

```bash
docker pull ghcr.io/techo-startup-center/camdx/security-server@sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b
```

```bash
docker image inspect ghcr.io/techo-startup-center/camdx/security-server@sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b \
  --format '{{.Id}} {{.Architecture}}/{{.Os}}'
```

Expected output:

```text
sha256:c4f62f32d57f7cfbeba4ecdfe825a7ea5c8daa4e70e1d7f986a54b518f27e1ce amd64/linux
```

If the local Image ID does not match exactly, stop. Do not deploy an unverified image; re-pull the exact digest above, or escalate to CamDX.

## 4. Deployment architecture

A two-service Docker Compose architecture: the Security Server container, and a separate `postgres:16` container for the recommended external-database pattern (§6).

**`postgres/compose.yaml`** (the shared network and the external database):

```yaml
services:
  postgres:
    image: postgres:16
    container_name: camdx-postgres
    restart: unless-stopped

    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}

    volumes:
      - camdx-postgres-data:/var/lib/postgresql/data

    networks:
      - camdx

    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d postgres"]
      interval: 5s
      timeout: 5s
      retries: 20
      start_period: 10s

networks:
  camdx:
    name: camdx

volumes:
  camdx-postgres-data:
    name: camdx-postgres-data
```

**`security-server/compose.yaml`** (the CamDX Security Server, joining the network above):

```yaml
services:
  security-server:
    image: ghcr.io/techo-startup-center/camdx/security-server@sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b
    container_name: camdx-security-server
    restart: unless-stopped

    networks:
      - camdx

    volumes:
      - camdx-security-server-etc-xroad:/etc/xroad

    environment:
      XROAD_DB_HOST: camdx-postgres
      XROAD_DB_PORT: "5432"
      XROAD_DB_PWD: ${XROAD_DB_PWD}
      XROAD_ADMIN_USER: ${XROAD_ADMIN_USER}
      XROAD_ADMIN_PASSWORD: ${XROAD_ADMIN_PASSWORD}
      XROAD_TOKEN_PIN: ${XROAD_TOKEN_PIN}

    ports:
      - "127.0.0.1:4000:4000"
      - "8080:8080"
      - "8443:8443"
      - "5500:5500"
      - "5577:5577"
      - "127.0.0.1:5588:5588"

networks:
  camdx:
    external: true

volumes:
  camdx-security-server-etc-xroad:
    name: camdx-security-server-etc-xroad
```

Two separate `.env` files are required, one per compose file (§10). Both must exist and be populated before either service is started.

## 5. Persistence

The named volume `/etc/xroad` must survive container recreation. It holds the entire configuration tree (`conf.d/local.ini`, `services/`, generated certificates, per-service database credentials in `db.properties`, and the software-token autologin PIN file if used).

The following does **not** persist across container recreation (`docker compose up -d --force-recreate` or equivalent):

- `docker logs` output (tied to the container ID, not a volume).
- `/var/log/supervisor/` (ephemeral writable layer).

Capture `docker logs` output before any deliberate container recreation if recent history might be needed. Do not recreate this container relying only on the container's own writable layer; the named volumes are what make recreation safe.

If using the local-PostgreSQL path (§6) instead of the external-database pattern, `/var/lib/postgresql/16/main` must also be persisted via its own volume.

**The validated Compose scaffold shown in §4 persists `/etc/xroad` and the external PostgreSQL data volume, but does not currently mount `/var/lib/xroad` as a separate volume.** Upstream uses `/var/lib/xroad` for backup files and messagelog archive files produced by the archiver process. This is distinct from the messagelog database itself, which is stored in the external PostgreSQL volume and is persisted exactly as described above; only the separate archive/backup files under `/var/lib/xroad` are not currently covered by a named volume in this scaffold. If these archive/backup files must survive container recreation, contact CamDX for the approved persistence/backup treatment before production use.

## 6. Database model

**Recommended: external PostgreSQL**, the pattern shown in §4. Set via environment variables:

| Variable | Purpose | Default if unset |
|---|---|---|
| `XROAD_DB_HOST` | External PostgreSQL host | `127.0.0.1` (triggers the local-DB path instead) |
| `XROAD_DB_PORT` | External PostgreSQL port | `5432` |
| `XROAD_DB_PWD` | PostgreSQL superuser password, used only once at first container initialization | none, required for the external-DB path on first init |
| `XROAD_DATABASE_NAME` | Optional database-name prefix used when constructing per-service role names at first init | unset |

Use the official `postgres:16` image, not a CamDX-modified one.

`postgres:16` is a mutable tag, not a pinned digest; CamDX has not published an immutable PostgreSQL digest for this deployment. Do not assume a later pull of `postgres:16` necessarily gives you the identical PostgreSQL artifact that was originally validated. Do not substitute an arbitrary digest and treat it as CamDX-validated. If your deployment requires immutable PostgreSQL image pinning, coordinate with CamDX on the artifact to record/use.

**Credential rotation:** `XROAD_DB_PWD` is consumed only at first initialization. Changing the environment variable on an already-initialized external database does not change the stored PostgreSQL role password. To rotate it on a running deployment:

1. Update the PostgreSQL role directly, e.g. `ALTER ROLE postgres WITH PASSWORD '<new value>';` (takes effect immediately).
2. Then update both `.env` files so they stay consistent: `POSTGRES_PASSWORD` in `postgres/.env`, and `XROAD_DB_PWD` in `security-server/.env`.

Never print or echo the real credential value while performing this rotation.

The image also supports a local PostgreSQL path (leave `XROAD_DB_HOST` unset). If you are considering this as your production pattern, contact CamDX first; the external-database pattern above is the one with full validated recreation/reboot coverage.

## 7. Operational Monitoring

Operational Monitoring capability is required for every CamDX Security Server. Local Operational Monitoring is baked into this image and runs automatically from first start; there is no separate install step.

If your deployment requires a remote/external Operational Monitoring topology, contact CamDX before deployment.

No `xroad-proxy` restart is required for OPMON in the container path (unlike the RHEL native installer); OPMON is already running from the container's first start.

## 8. Process model

The container does not use systemd. Process supervision is handled by Supervisor (`supervisord`). Every managed process logs to the container's own stdout stream, visible via `docker logs`.

No `HEALTHCHECK` is baked into the image itself; the health-check mechanism is the `5588` HTTP endpoint (§9), which your own Compose `healthcheck:` or orchestrator probe should invoke.

## 9. Ports

| Port | Role | Recommended exposure |
|---|---|---|
| `4000` | Admin UI | `127.0.0.1` only (or your authorized administration network) |
| `5500` | Security Server peer traffic | Published, per [`../network-requirements.md`](../network-requirements.md) |
| `5577` | Security Server peer traffic, OCSP-related | Published, per [`../network-requirements.md`](../network-requirements.md) |
| `5588` | Health-check endpoint | `127.0.0.1` only (or your authorized monitoring network) |
| `8080` | Client-proxy (consumer information system) HTTP | Published, scope to your trusted network |
| `8443` | Client-proxy (consumer information system) HTTPS | Published, scope to your trusted network |

Do not publish PostgreSQL (`5432`) externally. Restrict the Admin UI and health endpoint to your authorized administrator/monitoring network rather than binding them to `0.0.0.0`.

## 10. Secrets handling

Never place real secrets directly in a committed compose file. Use two separate, `chmod 600`, git-ignored `.env` files:

```bash
# postgres/.env - chmod 600, never committed
POSTGRES_PASSWORD='REPLACE_WITH_POSTGRES_SUPERUSER_PASSWORD'
```

```bash
# security-server/.env - chmod 600, never committed
XROAD_DB_PWD='REPLACE_WITH_POSTGRES_SUPERUSER_PASSWORD'
XROAD_ADMIN_USER='REPLACE_WITH_ADMIN_USERNAME'
XROAD_ADMIN_PASSWORD='REPLACE_WITH_ADMIN_PASSWORD'
XROAD_TOKEN_PIN='REPLACE_WITH_SOFTWARE_TOKEN_PIN'
```

```bash
chmod 600 postgres/.env security-server/.env
```

`POSTGRES_PASSWORD` and `XROAD_DB_PWD` must initially be set to the identical value; both refer to the same PostgreSQL superuser role. Keep them consistent after any rotation (§6).

Use single-quoted values (`KEY='value'`) in both `.env` files if a secret contains `$` or `#`; Compose's dotenv parser only treats single-quoted values as fully literal. Populate `.env` non-interactively (for example, reading from `read -rs` and writing with `printf`) rather than with an interactive editor, to avoid introducing hidden control characters into a secret value.

## 11. Deployment sequence

Run every command below from the deployment root, the directory that directly contains the `postgres/` and `security-server/` subdirectories.

1. Complete §2 to §3 (host prerequisites, image pull and verification).
2. Create `postgres/.env`, populate `POSTGRES_PASSWORD`, `chmod 600`.
3. Create `security-server/.env`, populate `XROAD_DB_PWD`, `XROAD_ADMIN_USER`, `XROAD_ADMIN_PASSWORD`, `XROAD_TOKEN_PIN`, `chmod 600`. `XROAD_DB_PWD` must initially match `POSTGRES_PASSWORD`.
4. Validate the PostgreSQL compose file's variable interpolation:
   ```bash
   docker compose --env-file postgres/.env -f postgres/compose.yaml config -q
   ```
   A clean exit means the `.env` file resolved correctly.
5. Start PostgreSQL:
   ```bash
   docker compose --env-file postgres/.env -f postgres/compose.yaml up -d
   ```
6. Confirm PostgreSQL is healthy before proceeding:
   ```bash
   docker compose --env-file postgres/.env -f postgres/compose.yaml ps
   ```
7. Validate the Security Server compose file's variable interpolation:
   ```bash
   docker compose --env-file security-server/.env -f security-server/compose.yaml config -q
   ```
8. Start the Security Server:
   ```bash
   docker compose --env-file security-server/.env -f security-server/compose.yaml up -d
   ```
9. Proceed to §12's readiness checks before handing off to Initial Configuration.

## 12. Verify

Before [Initial Configuration](../initial-configuration.md) (does not require the software token to be initialized):

```bash
docker compose --env-file security-server/.env -f security-server/compose.yaml ps
docker inspect camdx-security-server --format '{{.RestartCount}}'
docker exec camdx-security-server supervisorctl status
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5588/
curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:4000/
```

Expect the container `running`, `RestartCount` `0`, the expected Supervisor programs `RUNNING` (`postgres` correctly `STOPPED` if using the external-DB pattern), and both `curl` checks returning `200`. Also confirm the PostgreSQL container shows `healthy`.

```bash
docker inspect camdx-security-server --format '{{json .Mounts}}'
```

Confirm `/etc/xroad` is backed by the named volume (`camdx-security-server-etc-xroad`), not the container's writable layer.

After [Initial Configuration](../initial-configuration.md) is complete:

```bash
docker exec camdx-security-server signer-console list-tokens
```

Expect the token to show `OK, writable, available, active`, with no `USER_PIN_INCORRECT` in recent `docker logs`.

## 13. Restart, recreate, and reboot

| Event | What happens | Notes |
|---|---|---|
| Container restart (`docker restart`, or after a Docker daemon restart) | Same container ID; `docker logs` history persists | Identity, certificates, registration, token auto-unlock, and global configuration remain intact |
| Container recreation (`docker compose up -d --force-recreate`) | New container ID; `docker logs` and `/var/log/supervisor` are lost | Named-volume-backed state (`/etc/xroad`, external PostgreSQL data) persists, provided the volumes from §4/§5 are used |
| Host reboot | Docker daemon restarts; containers with `restart: unless-stopped` come back automatically | Existing container, not recreated |

Do not assume persistence across recreation merely because restart or reboot succeeded; recreation is a materially different event (new container ID, ephemeral layer discarded).

## 14. Continue

**Deployment is complete. Member/CamDX registration is not.**

Continue to [Initial Configuration](../initial-configuration.md) to connect this Security Server to your member identity and complete registration.

## 15. Deployment failed?

See [`../troubleshooting/README.md`](../troubleshooting/README.md). Preserve the exact error text/code before contacting CamDX.

## 16. References

- [`../network-requirements.md`](../network-requirements.md), [`../initial-configuration.md`](../initial-configuration.md), [`../troubleshooting/README.md`](../troubleshooting/README.md).
