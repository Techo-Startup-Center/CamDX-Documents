# CamDX Security Server — Container Deployment

## Status / scope

**Status: APPROVED / SAFE-EVIDENCED**, derived directly from the E2-C1 through E2-C5B container validation evidence (`~/TI-Director-Brain/initiatives/camdx-xroad-upgrade/evidence/2026-09-*-e2-container-*.md`), from read-only inspection of the frozen, published container image itself (`docker image inspect`, `docker create`/`docker cp` to extract `entrypoint.sh`, `_entrypoint_common.sh`, and the full `/etc/supervisor` configuration — no container was run to produce this document, and the image was never rebuilt), and from the actual validated deployment scaffold (`~/engineering/camdx-xroad-7.8.2-release/e2c-runtime/{sidecar,postgres}/compose.yaml`). This document does not infer native Ubuntu/RHEL packaging behavior into the container path — every claim below traces to container-specific evidence.

**Publication is now COMPLETE (E2-C5B, CLOSED / PASS / GO) — this supersedes the earlier placeholder draft of this document, which correctly deferred pull instructions pending registry publication.** The image is public and anonymously pullable; both approved tags are confirmed live.

This document is for **new container deployments**. It is **not** an in-place upgrade procedure, **not** a Member Migration guide, and **not** an HA guide — HA remains `REQUIRES VERIFICATION` throughout this document except where a specific container fact was explicitly validated (none currently establish an HA container topology). **This document does not rebuild, retag, or republish the frozen image** — every command below either pulls the existing published artifact or operates against it read-only.

This document does not duplicate content owned elsewhere:
- CamDX infrastructure runtime connectivity (Central Server, Management Security Server, TSA, OCSP, Central Monitoring) → [`../network-requirements.md`](../network-requirements.md)
- API provider endpoint connectivity (e-KYC, e-KYB, OCR, etc.) → [`../provider-connectivity.md`](../provider-connectivity.md)
- Member/anchor/key/certificate/subsystem configuration → [`../initial-configuration.md`](../initial-configuration.md)

## 1. Frozen image identity

| Field | Value |
|---|---|
| Repository | `ghcr.io/techo-startup-center/camdx/security-server` |
| Approved tags | `7.8.2`, `noble-7.8.2` — both confirmed to resolve to the identical digest below. **`latest` is not published** (confirmed absent, `HTTP 404`, both at publication time and independently re-checked this round). |
| Immutable registry digest | `sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b` |
| Frozen Image ID | `sha256:c4f62f32d57f7cfbeba4ecdfe825a7ea5c8daa4e70e1d7f986a54b518f27e1ce` |
| Frozen archive SHA-256 | `f3b5ba5ffa40c86575979572bf6ae7950fdfecb1c8bd1aad40c1117cebe267db` |
| Platform | `linux/amd64` only — no other architecture is published or evidenced |
| Package visibility | Public; anonymous pull confirmed for both tags |
| GHCR package linkage | `Techo-Startup-Center/CamDX` (public repository) — `COMPLETE / PASS` |

**Do not use or publish `:latest`.** **Do not rebuild or republish this image** — this document only pulls and deploys the existing, already-validated artifact. For any *future* build only (not this frozen one), the recommended OCI source label is `org.opencontainers.image.source=https://github.com/Techo-Startup-Center/CamDX` — confirmed via `docker image inspect` that the **current** frozen image does not carry this label (only `org.opencontainers.image.version=24.04` is present); this is not a defect in the current artifact and is not a reason to rebuild it.

## 2. Before you start

- **Container engine:** Docker (validated engine: Docker Engine, confirmed via evidence at server version `28.4.0` on the validation host; Docker Compose v2, confirmed at `v2.39.2`). No specific minimum version is asserted beyond what was directly observed — do not treat these exact versions as a hard minimum, but do not assume an arbitrarily old Docker/Compose version either.
- **Architecture:** `x86_64`/`linux/amd64` host — this is the only platform the published image supports.
- **Package-repository connectivity:** outbound HTTPS access to `ghcr.io` to pull the image (public, no authentication required for pulling — see §7).
- **Time synchronization** must be healthy before certificate/registration/timestamping operations — clock skew affects certificate validity checks, exactly as for the native installs. This document does not specify or hard-code an NTP server; that remains an infrastructure/operator decision.
- **DNS/FQDN:** the Security Server's public-facing FQDN must be prepared and resolvable before the certificate/registration steps in [`../initial-configuration.md`](../initial-configuration.md).
- **CamDX runtime connectivity** (Central Server, Management Security Server, TSA, OCSP, Central Monitoring) must be reachable from the host running the container — see [`../network-requirements.md`](../network-requirements.md); not duplicated here.
- **External PostgreSQL connectivity**, if using the validated external-database pattern (§11 — the recommended default) — either co-located on the same Docker host/network (as validated) or reachable over the network.
- **`curl`** (or an equivalent HTTP client), on whatever host runs the §17A deployment-readiness checks — this is an operator-side verification tool, not a CamDX Security Server container runtime requirement; see §7 for the full tool-dependency classification.

**Do not copy the native Ubuntu/RHEL package-install prerequisites (EPEL, SELinux tooling, `firewalld`, `dnf`/`apt` bootstrap, etc.) into this guide** — none of them apply to a single pre-built container image; the container's own runtime dependencies are already baked into the image.

## 3. Information provided by CamDX (onboarding)

Identical to the Ubuntu/RHEL guides' own §3 — CamDX supplies or confirms Member Name, Member Class, Member Code, Security Server Code (provided/confirmed by CamDX, distinct from the Member Code), Subsystem Code(s), and target environment during onboarding. **Use generic placeholders only when illustrating these fields** — do not reproduce real member-specific onboarding values in this document or in any canonical/public documentation. Have this information ready before proceeding to [`../initial-configuration.md`](../initial-configuration.md).

## 4. Network and DNS prerequisites

Full CamDX infrastructure connectivity (every authorized IP address, per environment and service) is owned by [`../network-requirements.md`](../network-requirements.md) — **not duplicated here**. See §14 below for the container-specific port-exposure classification (distinct from, but consistent with, the infrastructure matrix owned there).

## 5. Provider connectivity (if applicable)

If this member needs to reach a specific API provider (e-KYC, e-KYB, OCR, or another), that endpoint information is owned by [`../provider-connectivity.md`](../provider-connectivity.md) — **not duplicated here**.

## 6. Image selection and pinning

**For a controlled production deployment, pin the immutable digest — do not deploy against a mutable tag.**

**Production-safe, digest-pinned reference (preferred):**
```
ghcr.io/techo-startup-center/camdx/security-server@sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b
```

**Human-readable tags (for discovery/documentation only — both currently resolve to the exact digest above):**
```
ghcr.io/techo-startup-center/camdx/security-server:7.8.2
ghcr.io/techo-startup-center/camdx/security-server:noble-7.8.2
```

A tag is a mutable pointer that *could* be moved to a different digest in the future by a subsequent publication; the digest itself is immutable by construction (content-addressed) and is what actually guarantees you are running the exact, previously-validated artifact. **Never use `:latest`** — it is not published for this image, and even if it were, it would not provide the immutability guarantee a controlled deployment needs. No other tag is invented or implied supported by this document.

## 7. Public GHCR access — verification

The published package is public and anonymously pullable — no GitHub authentication is required. **This document does not add any tool to the CamDX Security Server container runtime requirement merely to deploy the image** — the canonical *pull-and-run* path below (§7.1) needs only Docker itself. `curl` is, however, genuinely used elsewhere in this guide as an **operator-side** deployment-verification tool — see the classification below.

- **`curl`** — used by §17A's mandatory health-endpoint and Admin UI reachability checks (`http://127.0.0.1:5588/`, `https://127.0.0.1:4000/`), and by the optional §7.2 registry/audit path. This is an operator-side verification tool run against the deployed container from the Docker host (or wherever the operator runs these checks) — it is **not** part of the CamDX Security Server container runtime itself, and the container does not require `curl` to function. Any equivalent HTTP client may be substituted for the §17A checks; this guide's canonical examples use `curl`.
- **`python3`** — required **only** for the optional §7.2 registry/audit token-parsing example. Not needed anywhere else in this guide, including §17A.

### 7.1 Canonical deployment verification (Docker only — no extra tools required)

```bash
# Pull by immutable digest (no authentication needed for a public package)
docker pull ghcr.io/techo-startup-center/camdx/security-server@sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b
```

```bash
docker image inspect ghcr.io/techo-startup-center/camdx/security-server@sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b \
  --format '{{.Id}} {{.Architecture}}/{{.Os}}'
```

Expected output:
```
sha256:c4f62f32d57f7cfbeba4ecdfe825a7ea5c8daa4e70e1d7f986a54b518f27e1ce amd64/linux
```

**If the resulting local Image ID does not match `sha256:c4f62f32d57f7cfbeba4ecdfe825a7ea5c8daa4e70e1d7f986a54b518f27e1ce` exactly — STOP.** Do not deploy an unverified image. Do not attempt to "fix" this by rebuilding — re-pull the exact digest above, or escalate to CamDX release engineering.

**Do not require GitHub authentication for this pull** — the package is public. Only supply credentials if a specific environment's outbound network policy or a local rate-limit condition actually requires it; this document does not publish a PAT/credential example, since none is needed for the validated public-access path.

### 7.2 Optional registry/audit verification (requires `curl` and `python3`)

Useful for an independent, registry-side audit (e.g. confirming a tag's digest without pulling the full image) — **this method requires `curl` (also used by §17A, see above) and `python3` (not needed anywhere else in this guide) on whatever host runs it.** Do not assume `python3` is present; install it explicitly only if you intend to run this optional check.

Confirmed directly (independently re-verified via a fresh anonymous token exchange, not merely operator-reported, per `evidence/2026-09-21-e2-container-ghcr-publication.md` Phase 6):

```bash
# List published tags anonymously
curl -fsSL https://ghcr.io/v2/techo-startup-center/camdx/security-server/tags/list
# → {"name":"techo-startup-center/camdx/security-server","tags":["jammy-7.3.2","7.8.2","noble-7.8.2"]}
```

```bash
# Confirm the registry digest for a given tag, directly from the HTTP response header
# (not a derived/computed hash — this is the authoritative registry digest)
TOKEN=$(curl -fsSL "https://ghcr.io/token?scope=repository:techo-startup-center/camdx/security-server:pull" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -fsSL -I \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  https://ghcr.io/v2/techo-startup-center/camdx/security-server/manifests/7.8.2 \
  | grep -i docker-content-digest
# → docker-content-digest: sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b
```

## 8. Deployment architecture

**Derived directly from the validated E2-C runtime configuration** (`~/engineering/camdx-xroad-7.8.2-release/e2c-runtime/{sidecar,postgres}/compose.yaml`) — a two-service Docker Compose architecture: the Security Server container itself, plus a separate, official `postgres:16` container for the validated external-database pattern (§11). **This is the validated pattern, not a hypothetical one** — it is what E2-C2A through E2-C3A actually exercised end to end, including restart, recreation, and host-reboot recovery (§18). Internal validation-specific naming (`camdx-e2c-*`) has been generalized to canonical names below without changing the underlying architecture.

**`postgres/compose.yaml`** (brings up the shared network and the external database):
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

**`security-server/compose.yaml`** (the CamDX Security Server itself, joining the network created above):
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

**Two separate, protected `.env` files are required** — one per compose file, since each references a distinct set of secret-bearing variables (`postgres/.env` for `POSTGRES_PASSWORD`; `security-server/.env` for `XROAD_DB_PWD`/`XROAD_ADMIN_USER`/`XROAD_ADMIN_PASSWORD`/`XROAD_TOKEN_PIN` — see §15). **Both files must exist and be populated before either service is started** — do not start PostgreSQL first and populate its `.env` afterward. See §16 for the full, ordered deployment sequence — run from the deployment root containing the `postgres/` and `security-server/` directories — including explicit `--env-file` usage so Compose does not fall back to an implicit, ambiguous `.env` file lookup. Neither compose file contains a `build:` directive — confirmed as a release-handoff requirement in the validated deployment (`evidence/2026-09-21-e2-container-deployment-readiness.md` Phase 6): the image is always referenced, never built, by the deployment definition.

## 9. Host prerequisites (classified)

| Category | Requirement |
|---|---|
| Container engine | Docker Engine + Docker Compose v2 (validated at `28.4.0`/`v2.39.2`; no other minimum independently established) |
| CPU architecture | `x86_64` (`linux/amd64`) only |
| Storage / persistent filesystem | Docker-managed named volumes (§10) — no specific filesystem type required beyond whatever Docker's storage driver needs on this host |
| DNS/FQDN | Security Server's public FQDN prepared and resolvable |
| Time synchronization | Must be healthy before certificate/registration/timestamping work — no NTP endpoint invented here |
| Network/firewall | Per §14's port classification and [`../network-requirements.md`](../network-requirements.md) |
| Database connectivity | Reachable `postgres:16` instance (co-located, as validated, or external) if using the recommended external-DB pattern |
| CamDX runtime connectivity | Per [`../network-requirements.md`](../network-requirements.md) — required before [`../initial-configuration.md`](../initial-configuration.md), not merely to pull/start the container |

## 10. Persistence — critical

**Determined directly from the entrypoint scripts (`entrypoint.sh`, `_entrypoint_common.sh`, extracted read-only from the frozen image) and the validated compose scaffold, not guessed.**

**Must survive container recreation — persisted via the named volume `/etc/xroad`:**

- `/etc/xroad/` — the entire configuration tree: `conf.d/local.ini`, `services/`, `ssl/internal.crt`/`ssl/internal.key`/`ssl/proxy-ui-api.crt` (auto-generated on first start if absent), `VERSION` (configuration-version marker used by the entrypoint's migration logic), and — **if local software-token auto-unlock (`xroad-autologin`) is used** — `/etc/xroad/autologin` (the PIN source file the container's autologin mechanism reads; see §15).
- `/etc/xroad/db.properties` — per-service database role credentials generated at first initialization (`serverconf`, `op-monitor`, `messagelog` roles) — **distinct from** the `XROAD_DB_PWD` environment variable, which is only the PostgreSQL `postgres` superuser credential used once at first-init (see §11's credential-rotation warning).
- `/etc/xroad.properties` — a symlink to `/etc/xroad/xroad.properties`, created by the entrypoint on first start; persisted as part of the same volume.

**Does NOT persist across container recreation (`docker compose up -d --force-recreate` or equivalent) — directly confirmed, not assumed:**

- **`docker logs` output (stdout/stderr capture)** — tied to the container ID, not to any volume. Confirmed directly: after a validated recreate, `docker logs`' earliest visible line matched the *new* container's own start time exactly — zero pre-recreate history was visible (`evidence/2026-09-21-e2-container-operations-logging-readiness.md`).
- **`/var/log/supervisor/`** — confirmed no volume mount exists for this path; it is part of the container's ephemeral writable layer and is lost on recreation.
- **The `/.xroad-reconfigured` marker file** (container root) — used only to skip redundant reconfiguration on a plain restart; losing it on recreate is harmless (the entrypoint simply reconfigures again), not a data-loss concern.

**If using the local-PostgreSQL path (§11.1) instead of the validated external-database pattern, `/var/lib/postgresql/16/main` must also be persisted via its own volume** — this was not part of the validated E2-C architecture (which used an external `postgres:16` container with its own separate named volume instead) and is `REQUIRES VERIFICATION` as a complete, end-to-end-tested container-native pattern; see §11.1.

**Capture `docker logs` output (and any non-empty `/var/log/supervisor` files) before any deliberate container recreation** if recent history might be needed — this is the documented operational implication of the finding above, not a theoretical concern.

**Do not recreate this container with identity/key/configuration state relying only on the container's own writable layer.** The named volume(s) above are what make recreation safe; without them, recreation destroys the Security Server's identity, keys, and configuration.

## 11. Database model

**Determined directly from the entrypoint script's own logic and the frozen image's supervisor configuration** — the image supports two patterns; only one has been end-to-end validated by this initiative.

**Recommended / validated: external PostgreSQL** (the pattern actually exercised through E2-C2A–E2-C3A, including recreation and host-reboot recovery, §18). Set via environment variables read by the entrypoint:

| Variable | Purpose | Default if unset |
|---|---|---|
| `XROAD_DB_HOST` | External PostgreSQL host | `127.0.0.1` (triggers the local-DB path instead — see §11.1) |
| `XROAD_DB_PORT` | External PostgreSQL port | `5432` |
| `XROAD_DB_PWD` | `postgres` **superuser** password — used **only once**, at first container initialization, to create/verify the per-service databases and roles (`serverconf`, `op-monitor`, `messagelog`) | none — required for the external-DB path on first init |
| `XROAD_DATABASE_NAME` | Optional database-name prefix used when constructing per-service role names during first init | unset (upstream default naming applies) |

**Validated PostgreSQL container:** the official `postgres:16` image (§8) — not a CamDX-modified image. This matches the version the container's own *local*-DB path would also initialize (`/usr/lib/postgresql/16/bin/initdb`, confirmed via entrypoint inspection), so `16` is a directly-evidenced, not invented, major version for this container baseline specifically (this is a container-specific fact and is not transferred to the native Ubuntu/RHEL PostgreSQL-version question, which remains separately unresolved in those guides).

**PostgreSQL image reproducibility — `postgres:16` is a mutable tag; the exact historically-validated artifact digest is not evidenced.** This task searched all E2-C evidence files, the compose scaffold, and recorded runtime state for a captured PostgreSQL `RepoDigest`/Image ID from the actual validation rounds — none exists; every evidence file that records an image digest does so only for the CamDX Security Server image itself, never for the `postgres` container. A `postgres:16` image is present in this host's local Docker cache (unrelated to this documentation task — not pulled to produce this guide) reporting `PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2)`, matching the exact version string recorded in `evidence/2026-09-20-e2-container-post-reboot-validation.md`; this is noted as a **corroborating observation only** — it is not treated as proof that this specific image digest is the one exercised during E2-C validation, and no digest is presented here as historically pinned. **This is a reproducibility/hardening gap in the deployment definition, not a CamDX Security Server image defect** — see §22. The canonical example below therefore keeps the mutable `postgres:16` tag, matching exactly what the validated scaffold itself recorded, rather than presenting a freshly-pulled digest as if it were the historically-tested one.

**Critical credential-rotation trap, evidenced directly (`evidence/2026-09-21-e2-container-db-credential-readiness.md`):** `XROAD_DB_PWD` is consumed **only at first initialization**. Changing the environment variable on an *already-initialized* external database does **not** change the actual PostgreSQL role's stored password — "changing the container environment does not change an already-initialized data volume's role password." The official `postgres` image's own `POSTGRES_PASSWORD` variable is likewise only an *initialization* variable for a brand-new data directory — setting it on an already-initialized data volume does not rotate that volume's existing role password either. To rotate this credential safely on a running deployment:

1. Update the PostgreSQL role directly and live, e.g. `ALTER ROLE postgres WITH PASSWORD '<new value>';` (takes effect immediately in a live cluster — no PostgreSQL restart is required or prescribed).
2. Only then update **both** `.env` files so they stay consistent with the live credential and with each other: `POSTGRES_PASSWORD` in `postgres/.env`, and `XROAD_DB_PWD` in `security-server/.env` — both refer to the same PostgreSQL `postgres` superuser role and must match. Do not update one and leave the other stale.

Do not assume editing either `.env` file alone rotates a live credential, and never print or echo the real credential value while performing this rotation.

### 11.1 Local PostgreSQL — supported by the image, not the validated production pattern

**Confirmed present in the image's own capability** (via direct entrypoint-script inspection): if `XROAD_DB_HOST` is left unset (defaults to `127.0.0.1`), the entrypoint runs `initdb` for a local PostgreSQL 16 cluster at `/var/lib/postgresql/16/main`, and the frozen image's supervisor configuration includes a `postgres` program (dynamically enabled/disabled by the entrypoint depending on which path is detected). **This capability exists and is real, but this initiative's E2-C validation rounds used the external-database pattern (§11) for every recreation/reboot/credential test performed** — the local-DB container path has not been independently exercised end to end (persistence across recreation, credential handling, backup) by this initiative. **Status: `REQUIRES VERIFICATION`** if you intend to rely on the local-DB container path as your production pattern; it is not a validated alternative in the same sense as external PostgreSQL. Do not copy HA-style database replication assumptions into either path — HA remains out of scope for this document.

## 12. Operational Monitoring

Canonical CamDX policy is unchanged from the native guides: OPMON capability **MANDATORY**, **local = default**, **remote/external = supported alternative**.

**Container-specific implementation, confirmed directly from the frozen image's supervisor configuration and runtime logs:**

- **Local Operational Monitoring is baked into the image and runs by default — there is no separate install step, unlike the native Ubuntu/RHEL packages.** The supervisor configuration (`/etc/supervisor/conf.d/xroad.conf`, extracted read-only) includes a `program:xroad-opmonitor` entry (`/usr/share/xroad/bin/xroad-opmonitor`) with no `autostart=false` override — it starts automatically with every container. This is a genuine container-specific difference from native installs, where `xroad-addon-opmonitoring`/`xroad-opmonitor` must be explicitly `apt`/`dnf` installed.
- **Proxy monitoring (`proxymonitor`) has no separate supervisor program** — confirmed both by the absence of any `program:xroad-addon-proxymonitor` entry in the supervisor configuration and by direct log evidence (`"Registering ProxyMonitorService RPC service"`, logged by `xroad-proxy` itself at container start) — consistent with the same finding independently confirmed for both the Ubuntu and RHEL native builds of this component.
- **Health/monitor ports:** `5588` is the health-check endpoint (confirmed reachable and returning `HTTP 200` at `http://127.0.0.1:5588/` in the validated deployment, both pre- and post-host-reboot) — this is the container/Sidecar-specific `health-check-port` evidence already referenced in the native guides' unresolved-items list; it remains **`REQUIRES VERIFICATION` for native installs specifically**, and this container evidence does **not** silently resolve that native question.
- **Restart behavior:** **no `xroad-proxy` restart is required after enabling OPMON in this container** — unlike the RHEL native finding (where a fresh install of `xroad-addon-opmonitoring` required an explicit `xroad-proxy` restart). This is because OPMON is already running from the container's first start, not added afterward — there is no equivalent "install OPMON after the fact" step in the container path to require a restart in response to. **The RHEL restart requirement is not transferred here, and neither is Ubuntu's unresolved restart state** — this document states the container's own, independently-confirmed behavior only.
- **Remote/external OPMON for the container path:** no environment variable or configuration mechanism for pointing this image at a remote/external Opmonitor node was found in the entrypoint scripts or supervisor configuration. **Status: `REQUIRES VERIFICATION`** — do not invent one.

## 13. Process / supervision model

**The container does not use systemd.** Process supervision is handled entirely by **Supervisor** (`supervisord`), confirmed directly: the image's `CMD` is `/root/entrypoint.sh`, which (after running `_entrypoint_common.sh`'s initialization logic) execs `/usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf`. **Do not describe systemd units for the container runtime** — the native guides' systemd unit inventories do not apply here at all; this is a fundamentally different process model.

**Full supervisor program list, confirmed by direct inspection of `/etc/supervisor/conf.d/xroad.conf`:**

| Program | Command | User | Notes |
|---|---|---|---|
| `postgres` | `postgres -D /var/lib/postgresql/16/main ...` | `postgres` | Only when using the local-DB path (§11.1); the entrypoint dynamically sets `autostart=true`/`false` for this program depending on whether `XROAD_DB_HOST` points local or external. In the validated external-DB deployment, this shows `STOPPED` — expected, not a fault. |
| `xroad-proxy-ui-api` | `/usr/share/xroad/bin/xroad-proxy-ui-api` | `xroad` | Admin UI / management REST API |
| `xroad-signer` | `/usr/share/xroad/bin/xroad-signer` | `xroad` | Signing/authentication key operations, `priority=200` |
| `xroad-confclient` | `/usr/share/xroad/bin/xroad-confclient` | `xroad` | Global configuration client. **`docker logs` tag gotcha, directly confirmed:** this process's stdout is tagged `[xroad-confclient-service]`, not `[xroad-confclient]` as the supervisor program name would suggest — search logs for the correct tag. |
| `xroad-proxy` | `/usr/share/xroad/bin/xroad-proxy` | `xroad` | Core message-exchange proxy, `stopwaitsecs=30` |
| `xroad-autologin` | `/usr/share/xroad/autologin/xroad-autologin-retry-docker.sh` | `xroad` | Automatic software-token PIN entry. **Runs by default in the container** (unlike native installs, where this is an optional, not-installed-by-default package) — `autorestart=false`, so a failed PIN attempt does not loop retry via Supervisor itself (the script has its own internal retry loop instead). See §15 for the PIN source. |
| `xroad-monitor` | `/usr/share/xroad/bin/xroad-monitor` | `xroad` | Environmental/system monitoring |
| `xroad-opmonitor` | `/usr/share/xroad/bin/xroad-opmonitor` | `xroad` | Local Operational Monitoring daemon — see §12 |
| `xroad-addon-messagelog` | `/usr/share/xroad/bin/xroad-messagelog-archiver` | `xroad` | Message log archiver — baked in and running by default, not a separately-installed addon in this container |
| `cron` | `/usr/sbin/cron -f` | `root` | General cron daemon |

Every program logs `stdout`/`stderr` to the container's own stdout stream (`stdout_logfile=/dev/stdout`, `stdout_logfile_maxbytes=0`) — see §19.

**No `HEALTHCHECK` is baked into the image itself** (confirmed via `docker image inspect`, `Healthcheck: None`) — the health-check mechanism is the `5588` HTTP endpoint (§12), which an external health-check definition (Compose `healthcheck:`, an orchestrator probe, or manual polling) must invoke; the image does not self-report health via Docker's own health-status field.

## 14. Ports

**Derived directly from the image's declared `EXPOSE` set (`docker image inspect`) and the validated compose scaffold's actual publish/bind decisions** — not asserted from this task's own prior knowledge of native port defaults.

| Port | Declared in image | Role (confirmed) | Validated exposure |
|---|---|---|---|
| `4000` | Yes | Admin UI | **`127.0.0.1` only** in the validated deployment — not published to all interfaces |
| `5500` | Yes | Security Server peer / server-to-server traffic (see [`../network-requirements.md`](../network-requirements.md)) — **not** the consumer-information-system client path, which is `8080`/`8443` below | Published on all interfaces |
| `5577` | Yes | Security Server peer / server-to-server traffic, OCSP-related — explicitly **not** a log-collection port, per direct evidence | Published on all interfaces |
| `5588` | Yes | Health-check endpoint (§12) | **`127.0.0.1` only** in the validated deployment |
| `8080` | Yes | Client-proxy (consumer-information-system) HTTP | Published on all interfaces |
| `8443` | Yes | Client-proxy (consumer-information-system) HTTPS | Published on all interfaces |

**`8080`/`8443` being the image's own declared/exposed ports is container-specific evidence — it is not used here to silently resolve the broader, still-open native `client-http-port`/`client-https-port` CamDX policy question** (see [`../initial-configuration.md`](../initial-configuration.md) §12 and the Ubuntu/RHEL guides' own unresolved-items lists). The container's stock `8080`/`8443` exposure is stated as a fact about this image; it is not proof of what native installs should standardize on.

**No PostgreSQL port is published externally** in the validated architecture — confirmed directly: neither compose file in §8 publishes `5432` to the host.

**Restrict Admin UI (`4000`) and the health endpoint (`5588`) to the authorized administrator/monitoring network** — the validated deployment used `127.0.0.1`-only binding specifically to prevent broader exposure; adapt the bind address to this deployment's actual authorized topology per [`../network-requirements.md`](../network-requirements.md) rather than publishing these to `0.0.0.0` as a shortcut.

## 15. Secrets handling

**Never place real secrets directly in a committed compose file or public example.** The Security Server container receives four secret-bearing environment variables. The separate PostgreSQL container receives one additional secret-bearing initialization variable, `POSTGRES_PASSWORD` — five secret-bearing values in total across the two-container deployment, each sourced from a local, `chmod 600`, git-ignored `.env` file — **never hardcoded in `compose.yaml` itself**:

| Variable | Purpose | Consumed |
|---|---|---|
| `XROAD_DB_PWD` | PostgreSQL `postgres` superuser password | Once, at first container initialization only (§11) |
| `XROAD_ADMIN_USER` | Initial Admin UI username | Once, at first container initialization (creates the account if it doesn't already exist) |
| `XROAD_ADMIN_PASSWORD` | Initial Admin UI password | Once, at first container initialization |
| `XROAD_TOKEN_PIN` | Software-token PIN, consumed by the `xroad-autologin` mechanism (§13) — must exactly match the PIN chosen during Security Server initialization | Every container start, by the autologin retry script |
| `POSTGRES_PASSWORD` | The `postgres:16` container's own superuser initialization password (separate `.env`, in the `postgres/` deployment directory) — must match `XROAD_DB_PWD` since both refer to the same role | Once, by the official `postgres` image's own entrypoint, at first initialization |

**Docker Compose `.env` dotenv encoding — directly evidenced requirement, not a generic suggestion.** Compose's dotenv parser supports unquoted, double-quoted, and single-quoted values; only **single-quoting** (`KEY='value'`) is fully literal with zero `$`/`${}` expansion and zero `#`-comment truncation — required if a secret value contains either character (confirmed against the actual behavior of Compose `v2.39.2` in this initiative's own validated deployment, including a real corruption incident this exact rule was written to prevent). Populate `.env` **non-interactively** (e.g. a script reading from `read -rs` and writing via `printf`) — an interactive editor risks introducing control/backspace bytes into a secret value, which will not be visually apparent but will break authentication.

**Two separate `.env` files, one per compose file (§8, §16) — do not combine them into one:**

```bash
# postgres/.env — chmod 600, never committed
POSTGRES_PASSWORD='REPLACE_WITH_POSTGRES_SUPERUSER_PASSWORD'
```

```bash
# security-server/.env — chmod 600, never committed
XROAD_DB_PWD='REPLACE_WITH_POSTGRES_SUPERUSER_PASSWORD'
XROAD_ADMIN_USER='REPLACE_WITH_ADMIN_USERNAME'
XROAD_ADMIN_PASSWORD='REPLACE_WITH_ADMIN_PASSWORD'
XROAD_TOKEN_PIN='REPLACE_WITH_SOFTWARE_TOKEN_PIN'
```

```bash
chmod 600 postgres/.env security-server/.env
```

**`POSTGRES_PASSWORD` (in `postgres/.env`) and `XROAD_DB_PWD` (in `security-server/.env`) must initially be set to the identical value** — both refer to the same PostgreSQL `postgres` superuser role in the validated external-DB architecture (§11). Keep them consistent after any credential rotation too (§11's rotation procedure updates both files, never just one).

**Software-token PIN persistence, evidenced directly:** once the token is initialized, the PIN the `xroad-autologin` mechanism uses is read from a **file**, `/etc/xroad/autologin` (confirmed via direct inspection of the image's `default-fetch-pin.sh`), not solely from the `XROAD_TOKEN_PIN` environment variable at every start — this file lives under the persisted `/etc/xroad` volume (§10), so it survives recreation as long as that volume is preserved and the environment variable continues to match it. Treat this file with the same sensitivity as the PIN itself.

**This document does not invent Docker secrets or Kubernetes Secrets support** — no evidence was found that the frozen image reads credentials from `/run/secrets/*` or an equivalent mechanism; the validated, evidenced mechanism is plain environment variables sourced from a protected `.env` file, exactly as shown above. If a specific deployment target (e.g. a Kubernetes cluster) requires a different secret-injection mechanism, that adaptation is the operator's own responsibility and is not validated by this document.

## 16. Deployment sequence

**Run every command in this section from the deployment root — the directory that directly contains the `postgres/` and `security-server/` subdirectories** referenced by the relative paths below (`postgres/.env`, `postgres/compose.yaml`, `security-server/.env`, `security-server/compose.yaml`). The commands themselves are still relative-path commands, run from that one fixed location — explicit `--env-file` does not make them independent of the current working directory; what it does is remove Compose's own implicit `.env`-discovery ambiguity (Compose's default lookup for a bare `.env` file depends on the invocation form and version), by naming exactly which `.env` file each specific compose invocation uses, deterministically. `docker compose ... config -q` (not plain `config`) is used to validate variable interpolation **without** rendering resolved secret values to stdout — `config -q` only reports a nonzero exit and an error message on a problem, printing nothing on success.

1. **Host/image prerequisites** — complete §2–§9, including §7's image pull/verification.
2. **Create `postgres/.env`** (§15's dual-file model): populate `POSTGRES_PASSWORD` only, `chmod 600`, git-ignored, never committed, placeholder-only in any public example.
3. **Create `security-server/.env`**: populate `XROAD_DB_PWD`, `XROAD_ADMIN_USER`, `XROAD_ADMIN_PASSWORD`, `XROAD_TOKEN_PIN`, `chmod 600`, git-ignored, never committed. `XROAD_DB_PWD` must initially match `POSTGRES_PASSWORD` above — both refer to the same PostgreSQL `postgres` superuser role (§11).
4. **Validate the PostgreSQL compose file's variable interpolation before starting anything:**
   ```bash
   docker compose \
     --env-file postgres/.env \
     -f postgres/compose.yaml \
     config -q
   ```
   A clean exit (no output, exit code `0`) means `POSTGRES_PASSWORD` resolved correctly from `postgres/.env`. A missing-variable warning or nonzero exit means the `.env` file is not being found or is incomplete — fix that before proceeding, rather than starting a container with an unresolved secret.
5. **Start PostgreSQL:**
   ```bash
   docker compose \
     --env-file postgres/.env \
     -f postgres/compose.yaml \
     up -d
   ```
6. **Confirm PostgreSQL is healthy before proceeding:**
   ```bash
   docker compose \
     --env-file postgres/.env \
     -f postgres/compose.yaml \
     ps
   # STATE should show "healthy"
   ```
7. **Validate the Security Server compose file's variable interpolation:**
   ```bash
   docker compose \
     --env-file security-server/.env \
     -f security-server/compose.yaml \
     config -q
   ```
   Same clean-exit expectation as step 4, now for all four `security-server/.env` variables.
8. **Start the Security Server:**
   ```bash
   docker compose \
     --env-file security-server/.env \
     -f security-server/compose.yaml \
     up -d
   ```
9. **Proceed to §17A's pre-initial-configuration deployment-readiness checklist** before treating the deployment as ready to hand off to [`../initial-configuration.md`](../initial-configuration.md). §17B's post-configuration checks apply only *after* that handoff is complete.

**Confirm your installed Compose v2 supports the exact syntax above** (`--env-file` as a top-level flag preceding `-f`, and `config -q`) before relying on it in production — both are standard Compose v2 CLI behavior and were exercised in the same form during this initiative's own validated deployment (Compose `v2.39.2`), but this task did not exhaustively test every older v2 minor release.

## 17. Health / validation checklist

**Split into two stages, because software-token state depends on member configuration, which [`../initial-configuration.md`](../initial-configuration.md) owns, not this document.** Checking `Token: 0 (OK, writable, available, active)` or "no `USER_PIN_INCORRECT`" *before* the token has even been initialized would be a lifecycle contradiction — a fresh container has no initialized token yet. §17A covers only what should be true before member configuration begins; §17B covers what becomes checkable only after it completes.

### 17A. Pre-initial-configuration — deployment readiness

Evidence-backed, confirm **before** proceeding to [`../initial-configuration.md`](../initial-configuration.md). **Does not require the software token to be initialized or active** — that happens during initial configuration, not before it.

- [ ] `docker image inspect` on the running container's image shows Image ID `sha256:c4f62f32d57f7cfbeba4ecdfe825a7ea5c8daa4e70e1d7f986a54b518f27e1ce` and `amd64/linux` — §7
- [ ] `docker compose --env-file security-server/.env -f security-server/compose.yaml ps` shows the Security Server container `running` (a clean single start, not a crash-loop)
- [ ] `docker inspect camdx-security-server --format '{{.RestartCount}}'` returns `0` — **use `docker inspect`, not `docker compose ps`, for this value; `docker compose ps` does not expose `RestartCount` in its output**
- [ ] `docker exec camdx-security-server supervisorctl status` shows the expected programs `RUNNING` (§13) — `postgres` correctly `STOPPED` if using the external-DB pattern, that is expected, not a fault
- [ ] Health endpoint reachable: `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5588/` → `200` (`curl` is an operator-side deployment-verification tool for this check — not part of the CamDX Security Server container runtime itself; any equivalent HTTP client works, this guide's canonical examples use `curl`)
- [ ] Admin UI reachable: `curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:4000/` → `200`
- [ ] `docker logs camdx-security-server` reviewed for the startup window against the following operational gate — **not** a literal zero-`ERROR`/`Exception`-string requirement: a fresh, not-yet-configured Security Server can legitimately log messages referencing configuration objects (member, subsystem, certificates) that do not exist until [`../initial-configuration.md`](../initial-configuration.md) is completed, and those expected messages must not by themselves fail this readiness gate.
  - [ ] no repeated fatal startup failure (a process failing to start at all, repeatedly)
  - [ ] no crash loop (cross-check against the `RestartCount`/`supervisorctl status` checks above)
  - [ ] no database-connectivity/migration failure (distinct from the dedicated PostgreSQL check below)
  - [ ] no unexpected process-termination error (a managed process exiting outside normal Supervisor-controlled behavior)
- [ ] PostgreSQL container `healthy` (`docker compose --env-file postgres/.env -f postgres/compose.yaml ps`), and the Security Server's `docker logs` shows successful database connection/migration (`Liquibase: Update has been successful` or equivalent, no connection errors)
- [ ] Local OPMON process present: `xroad-opmonitor` `RUNNING` in `supervisorctl status` (§12) — functional data querying is a post-configuration check, §17B
- [ ] Persistent volumes present and correctly mounted: `docker inspect camdx-security-server --format '{{json .Mounts}}'` shows `/etc/xroad` backed by the named volume, not the container's writable layer
- [ ] CamDX infrastructure connectivity confirmed available from the host (per [`../network-requirements.md`](../network-requirements.md))
- [ ] Peer listener ports (`5500`/`5577`) bound and reachable from the authorized peer network, not merely locally

**Do not claim** software token initialized/active, member registration PASS, certificate registration PASS, or real API exchange PASS at this stage — none of that exists yet; it is the outcome of [`../initial-configuration.md`](../initial-configuration.md), not of container deployment alone.

### 17B. Post-initial-configuration — runtime check

**Only meaningful after [`../initial-configuration.md`](../initial-configuration.md) is complete** — do not attempt these before the software token, member identity, and certificates actually exist. This section does not duplicate that workflow; it only re-confirms the container-runtime consequences of having completed it.

- [ ] Software token initialized and auto-unlocks on start: `Token: 0 (OK, writable, available, active)` via `signer-console list-tokens` (or `docker exec camdx-security-server signer-console list-tokens`)
- [ ] No `USER_PIN_INCORRECT` present anywhere in recent `docker logs`
- [ ] `xroad-signer` healthy, AUTH and SIGN keys both `available`
- [ ] Security Server identity, AUTH/SIGN certificate registration, and subsystem registration all confirmed persisted
- [ ] Local `operational_data` table queryable with a nonzero/growing record count reflecting real activity
- [ ] If this deployment requires restart/recreate persistence, independently re-confirm it on this specific host/storage backend before go-live — see §18; do not assume the E2-C validation evidence transfers automatically to a different storage backend or host configuration.

## 18. Restart / recreate / reboot boundaries

**Distinguish these precisely — they are not interchangeable, and only some have been directly validated with the persistence architecture in §8/§10:**

| Event | What happens to the container | Validated? |
|---|---|---|
| **Container process restart** (a process inside the container is restarted by Supervisor, e.g. `autorestart=true` after a crash) | Same container, same ID; Supervisor's own `autorestart` handles this internally | Implicit in normal operation; individual program `autorestart` behavior is as configured in §13's table |
| **Container restart** (`docker restart`, or Docker's `unless-stopped` policy after the Docker daemon restarts) | Same container ID preserved; `docker logs` history **persists** (same container) | **PASS**, directly validated (E2-C2A/E2-C2B): identity, certificates, registration, token auto-unlock, and global configuration all confirmed intact after a restart triggered by an actual host reboot; local OPMON remained functional and a remote operational-data retrieval (`getSecurityServerOperationalData`, queried by a separate monitoring client) was successfully revalidated post-reboot. **This is not the same as validating a remote/external Opmonitor node topology for the Security Server itself** — that remains `REQUIRES VERIFICATION` per §12; the container was configured for local OPMON throughout, and only the *query* of its data came from a remote client. |
| **Container recreation** (`docker compose up -d --force-recreate`, or removing and re-creating the container) | **New container ID.** `docker logs` history and `/var/log/supervisor` contents are **lost** (§10). Named-volume-backed state (`/etc/xroad`, external PostgreSQL data) **persists** | **PASS**, directly validated (E2-C3): identity, AUTH/SIGN certificates, registration, subsystem, global configuration, token auto-unlock (from the repaired `.env`, no shell override), local OPMON (16 records, no loss), messagelog (36 records, no loss) all confirmed intact across an actual `--force-recreate`, **provided** the named volumes and external database from §8/§10 are used |
| **Host reboot** | Docker daemon restarts; containers with `restart: unless-stopped` restart automatically (existing container, not recreated) | **PASS**, directly validated (E2-C2B): both the Security Server and PostgreSQL containers came back automatically within seconds of the Docker daemon starting, zero manual intervention, `RestartCount: 0`, followed by successful real API exchange and successful remote retrieval/query of operational data from the locally-configured OPMON service post-reboot. **As with the container-restart row above, this validates local OPMON's continued functioning and a remote client's ability to query it — not a remote/external Opmonitor-node topology for the Security Server itself, which remains `REQUIRES VERIFICATION` per §12.** |

**Do not infer persistence across recreation merely because restart or host reboot succeeded** — recreation is a materially different event (new container ID, ephemeral layer discarded) and was separately, explicitly validated in this initiative, not assumed from the restart/reboot results alone.

**Rollback: `REQUIRES VERIFICATION` — not testable in this initiative.** This is the first CamDX container release; no prior published CamDX Security Server image exists to roll back to, so no rollback procedure has been exercised. Do not invent one.

## 19. Logging

**Two mechanisms, both directly evidenced, with different persistence characteristics (see §10, §18):**

- **`docker logs`** — every Supervisor-managed process's stdout is streamed here (`stdout_logfile=/dev/stdout`), tagged by supervisor program name (with the `xroad-confclient` → `[xroad-confclient-service]` naming exception noted in §13). This is the primary, evidenced way to observe runtime behavior. **Persists across restart/reboot, lost on recreation.**
- **`/var/log/supervisor/`** — per-process stderr files (each confirmed present for every managed process) plus `supervisord.log`. **Not volume-mounted — ephemeral, lost on recreation**, same as `docker logs`.

**No Docker log rotation/retention policy is configured by default** — confirmed as an open operational item, classified explicitly as operations hardening, **not** an image defect. Before high-volume production operation, configure Docker's own `log-opts` (`max-size`/`max-file`) or a centralized log-collection solution — no specific vendor or configuration is prescribed here. Capture `docker logs` output before any deliberate recreation if recent history might be needed for an investigation (§10).

## 20. Initial Configuration handoff

**Container deployment complete.**

Do not attempt member/key/certificate/subsystem configuration here — that entire workflow (configuration anchor import, Member Class/Member Code, Member Name verification, Security Server Code, software token/PIN, timestamping service, AUTH/SIGN key generation, CSR submission, certificate import, authentication certificate registration, subsystem registration, and final registration status checks) is owned by [`../initial-configuration.md`](../initial-configuration.md), identically to the Ubuntu and RHEL tracks.

## 21. Differences from native Ubuntu/RHEL — summary

| Area | Native (Ubuntu/RHEL) | Container |
|---|---|---|
| Process supervision | systemd units | Supervisor (`supervisord`) — no systemd |
| Installation model | Package manager (`apt`/`dnf`), host-level | Single pre-built, digest-pinned image |
| Local OPMON | Must explicitly install `xroad-addon-opmonitoring` | Baked in, runs by default from first start |
| Messagelog archiver | Part of the base `xroad-securityserver` dependency set | Baked in, runs by default |
| Admin account creation | Interactive package prompt (Ubuntu) / explicit `xroad-add-admin-user` command (RHEL) | `XROAD_ADMIN_USER`/`XROAD_ADMIN_PASSWORD` environment variables, consumed once at first container init |
| Database | Local PostgreSQL auto-installed as a package dependency (default) or explicit remote-DB package choice | External `postgres:16` container (validated default) or an in-image local-DB path (§11.1, unvalidated) |
| OPMON restart requirement | RHEL: confirmed required after installing OPMON; Ubuntu: unresolved | Not applicable — OPMON is never "installed after the fact" in the container path |
| Client-proxy ports | Stock `8080`/`8443` vs. CamDX-historical `80`/`443` — unresolved policy question | Image exposes `8080`/`8443` (stock) — this is a container-specific fact, not a resolution of the native policy question |

## 22. Items requiring verification

1. **Local-PostgreSQL container path** (§11.1) — supported by the image's own init logic, not independently validated end to end by this initiative (only the external-DB pattern was exercised through recreation/reboot/credential-rotation testing).
2. **Remote/external OPMON for the container path** (§12) — no configuration mechanism found in the entrypoint/supervisor configuration; not documented because it is not evidenced.
3. **Rollback procedure** (§18) — not testable, first container release, no prior image to roll back to.
4. **Docker log rotation/retention** (§19) — not configured by default; classified as operations hardening, not an image defect.
5. **`strict-identifier-checks`, `client-http-port`/`client-https-port`, `health-check-port` (for native installs specifically), `max-records-in-payload`** — the same broader CamDX policy questions open in the Ubuntu/RHEL guides remain open here; container-specific facts (e.g. §14's port exposure) are not used to silently resolve them. See [`../initial-configuration.md`](../initial-configuration.md) §12.
6. **High Availability** — out of scope for this document; no container HA topology was found evidenced.
7. **Minimum Docker/Compose version** — only the validated versions (`28.4.0`/`v2.39.2`) are directly evidenced; no formal minimum is asserted below that.
8. **PostgreSQL image reproducibility** (§11) — `postgres:16` is a mutable tag; the exact image digest/Image ID actually exercised during E2-C validation was never captured in evidence and is not evidenced. This is a deployment-definition reproducibility/hardening gap, not a CamDX Security Server image defect. Pin the official `postgres` image to a specific digest as a hardening step if full artifact immutability is required for this deployment — no specific digest is prescribed here, since none was historically validated.

None of these are guessed at or resolved in this document.

## 23. References

- `evidence/2026-09-11-e2-container-build-assessment.md` through `evidence/2026-09-21-e2-container-ghcr-publication.md` (this initiative, 12 files spanning E2-C1 through E2-C5B) — the full container validation chain: build assessment, HTTPS preflight, Sidecar build validation, pre-/post-reboot runtime validation, deployment-definition readiness (E2-C3), DB-credential readiness (E2-C3A), operations/logging readiness (E2-C4), registry publication preparation, and GHCR publication execution (E2-C5B, CLOSED/PASS/GO).
- Read-only inspection of the frozen, published image itself: `docker image inspect`, and `docker create`/`docker cp` (never `docker run`) to extract `/root/entrypoint.sh`, `/root/_entrypoint_common.sh`, `/etc/supervisor/` (full tree), and `/usr/share/xroad/autologin/` — the authoritative basis for the process/supervision model, persistence paths, and secrets mechanism throughout this document. No container was started to produce this document; no image was rebuilt.
- `~/engineering/camdx-xroad-7.8.2-release/e2c-runtime/{sidecar,postgres}/compose.yaml` and `e2c-runtime/sidecar/.env.example` — the actual validated deployment scaffold; internal validation-specific naming (`camdx-e2c-*`) generalized to canonical names in §8 without changing the underlying architecture.
- `~/engineering/camdx-xroad-7.8.2-release/docs/camdx-7.8.2-sidecar-operations-troubleshooting.md` — the existing operations/troubleshooting runbook referenced by the E2-C4 logging-readiness evidence; consult directly for troubleshooting detail beyond this deployment guide's scope.
- [`../network-requirements.md`](../network-requirements.md), [`../provider-connectivity.md`](../provider-connectivity.md), [`../initial-configuration.md`](../initial-configuration.md), [`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md), [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md).

## 24. Document change history

| Date | Change |
|---|---|
| 2026-09-24 | Initial placeholder draft created as part of the CamDX-Documents 7.8.2 documentation architecture modernization. Documented the validated deployment pattern and explicitly deferred any "publicly available" claim until registry publication completed. |
| 2026-09-25 (round 1) | Full evidence-driven rewrite, following E2-C5B's closure (CLOSED/PASS/GO) — GHCR publication is now complete, superseding the placeholder's deferred pull instructions. Rewritten directly from the E2-C1 through E2-C5B validation evidence, read-only inspection of the frozen published image (`docker image inspect`/`docker create`/`docker cp`, no run, no rebuild), and the actual validated `e2c-runtime` deployment scaffold. Documented: digest-pinned image identity; anonymous public GHCR pull/verification with real evidenced commands; the validated two-service (external PostgreSQL + Security Server) Compose architecture; the exact persistence boundary (`/etc/xroad` named volume vs. ephemeral `docker logs`/`/var/log/supervisor`, directly confirmed by a real recreate test); the external-PostgreSQL-16 database model as the validated default, with the local-DB path documented as image-supported but not end-to-end validated; the container-specific OPMON model (baked-in, always-on local OPMON, no install step, no RHEL-style restart requirement); the full Supervisor process list (not systemd) with the `xroad-confclient` log-tag naming exception; the image's actual declared port set with validated bind/publish decisions (`4000`/`5588` restricted to `127.0.0.1`); the four validated secret environment variables with Compose dotenv single-quoting requirements (sourced from this initiative's own documented `.env` corruption-prevention rule); and a precise restart-vs-recreate-vs-reboot evidence table, each classification backed by a specific validation round. |
| 2026-09-25 (round 2) | Targeted operational correction, following a HOLD gate on round 1's content: (1) fixed the dual-`.env` deployment sequence — `postgres/.env` and `security-server/.env` must both be created and populated **before** any container starts, not partway through; §16 rewritten as an explicit 9-step order with `--env-file` passed on every `docker compose` invocation (deterministic, not dependent on the operator's working directory) and `docker compose ... config -q` (not plain `config`) used to validate variable interpolation without rendering resolved secrets to stdout; §15 now shows both `.env` files separately. (2) Split §17 into §17A (pre-`initial-configuration.md` deployment readiness — does not require the software token to be initialized) and §17B (post-`initial-configuration.md` runtime check — token auto-unlock, `USER_PIN_INCORRECT` absence, registration/certificate persistence) — the prior single checklist incorrectly required token-active state before member configuration exists, a lifecycle contradiction. (3) Searched all E2-C evidence for a captured PostgreSQL image digest from the actual validation rounds — none found; documented `postgres:16` as a mutable tag with the exact historically-exercised artifact **not** evidenced, explicitly not treating a freshly-inspected local `postgres:16` image as proof of the historical digest, and added this as a reproducibility/hardening item (§22) rather than a CamDX Security Server image defect. (4) Restructured §7 into a canonical Docker-only verification path (pull by digest + `docker image inspect`, no extra tools) and an explicitly-labeled optional registry/audit path requiring `curl`/`python3`, which are not otherwise required by this guide. (5) Corrected the `RestartCount` claim — `docker compose ps` does not expose that field; `docker inspect --format '{{.RestartCount}}'` does, and §17A now uses it. (6) Corrected "both local and remote OPMON... confirmed intact" in §18's restart-recreate-reboot table to "local OPMON remained functional and a remote operational-data retrieval... was successfully revalidated," with an explicit note this does not validate a remote/external Opmonitor node topology (§12's own `REQUIRES VERIFICATION` classification for that topology is preserved, not contradicted). (7) Extended the DB credential-rotation procedure (§11) to update **both** `.env` files consistently after a live `ALTER ROLE` rotation, and clarified that the official `postgres` image's own `POSTGRES_PASSWORD` is likewise only a first-initialization variable, not a live-rotation mechanism. (8) Reworded the `5500`/`5577` port table entries (§14) to "Security Server peer / server-to-server traffic," explicitly distinguished from the `8080`/`8443` consumer-information-system client path, to avoid confusing "peer/client" wording. |
| 2026-09-25 (round 3, this round) | Final cleanup, following a HOLD gate on round 2's remaining `--env-file` gaps and two residual wording issues: (1) every remaining secret-bearing `docker compose ... ps` invocation now passes the matching `--env-file` explicitly (§16 step 6's PostgreSQL health check; §17A's Security Server and PostgreSQL status checks) — Compose variable resolution is now deterministic on every executable `docker compose` command in the guide, not merely most of them. (2) Corrected the §7/§2 tool-dependency claim — round 2 said `curl`/`python3` were "not otherwise required anywhere else in this guide," which was inaccurate: §17A's mandatory health-endpoint and Admin UI checks use `curl`. §7 now explicitly classifies `curl` as an operator-side deployment-verification tool (used by both §17A and the optional §7.2 audit path, but never part of the CamDX Security Server container runtime itself) and `python3` as required only for the optional §7.2 path; §2 gained a matching prerequisite bullet. (3) Corrected the last imprecise "remote OPMON query post-reboot" phrase in §18's host-reboot row (round 2 had already fixed the container-restart row but missed this one) — reworded to "successful remote retrieval/query of operational data from the locally-configured OPMON service post-reboot," with the same explicit non-topology clarification already applied to the restart row; searched the full guide and confirmed no remaining sentence implies a validated remote/external Opmonitor-node topology. |
| 2026-09-25 (round 4, this round) | **APPROVED.** Three non-blocking wording cleanups applied post-approval, no architecture/policy change: (1) §8/§16 no longer claim explicit `--env-file` makes the deployment sequence independent of the operator's current working directory — it only removes Compose's own implicit `.env`-discovery ambiguity; §16 now opens with an explicit instruction to run every command from the deployment root containing the `postgres/` and `security-server/` directories. (2) §15's "exactly four secret-bearing values" corrected to state the Security Server container receives four secret-bearing environment variables and the separate PostgreSQL container receives one additional secret-bearing initialization variable (`POSTGRES_PASSWORD`) — five in total across the two-container deployment; the two-`.env`-file model and every credential-rotation rule are unchanged. (3) §17A's pre-configuration `docker logs` check no longer requires a literal zero-`ERROR`/`Exception`-string match (too absolute for a Security Server that has not yet completed member/token/certificate registration, where some expected log messages reference configuration objects that do not exist yet) — replaced with an operationally precise gate: no repeated fatal startup failure, no crash loop, no database-connectivity/migration failure, no unexpected process-termination error. §17B's post-configuration checks are unchanged. |
