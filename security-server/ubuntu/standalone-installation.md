# CamDX Security Server — Ubuntu Standalone Installation

## Status / scope

**Status: APPROVED / SAFE-EVIDENCED** for repository identity, package version, repository-key identity, and the overall installation flow (sourced from CamDX's validated E2 Jammy/Noble 7.8.2 packaging/canary evidence and this initiative's own independently-verified repository-key fingerprint). Several CamDX-specific configuration values remain **REQUIRES VERIFICATION** — see §18 — and are not silently resolved here.

This document is for a **fresh installation onto a new host only**. It is **not** an in-place upgrade procedure for a Security Server already running an earlier CamDX/X-Road version. Existing Security Servers may run different historical CamDX versions; do not use this guide as an upgrade path — see [`../upgrade/README.md`](../upgrade/README.md). **Member Migration & Release Readiness remains NOT STARTED / GATED** and is not implied ready by anything in this document.

This document does not duplicate content owned elsewhere:
- CamDX infrastructure runtime connectivity (Central Server, Management Security Server, TSA, OCSP, Central Monitoring) → [`../network-requirements.md`](../network-requirements.md)
- API provider endpoint connectivity (e-KYC, e-KYB, OCR, etc.) → [`../provider-connectivity.md`](../provider-connectivity.md)
- Member/anchor/key/certificate/subsystem configuration → [`../initial-configuration.md`](../initial-configuration.md)

## 1. Supported platforms

Two separate, explicitly distinct validated tracks — **do not** use one track's repository configuration for the other:

| Platform | CamDX package version | Repository |
|---|---|---|
| Ubuntu 22.04 LTS "Jammy Jellyfish" | `7.8.2-1.ubuntu22.04` | `camdx-deb-jammy-7.8.2` |
| Ubuntu 24.04 LTS "Noble Numbat" | `7.8.2-1.ubuntu24.04` | `camdx-deb-noble-7.8.2` |

Both repository names are confirmed CamDX Nexus hosted-repository names (verified directly during E2 release-infrastructure validation). **Architecture: `amd64` is the only architecture with direct package evidence** — the frozen 7.8.2 package inventory (28 packages per distribution track) shows every compiled package built as `amd64`, with the remaining packages architecture-independent (`all`); no other CPU architecture appears anywhere in the release evidence, and none is implied supported by this document. Do **not** use `latest`, `current`, `noble-current`, or the Jammy repository for a Noble host (or vice versa) — no authoritative CamDX repository requires or supports that.

## 2. Before you start

- **Hardware:** 2 vCPU, 4 GB RAM, 100 GB disk, 100 Mbps network (sourced from the legacy CamDX guide; not independently re-benchmarked against 7.8.2 load characteristics in this task).
- **Package-repository connectivity:** installing CamDX packages requires **HTTPS access to `repository.camdx.gov.kh`**, plus normal access to the standard Ubuntu package repositories/mirrors for dependency resolution. This is **distinct from CamDX Central Authority runtime connectivity** (Central Server, Management Security Server, TSA, OCSP, Central Monitoring — see [`../network-requirements.md`](../network-requirements.md)). The configuration anchor file itself may be retrieved from the CamDX repository endpoint separately (see [`../initial-configuration.md`](../initial-configuration.md) §3) and does not by itself require Central Authority runtime connectivity to download. However, CamDX runtime connectivity **must** be ready before anchor import/global configuration retrieval, Security Server registration, and later runtime operations in [`../initial-configuration.md`](../initial-configuration.md) — none of that is required merely to configure the apt repository and install packages at this stage.
- **A non-`xroad` administrator account** will be created during this procedure. Do not name it `xroad` — that name is reserved for the X-Road system user.
- **Do not begin this procedure as an in-place upgrade** of an existing Security Server — see "Status / scope" above.

## 3. Information provided by CamDX (onboarding)

CamDX normally supplies or confirms the following during member onboarding/kickoff, before or during installation:

| Field | Source |
|---|---|
| Member Name | Reference identity supplied during onboarding — during X-Road initial configuration, verify the resolved/displayed name matches the expected organization |
| Member Class | Provided by CamDX |
| Member Code | Provided by CamDX |
| Security Server Code | Provided/confirmed by CamDX — distinct from the Member Code, identifies this specific Security Server instance |
| Subsystem Code(s) | Provided/confirmed by CamDX according to the member's specific API/use case |
| Target environment | Development or Production, as confirmed by CamDX for this deployment |

**Use generic placeholders only when illustrating these fields** — do not reproduce real member-specific onboarding values in this document or in any canonical/public documentation. Have this information ready before proceeding to [`../initial-configuration.md`](../initial-configuration.md) (§20 below); the detailed registration/configuration workflow that consumes it is owned by that document, not duplicated here.

## 4. Network and DNS prerequisites

Full CamDX infrastructure connectivity (every authorized IP address, per environment and service) is owned by [`../network-requirements.md`](../network-requirements.md) — **not duplicated here**. All addresses authorized there for the applicable environment must be allowlisted before proceeding to [`../initial-configuration.md`](../initial-configuration.md).

Installation-relevant reminders only:

- **Admin UI:** `TCP 4000`, reachable from the authorized administrator network only.
- **Peer Security Server traffic:** `TCP 5500`/`5577`, as applicable to this deployment's role (see [`../network-requirements.md`](../network-requirements.md) §4/§6).
- **DNS / FQDN:** the Security Server's FQDN must be prepared and resolvable (internally for administrators, externally for peer Security Servers) before the certificate/registration steps in [`../initial-configuration.md`](../initial-configuration.md).
- **NAT / VIP:** if this Security Server sits behind NAT or a VIP, understand which address peers will actually observe before registration — see [`../network-requirements.md`](../network-requirements.md) §5.
- **Time synchronization:** must be healthy (NTP or equivalent) before certificate operations — clock skew affects certificate validity checks.

No FQDN is invented in this document, and no private lab address is reproduced here.

## 5. Provider connectivity (if applicable)

If this member needs to reach a specific API provider (e-KYC, e-KYB, OCR, or another), that endpoint information is owned by [`../provider-connectivity.md`](../provider-connectivity.md) — **not duplicated here** unless there is a specific operational reason to. Consult that document once the Security Server is registered and ready for peer connectivity, per whichever API(s) this member is onboarding for.

## 6. OS / architecture pre-flight

Before touching repository configuration, confirm this host actually matches one of the two supported tracks:

```bash
. /etc/os-release
printf '%s\n' "$VERSION_CODENAME"
dpkg --print-architecture
```

- `VERSION_CODENAME` (sourced from `/etc/os-release`, which is present on every Ubuntu install by default — no extra package such as `lsb-release` is required just to run this check) must be `jammy` or `noble` — any other codename means this guide does not (yet) cover this host; do not proceed by guessing the closest match.
- `dpkg --print-architecture` must print `amd64` — per §1, this is the only architecture with direct 7.8.2 package evidence.

**If either check does not match a supported combination, STOP** — do not continue to repository configuration on an unsupported release/architecture.

## 7. Clean-host prerequisite bootstrap

A fresh Ubuntu host does not necessarily have `curl`, GPG tooling, or a full locale set installed by default. Bootstrap against the **normal Ubuntu repositories** (not yet CamDX's) before touching CamDX repository configuration:

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg locales
```

- `ca-certificates` — required for TLS certificate validation when retrieving the CamDX signing key and packages over HTTPS.
- `curl` — used to retrieve the CamDX signing key (§8).
- `gnupg` — provides the `gpg` tooling used to inspect and dearmor the signing key (§8).
- `locales` — required for the locale generation step below.
- `software-properties-common` is **not** included — nothing in the resulting procedure actually invokes a command that requires it (no `add-apt-repository` is used), so it is not carried forward from the legacy guide merely because it appeared there historically.

This `apt install` is idempotent — safe to re-run on a host that already has some or all of these packages.

```bash
sudo adduser camdx-systemadmin
echo 'LC_ALL=en_US.UTF-8' | sudo tee -a /etc/environment
sudo locale-gen en_US.UTF-8
sudo timedatectl set-timezone Asia/Phnom_Penh
```

This preparation (admin-user creation and locale/timezone setup) is unchanged in mechanics from the legacy CamDX guide and is generic enough to apply identically to both Jammy and Noble — it was not independently re-tested on a fresh Noble host as part of this documentation task and should be confirmed operationally if in doubt.

## 8. Repository-key retrieval and identity verification

**Do not trust the downloaded key based on its retrieval URL alone.** The block below downloads the key, verifies its fingerprint by machine comparison in one deterministic, isolated GPG keyring, and only installs it under `/etc/apt/keyrings/` on an exact match — stopping and exiting nonzero otherwise, with no partial trust and no leftover state.

```bash
set -euo pipefail

EXPECTED_FPR="B387E4CB3C3DE46723AD8E2E13CA752F04194DBF"
KEY_URL="https://repository.camdx.gov.kh/repository/camdx-anchors/api/gpg/key/0x04194DBF-pub.asc"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
install -d -m 0700 "$WORKDIR/gnupg-home"

curl -fsSL "$KEY_URL" -o "$WORKDIR/camdx-apt-key.asc"

gpg --homedir "$WORKDIR/gnupg-home" --no-default-keyring --batch --quiet \
    --import "$WORKDIR/camdx-apt-key.asc"

ACTUAL_FPR="$(gpg --homedir "$WORKDIR/gnupg-home" --no-default-keyring --batch \
    --with-colons --list-keys \
  | awk -F: '$1=="fpr"{print $10; exit}')"

if [ "$ACTUAL_FPR" != "$EXPECTED_FPR" ]; then
  echo "CamDX repository key fingerprint MISMATCH — expected $EXPECTED_FPR, got $ACTUAL_FPR" >&2
  echo "STOP: do not trust, dearmor, or install this key." >&2
  exit 1
fi

echo "CamDX repository key fingerprint verified: $ACTUAL_FPR"

gpg --batch --yes --dearmor \
    -o "$WORKDIR/camdx-archive-keyring.gpg" \
    "$WORKDIR/camdx-apt-key.asc"

sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 \
    "$WORKDIR/camdx-archive-keyring.gpg" \
    /etc/apt/keyrings/camdx-archive-keyring.gpg
```

This block uses a **single** temporary GnuPG home (`$WORKDIR/gnupg-home`, explicitly created with `install -d -m 0700` before `gpg` ever references it — an explicitly specified `--homedir` must exist before use) for both the import and the fingerprint extraction — never your real keyring — and the `trap` ensures the temporary directory (key file, keyring, everything) is removed whether the script succeeds or exits early on a mismatch. The comparison is a machine string comparison of the primary-key fingerprint via `--with-colons` output (the `fpr:` record), not a visual comparison. `gpg` itself is never invoked under `sudo`: dearmoring happens as the normal user into a temporary file inside `$WORKDIR`, and only the final, already-dearmored keyring file is moved into place with `sudo install`, which needs no GPG tooling of its own.

**Expected fingerprint (independently verified, confirmed identity of this exact CamDX APT repository key):**

```
B387E4CB3C3DE46723AD8E2E13CA752F04194DBF
```

This fingerprint was independently verified via an isolated temporary keyring twice in this initiative's history — once during the E2-C1 container-build task (recorded in engineering evidence) and again during this documentation round — both producing an identical result. **This is a different key from the one used to sign CamDX's RHEL 9 RPM packages** (RPM signatures use key ID `AC367CFD31FFE24E`, subkey `464A548B2267196C4F237376AC367CFD31FFE24E` — neither the primary fingerprint nor either subkey of the RPM key matches this APT key). Do not conflate the two; this document verifies only the APT/repository key.

**If the script prints a mismatch and exits, do not proceed.** Re-verify the retrieval URL and escalate rather than working around the check.

**Note on this command's provenance:** the retrieval URL and the fingerprint above are both confirmed, independently-verified CamDX infrastructure. The specific keyring filename `camdx-archive-keyring.gpg` and the `/etc/apt/keyrings/` location follow current Debian/Ubuntu packaging convention for `signed-by=`-based repositories — this exact filename is not itself an authoritative CamDX-mandated convention (no CamDX documentation prescribes one), so treat the filename as illustrative/reasonable, not as a fixed requirement, if CamDX later publishes its own convention.

## 9. Repository source line

**Ubuntu 22.04 Jammy:**
```bash
echo 'deb [arch=all,amd64 signed-by=/etc/apt/keyrings/camdx-archive-keyring.gpg] https://repository.camdx.gov.kh/repository/camdx-deb-jammy-7.8.2 jammy main' \
  | sudo tee /etc/apt/sources.list.d/camdx.list
```

**Ubuntu 24.04 Noble:**
```bash
echo 'deb [arch=all,amd64 signed-by=/etc/apt/keyrings/camdx-archive-keyring.gpg] https://repository.camdx.gov.kh/repository/camdx-deb-noble-7.8.2 noble main' \
  | sudo tee /etc/apt/sources.list.d/camdx.list
```

```bash
sudo apt update
```

**Repository-name provenance:** `camdx-deb-jammy-7.8.2` and `camdx-deb-noble-7.8.2` are confirmed CamDX Nexus hosted-repository names (verified directly during E2 release-infrastructure validation). This is a direct correction of the legacy guide, which pointed at `camdx-deb-jammy-7.4.2` even where it claimed Ubuntu 24.04 support — that cross-release/cross-distribution ambiguity is not reproduced here.

## 10. Candidate-version gate (mandatory, before installation)

**Do not run the install command until this gate passes.**

```bash
apt-cache policy xroad-securityserver
```

The `Candidate:` line must read:

| Platform | Required candidate version |
|---|---|
| Jammy | `7.8.2-1.ubuntu22.04` |
| Noble | `7.8.2-1.ubuntu24.04` |

**If the candidate does not match — STOP. Do not install.** Inspect for a stale or conflicting configuration before proceeding:

```bash
cat /etc/apt/sources.list
ls /etc/apt/sources.list.d/
apt-cache policy xroad-securityserver
```

Look specifically for an old X-Road/CamDX repository line (e.g. a leftover `camdx-deb-jammy-7.4.2` entry, or the wrong track's `.list` file) still present in `/etc/apt/sources.list` or another file under `/etc/apt/sources.list.d/`. Remove or correct it, `sudo apt update` again, and re-run the candidate check before proceeding.

**On explicit version pinning:** every package in the frozen 7.8.2 inventory for a given distribution track shares an identical, uniform version string (confirmed: all 28 Jammy packages at `7.8.2-1.ubuntu22.04`, all 28 Noble packages at `7.8.2-1.ubuntu24.04`), which is *consistent with* `xroad-securityserver=<version>` being a clean, supported way to pin the install. However, this task did not independently inspect the actual `.deb` package `Depends:` field syntax (only a filename/checksum inventory was available, not extracted package metadata) to confirm the meta-package's dependency version constraints support an explicit pin cleanly. **This guide therefore retains the unversioned install command** (§11) and relies on the mandatory candidate-version gate above as the actual safety mechanism, rather than guessing at pinned-install syntax that has not been directly verified.

## 11. Package installation

Only after §6, §8, and §10 all pass:

```bash
sudo apt install xroad-securityserver
```

`xroad-securityserver` is a meta-package; its dependency graph (pulling in the full X-Road service set, and a local PostgreSQL server unless `xroad-database-remote` was installed first, see §13) is inherited from upstream X-Road packaging and was not restructured by CamDX's 7.8.2 rebuild; CamDX's E2 validation confirmed package **content** correctness (branding, PKI classes, no development/`SNAPSHOT` residue) for this dependency set, not a changed install sequence.

During installation, the package interactively prompts for:
- **Admin UI account name** — supply the `camdx-systemadmin` (or equivalent) account created in §7. Because this account already exists (created *before* the package), and the package's own post-install step grants it Admin UI rights as part of this prompt, there is no separate "add user to the X-Road group" step to perform manually, and no risk of adding a user to a group that doesn't exist yet.
- **Database server URL** — local is suggested by default; see §13 for the remote option.
- **Subject DN / subjectAltName** for the Admin UI's and management REST API's self-signed TLS certificate — e.g. `/C=KH/O=<ORGANIZATION>/OU=<UNIT>/CN=<HOSTNAME-OR-FQDN-OR-IP>`.

**Do not** install any HA-only component (a dedicated `serverconf` PostgreSQL cluster, `rsync`-based state replication, an external load balancer) as part of this standalone procedure — those belong to the HA topology only (status: requires verification), not to a standalone deployment.

## 12. Operational Monitoring selection

Operational Monitoring **capability is mandatory** for a CamDX Security Server deployment. For a standalone Ubuntu installation:

- **Default: local Operational Monitoring**, running on this Security Server itself.
- **Supported alternative: remote/external Operational Monitoring.** Remote/external Operational Monitoring uses a dedicated Operational Monitoring node outside the Security Server. Depending on the approved deployment architecture, that node may serve one or more Security Servers. This is a supported architecture, **not** an HA-only special case — but a detailed, evidenced standalone procedure for configuring a Security Server to use a remote/external Opmonitor node (as opposed to the topology currently documented only for the HA case) has not been established. **Status: REQUIRES VERIFICATION.** No configuration is invented here for that path — if this deployment is explicitly designed around remote/external Operational Monitoring, confirm the exact configuration before proceeding rather than following the local-path commands below.

For the normal (local, default) standalone path:

```bash
sudo apt install xroad-addon-opmonitoring
sudo systemctl restart xroad-opmonitor
```

`xroad-addon-proxymonitor` is **not** installed separately here — direct inspection of the frozen `.deb` package's own `Depends:` metadata (both Jammy and Noble tracks, see §15) confirms it is already part of the standard `xroad-securityserver` dependency set, so it is present on this host from §11 onward without a further command. **`xroad-opmonitor` is confirmed, via direct inspection of the frozen `.deb` package's own `Depends:` metadata (both Jammy and Noble tracks), to be a mandatory dependency of `xroad-addon-opmonitoring`** — installing `xroad-addon-opmonitoring` successfully will always pull in `xroad-opmonitor`; no separate install command is needed or provided for it. If `xroad-opmonitor` is nonetheless absent after this sequence, that indicates an inconsistent package/dependency state, not a normal gap to patch — **STOP and inspect** (`apt-cache policy xroad-opmonitor`, `dpkg-query -W xroad-opmonitor`, `apt list --installed | grep xroad`) rather than improvising an installation of a package that should already be present.

**Restart-sequence completeness: `REQUIRES VERIFICATION`.** The sequence above (installing `xroad-addon-opmonitoring`, with `xroad-addon-proxymonitor` already present from the base Security Server installation, then restarting `xroad-opmonitor`) is what the legacy CamDX guide itself documents, and is retained here for that reason. **Whether `xroad-proxy` also needs to be restarted before remote `getSecurityServerOperationalData` functions correctly on a native Ubuntu install has not been evidenced in this task.** A similar restart requirement was directly observed on RHEL — that finding is **specific to RHEL** and is **not** applied here without Ubuntu-specific evidence; no `xroad-proxy` restart is prescribed as a canonical Ubuntu step. After completing the sequence above, verify remote Operational Monitoring functionality directly against this deployment; if it does not work as expected, treat that as a troubleshooting/evidence-collection case (see [`../troubleshooting/connectivity.md`](../troubleshooting/connectivity.md)) rather than applying an unvalidated restart as a standard fix.

Whichever topology applies to this specific deployment should be stated explicitly in this deployment's own records (do not leave it ambiguous which model is in use).

## 13. PostgreSQL / database handling

**Default (standalone) path:** a local PostgreSQL server is installed automatically as an `xroad-securityserver` dependency — no separate `apt install postgresql` step is needed or should be added. This is the CamDX-suggested default (per the package's own installer prompt) and is the path most standalone deployments should use. This guide does **not** state a specific PostgreSQL major version for this path — the local package pulled in follows whatever the `xroad-securityserver` dependency chain resolves to on the target Ubuntu release, and this task found no direct 7.8.2 package evidence establishing a specific version number to document as authoritative; inventing one would not be supported by evidence.

### 13.1 Remote / external PostgreSQL — architectural option, not a validated 7.8.2 procedure

Remote/external PostgreSQL is an architectural option inherited from X-Road/CamDX historical deployments.

**Detailed CamDX 7.8.2 standalone remote-PostgreSQL procedure: REQUIRES VERIFICATION.**

This guide does **not** provide an executable `xroad-database-remote` installation sequence, `/etc/xroad.properties` configuration, or credential-handling commands for this path, because that procedure has not been independently validated against 7.8.2 in this documentation task. It also does not assert that the local `psql` client and remote PostgreSQL server versions must match exactly — that requirement is not reproduced here unless current, authoritative evidence specifically confirms it for 7.8.2. If a remote/external database is required for this deployment, confirm the exact supported procedure and version constraints before proceeding, rather than following an unvalidated copy-paste sequence.

Do **not** copy HA-style replication assumptions (a dedicated separate `serverconf` cluster, streaming replication, `node.ini`) into this section — those are HA-only concerns, out of scope for a standalone deployment, and are not present here regardless.

## 14. Administrator access

The Admin UI account was created and granted rights during package installation (§11). Confirm access:

```
https://<SECURITY_SERVER_IP_OR_FQDN>:4000
```

A connection-refused error for a short period after service start is expected while the Admin UI finishes starting — not a fault. Full Admin UI configuration (member info, anchor, keys, certificates, registration) is covered in [`../initial-configuration.md`](../initial-configuration.md), not here.

## 15. Post-install service checks

```bash
systemctl --no-pager --failed
```
Confirm no X-Road-related unit appears in the failed list.

```bash
sudo systemctl list-units "xroad-*"
```

**Expected units, confirmed directly from the frozen 7.8.2 `.deb` package contents** (read-only inspection of the actual validated build artifacts — `dpkg-deb -c`/`-f` against packages whose SHA-256 checksums were verified to match the frozen release inventory — for **both** the Jammy and Noble tracks; no package was rebuilt, modified, or installed to obtain this):

| Unit | Shipped by package | Confirmed via |
|---|---|---|
| `xroad-base` | `xroad-base` | `.../usr/lib/systemd/system/xroad-base.service` present in the package contents (Noble build artifact) |
| `xroad-confclient` | `xroad-confclient` | `.../usr/lib/systemd/system/xroad-confclient.service` present (Noble build artifact) |
| `xroad-monitor` | `xroad-monitor` | `.../usr/lib/systemd/system/xroad-monitor.service` present (Noble build artifact) |
| `xroad-proxy` | `xroad-proxy` | `.../usr/lib/systemd/system/xroad-proxy.service` present (Noble build artifact) |
| `xroad-proxy-ui-api` | `xroad-proxy-ui-api` | `.../usr/lib/systemd/system/xroad-proxy-ui-api.service` present (Noble build artifact) |
| `xroad-signer` | `xroad-signer` | `.../usr/lib/systemd/system/xroad-signer.service` present (Noble build artifact) |
| `xroad-addon-messagelog` | `xroad-addon-messagelog` | `.../usr/lib/systemd/system/xroad-addon-messagelog.service` present (Noble build artifact) |
| `xroad-opmonitor` | `xroad-opmonitor` | `xroad-opmonitor.service` present in **both** the Jammy and Noble `xroad-opmonitor` package contents (path differs slightly by track — `./lib/systemd/system/` on Jammy vs. `./usr/lib/systemd/system/` on Noble, both standard systemd search paths). **Present only when local Operational Monitoring is installed (§12)** — not part of the base `xroad-securityserver` dependency set (confirmed: `xroad-securityserver`'s own `Depends:` does not include `xroad-opmonitor` or `xroad-addon-opmonitoring` at all). Correctly **omitted from earlier drafts of this guide** — this round corrects that gap with direct package evidence, not inference. |

**`xroad-addon-proxymonitor` ships no systemd unit file at all — confirmed by direct inspection of the package's own file listing, on both the Jammy and Noble `.deb` artifacts** (`dpkg-deb -c xroad-addon-proxymonitor_*.deb` returns zero `.service` entries on either track). Its `Depends:` field (`xroad-proxy, xroad-monitor`) confirms it adds no separate daemon of its own. This is now established directly from the native package contents, not inferred from the separately-observed container behavior (where the same capability was seen registering itself inside the running `xroad-proxy` process) — the two observations are consistent, but this section relies on the native `.deb` evidence as its basis, per this round's review requirement.

**Note on `xroad-securityserver`'s own dependency set:** confirmed via `dpkg-deb -f xroad-securityserver_*.deb Depends`: `xroad-proxy`, `xroad-addon-metaservices`, `xroad-addon-messagelog`, `xroad-addon-proxymonitor`, `xroad-addon-wsdlvalidator`, `xroad-proxy-ui-api` — i.e. `xroad-addon-proxymonitor` **is** always installed as part of a standard `xroad-securityserver` install (consistent with it having no separate unit of its own to track), while Operational Monitoring (`xroad-addon-opmonitoring`/`xroad-opmonitor`) is confirmed **not** part of this base set and must be installed separately, exactly as §12 already documents.

```bash
systemctl status xroad-proxy
```
Use for any individual service needing closer inspection.

## 16. Package/version verification

```bash
dpkg-query -W -f='${Package}\t${Version}\n' 'xroad*' 2>/dev/null | sort
```

Expected version family:

| Platform | Expected version string in every `xroad*` package |
|---|---|
| Jammy | `7.8.2-1.ubuntu22.04` |
| Noble | `7.8.2-1.ubuntu24.04` |

**If mixed or unexpected versions are found — STOP.** Do not proceed to [`../initial-configuration.md`](../initial-configuration.md) with a misaligned package set. Capture the following before making any change:

```bash
apt-cache policy xroad-securityserver
dpkg-query -W -f='${Package}\t${Version}\n' 'xroad*' 2>/dev/null | sort
cat /etc/apt/sources.list
ls /etc/apt/sources.list.d/
systemctl --no-pager --failed
journalctl -u 'xroad-*' --no-pager --since "-1 hour"
```

Correct the repository definition first (§9/§10) and re-run the candidate-version gate. **Do not attempt an automatic reinstall/repair command** (e.g. `apt install --reinstall`) as a presumed fix — that recovery behavior has not been validated for this package set, and reinstalling only the meta-package does not prove the full dependency tree has realigned to the correct version. Because this is a fresh-host procedure with no prior production state to preserve, rebuilding the host from a clean image may be preferable to improvising a package-state repair — this is an operator decision to make deliberately, not an automatic step this guide prescribes. Any explicit downgrade/reinstall/recovery procedure should be separately validated before being published as a standard step.

## 17. CamDX-specific settings — do not apply unresolved values automatically

The following remain **CamDX policy questions**, not settled by this document — see [`../initial-configuration.md`](../initial-configuration.md) §12 for the full classification table and reasoning. Do **not** turn any of these into an unconditional required command here merely because a historical CamDX value exists:

| Setting | Upstream default | CamDX legacy documented value | Status |
|---|---|---|---|
| `strict-identifier-checks` | `true` (fresh installs, X-Road 7.3 onward) | `false` | REQUIRES VERIFICATION |
| `client-http-port` | `8080` | `80` | REQUIRES VERIFICATION |
| `client-https-port` | `8443` | `443` | REQUIRES VERIFICATION |
| `health-check-port` | `0` (disabled) | `5588` (validated only in the container/Sidecar deployment) | REQUIRES VERIFICATION for native installs |
| `max-records-in-payload` | `10000` | `30000` (legacy CamDX override; legacy key spelling `max-records-in-playload` was a documentation typo) | REQUIRES VERIFICATION |

`message-body-logging = false` is the one setting in this group classified **REQUIRED BY CAMDX** in [`../initial-configuration.md`](../initial-configuration.md) §12 — consistently applied across every legacy CamDX guide reviewed, with no internal inconsistency found. It may be applied as a standard step for this Ubuntu track on that basis. All other settings in the table above should be confirmed against current CamDX policy before being applied as a default for new 7.8.2 installations — see [`../initial-configuration.md`](../initial-configuration.md) §12 for the exact reasoning behind each.

## 18. Items requiring verification

Collected from throughout this document, in one place:

1. **Repository signing-key filename/path convention** (§8) — the retrieval URL and fingerprint are confirmed; the exact keyring filename convention is a reasonable current-Debian-practice choice, not an independently confirmed CamDX standard.
2. **`xroad-securityserver=<version>` pinned-install syntax** (§10) — plausible given uniform version strings across the package set, but not confirmed against actual `Depends:` metadata; unversioned install retained instead.
3. **`strict-identifier-checks`** CamDX policy for 7.8.2 fresh installs (§17).
4. **`client-http-port`/`client-https-port`** — which value CamDX 7.8.2 native installs should standardize on (§17).
5. **`health-check-port`** for native installs (§17).
6. **`max-records-in-payload`** CamDX override value for 7.8.2 (§17).
7. **Local OPMON restart sequence completeness** (§12) — whether `xroad-proxy` also requires a restart for remote Operational Monitoring to function on native Ubuntu; not evidenced either way, and the RHEL finding is explicitly not transferred.
8. **Remote/external Operational Monitoring** — detailed standalone (non-HA) implementation procedure (§12).
9. **Local PostgreSQL major version** actually pulled in on a fresh Jammy/Noble 7.8.2 install (§13).
10. **Remote/external PostgreSQL** — no executable procedure provided pending 7.8.2-specific validation (§13.1).
11. **Package-state recovery/reinstall procedure** (§16) — no validated automatic repair step exists; treated as an operator decision, not prescribed.

None of these are guessed at or resolved in this document.

## 19. Reboot validation — two distinct checkpoints

Both the Jammy and Noble 7.8.2 tracks have been validated to include full OS reboot recovery — but this covers two distinct levels of state, and this guide only speaks to the first:

- **Package-install-level check (in scope for this document):** after completing §6–§16, services should start correctly and survive a restart at the package/service level. A reboot at this stage mainly verifies service auto-start and persistent package/configuration state.
- **Full deployment-level reboot validation (out of scope for this document, belongs after [`../initial-configuration.md`](../initial-configuration.md)):** confirming that Security Server *identity*, certificates, registration, subsystem status, and Operational Monitoring state all persist correctly through a reboot is only meaningful once those things exist — i.e. after completing [`../initial-configuration.md`](../initial-configuration.md), not from this package-installation guide alone. Perform the full reboot validation there, not here.

Do not treat a reboot performed immediately after this document's steps as having validated identity/certificate/registration/OPMON persistence — it has not, because none of that state exists yet at this stage.

## 20. Proceed to Common Initial Configuration

**Ubuntu package installation complete.**

Do not attempt member/key/certificate/subsystem configuration here — that entire workflow (configuration anchor import, Member Class/Member Code, Member Name verification, Security Server Code, software token/PIN, timestamping service, AUTH/SIGN key generation, CSR submission, certificate import, authentication certificate registration, subsystem registration, and final registration status checks) is owned by [`../initial-configuration.md`](../initial-configuration.md).

## 21. Validation checklist

Before proceeding to [`../initial-configuration.md`](../initial-configuration.md), confirm:

- [ ] OS/architecture pre-flight passed (`jammy`/`noble` + `amd64`) — §6
- [ ] Repository-key fingerprint independently verified before install — §8
- [ ] Correct CamDX repository is configured for this release, not the other track's — §9
- [ ] Candidate-version gate passed *before* installation — §10
- [ ] `dpkg-query` shows every `xroad*` package aligned to the expected 7.8.2 version string, no mixed versions — §16
- [ ] PostgreSQL (local default, per §13) is healthy and reachable
- [ ] `systemctl --no-pager --failed` shows no X-Road-related failures — §15
- [ ] All expected `xroad-*` services are `active`/`running`, per the evidenced list in §15 — §15
- [ ] Admin UI is reachable on `TCP 4000` from the authorized administrator network — §14
- [ ] Operational Monitoring topology (local or remote/external) is explicitly identified for this deployment — §12
- [ ] If using the local/default OPMON path, `xroad-opmonitor` and related add-ons are installed and running — §12
- [ ] CamDX infrastructure connectivity (per [`../network-requirements.md`](../network-requirements.md)) is confirmed available from this host
- [ ] Ready to proceed to [`../initial-configuration.md`](../initial-configuration.md)

**Do not claim** member registration PASS, certificate registration PASS, real API exchange PASS, or full deployment-level reboot recovery at this stage — those are outcomes of the *later* configuration steps in [`../initial-configuration.md`](../initial-configuration.md) and the full reboot checkpoint in §19, not of package installation alone.

## 22. Troubleshooting

For connectivity problems after installation, see [`../troubleshooting/connectivity.md`](../troubleshooting/connectivity.md). For a mixed-version or failed-install condition, see §16 — capture diagnostics, correct the repository definition, and treat host rebuild as a deliberate operator decision rather than following an unvalidated automatic repair command.

## 23. References

- Legacy source: `standalone_security_server_installation_and_configuration.md` (this repository, `main` branch) — used for still-applicable procedural mechanics only; its `X-Road 7.4.2` baseline, `camdx-deb-jammy-7.4.2` repository reference, and `apt-key`-based signing are explicitly **not** carried forward.
- CamDX E2 7.8.2 Debian packaging and canary-validation evidence (internal engineering record; `camdx-deb-jammy-7.8.2`/`camdx-deb-noble-7.8.2`, `7.8.2-1.ubuntu22.04`/`7.8.2-1.ubuntu24.04`, 28-package inventory per track).
- CamDX APT repository-key fingerprint, independently verified via isolated temporary keyring (this task and the earlier E2-C1 container-build task, identical result).
- Read-only inspection of the frozen 7.8.2 `.deb` package contents (both Jammy and Noble, checksums verified against the release inventory) — the authoritative basis for the native systemd unit list in §15. This initiative's container-runtime service-set observations (E2-C1 through E2-C5B) remain available only as supplemental, corroborating runtime evidence, not as the basis for any native-packaging claim.
- [`../network-requirements.md`](../network-requirements.md), [`../provider-connectivity.md`](../provider-connectivity.md), [`../initial-configuration.md`](../initial-configuration.md), [`../troubleshooting/connectivity.md`](../troubleshooting/connectivity.md), [`../upgrade/README.md`](../upgrade/README.md).

## 24. Document change history

| Date | Change |
|---|---|
| 2026-09-24 (round 1) | Initial draft created, replacing the legacy guide's ambiguous cross-release/cross-distribution repository reference with two explicitly separate Jammy/Noble tracks; Central Authority IP tables moved to `network-requirements.md`. |
| 2026-09-24 (round 2) | Full modernization pass: restructured to an operator-friendly layout; replaced deprecated `apt-key` with a `signed-by=`-based keyring approach; added onboarding-information, provider-connectivity-pointer, PostgreSQL-model, and Operational Monitoring sections; added package/version verification and a validation checklist. |
| 2026-09-24 (round 3) | Targeted operational correction: added a clean-host prerequisite bootstrap (§7); added mandatory repository-key fingerprint verification against an independently-confirmed value, distinguished explicitly from the separate RHEL signing key (§8); added an OS/architecture pre-flight gate (§6); clarified package-repository vs. CamDX runtime connectivity (§2); added a mandatory pre-install candidate-version gate via `apt-cache policy` (§10), with an explicit, evidence-based decision not to use version-pinned install syntax; downgraded the remote-PostgreSQL subsection to a non-executable REQUIRES VERIFICATION note, removing unvalidated copy-paste commands and the unevidenced psql-version-match assertion (§13.1); derived the exact native systemd unit list from recorded evidence, correcting the prior omission of `xroad-opmonitor` and explicitly excluding `xroad-addon-proxymonitor` as its own unit based on direct container-log evidence (§15); added an explicit, unresolved caveat on whether `xroad-proxy` needs an additional restart for remote OPMON, without transferring the separately-observed RHEL finding (§12); removed the unvalidated `apt install --reinstall` recovery recommendation, replaced with a capture-diagnostics-first, no-automatic-repair approach (§16); split reboot validation into a package-level checkpoint (in scope here) and a full deployment-level checkpoint (explicitly deferred to after `initial-configuration.md`) (§19). All previously-open CamDX policy items (`strict-identifier-checks`, client-proxy ports, `health-check-port`, `max-records-in-payload`) remain REQUIRES VERIFICATION, unresolved by this round. |
| 2026-09-24 (round 4) | Final technical cleanup: (1) rewrote the GPG fingerprint verification block (§8) as one deterministic script using a single temporary GnuPG home, machine comparison of the `--with-colons` `fpr:` record, and an explicit exit/STOP on mismatch — the prior version used two separate `$(mktemp -d)` invocations and so never actually compared the imported key; (2) re-derived the native systemd unit inventory (§15) from **direct read-only inspection of the frozen `.deb` package contents** (both Jammy and Noble, checksums verified against the release inventory first) rather than container-process inference — confirmed every core unit's `.service` file directly, confirmed `xroad-opmonitor.service` is shipped by the `xroad-opmonitor` package on both tracks, and confirmed `xroad-addon-proxymonitor` ships no systemd unit on either track (previously stated on container-log inference alone); (3) removed the `sudo apt install xroad-opmonitor` fallback (§12) — package `Depends:` metadata, now directly inspected, proves `xroad-addon-opmonitoring` always pulls in `xroad-opmonitor`, so no fallback is needed; replaced with a STOP-and-inspect instruction for the (should-be-impossible) case of it being absent; removed the `sudo systemctl restart xroad-proxy` troubleshooting suggestion (§12) — no Ubuntu evidence supports it, and the RHEL finding remains explicitly RHEL-specific; restart-sequence completeness reclassified `REQUIRES VERIFICATION`; (4) reworded the package-repository-vs-CamDX-runtime-connectivity note (§2) to state CamDX runtime connectivity must be ready before anchor import/global configuration retrieval, registration, and later runtime operations, rather than "anchor download" — the anchor file's own retrieval from the CamDX repository endpoint does not itself require that connectivity. |
| 2026-09-24 (round 5) | Two command fixes plus follow-on cleanup: (1) fixed the GPG verification block (§8) — the round-4 script referenced `"$WORKDIR/gnupg-home"` as an explicit `--homedir` without ever creating that directory; added `install -d -m 0700 "$WORKDIR/gnupg-home"` immediately after `WORKDIR` creation, and restructured the dearmor/install step so `gpg` is never invoked under `sudo` (dearmor runs as the normal user into `$WORKDIR`, then `sudo install -m 0644` places the finished file under `/etc/apt/keyrings/`); fingerprint, single-homedir property, STOP-on-mismatch, and trap cleanup all unchanged; (2) replaced the `lsb_release -cs` OS pre-flight check (§6) with `. /etc/os-release` + `printf '%s\n' "$VERSION_CODENAME"`, since a minimal/clean Ubuntu host is not guaranteed to have `lsb_release` installed and `/etc/os-release` requires no additional package; `jammy`/`noble` + `amd64` requirement unchanged; (3) reworded the remote/external Operational Monitoring description (§12) to avoid implying it is necessarily a "dedicated, shared" node — now states it uses a dedicated node outside the Security Server that, depending on the approved architecture, may serve one or more Security Servers; MANDATORY/local-default/remote-supported/not-HA-only policy unchanged; (4) reworded the References entry (§23) that could be read as attributing the native systemd unit list to container-runtime observations — it now cites the frozen `.deb` package contents as the authoritative basis, with container observations named explicitly as supplemental/corroborating only, consistent with round 4's actual evidence in §15; (5) simplified the local-OPMON install sequence (§12) — since `xroad-addon-proxymonitor` is confirmed (via direct `Depends:` inspection, §15) to already be part of the standard `xroad-securityserver` dependency set, the redundant `sudo apt install xroad-addon-proxymonitor` step was removed, leaving `sudo apt install xroad-addon-opmonitoring` + `sudo systemctl restart xroad-opmonitor`, with explanatory text added; the separate open question of whether `xroad-proxy` also needs a restart was **not** touched and remains `REQUIRES VERIFICATION`, with no Ubuntu `xroad-proxy` restart command prescribed. |
| 2026-09-25 (round 6, this round) | Final non-blocking wording cleanup, applied after ChatGPT/operator **APPROVAL** of this document: the restart-sequence paragraph (§12) still referred to "installing both add-ons, then restarting only `xroad-opmonitor`" — stale wording left over from before round 5 dropped the separate `xroad-addon-proxymonitor` install step. Reworded to "installing `xroad-addon-opmonitoring`, with `xroad-addon-proxymonitor` already present from the base Security Server installation, then restarting `xroad-opmonitor`," consistent with §12's own command block and its supporting `Depends:` evidence. No other content changed. |
