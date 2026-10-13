# Install CamDX Security Server on Ubuntu

**Supported:** Ubuntu 24.04 LTS, Ubuntu 22.04 LTS, amd64 — CamDX 7.8.2

This guide gets a fresh Security Server installed and ready for [Initial Configuration](../initial-configuration.md). It does not configure your member identity, Security Server Code, token, keys, certificates, or registration — that is a separate step, covered there.

## 1. Before you start

- A fresh, supported Ubuntu host (22.04 or 24.04, amd64) — not an existing Security Server.
- Root/sudo access.
- The Security Server's FQDN/DNS prepared, if you have one ready.
- A synchronized system clock.
- CamDX connectivity and firewall rules prepared — see [`../network-requirements.md`](../network-requirements.md).
- Your onboarding information at hand for the next step (Member Class, Member Code, Security Server Code, Subsystem Code(s) — all provided or confirmed by CamDX, not chosen by you).

## 2. Recommended installation

From a checked-out copy of this repository:

```bash
cd security-server/scripts
sudo ./install-ubuntu.sh
```

The script will:
- confirm this host is a supported platform and architecture;
- refuse to continue if a Security Server is already installed here, or if the host's X-Road package/`/etc/xroad` state is partial or ambiguous;
- ask for (or accept via `--admin-user`) the administrator account to use for the Admin UI — if that account does not already exist, you will be asked to set its OS password interactively (it authenticates through this host's normal PAM login, the same as any other account); if it already exists, it is used as-is and its password is never changed;
- verify the CamDX repository signing key, configure the repository, and confirm both the exact expected package version and that it is actually being offered by the CamDX repository (not a conflicting source) before installing anything;
- install the Security Server with a local database and local Operational Monitoring (CamDX's default path).

Run `./install-ubuntu.sh --help` for all options, or `--preflight` to check readiness without making any changes.

## 3. Verify

```bash
sudo ./camdx-ss-check
```

Expected output ends with:

```text
Summary: PASS=... WARN=0 FAIL=0 SKIP=...

READY FOR INITIAL CONFIGURATION
```

If it instead reports `ACTION REQUIRED`, resolve the listed `FAIL` items before continuing — see [Installation failed?](#6-installation-failed) below.

## 4. Admin UI

```text
https://<SECURITY_SERVER_FQDN_OR_IP>:4000
```

Access should be limited to your authorized administration network — see [`../network-requirements.md`](../network-requirements.md) for the full connectivity matrix.

## 5. Continue

**Installation is complete. Member/CamDX registration is not.**

Continue to [Initial Configuration](../initial-configuration.md) to connect this Security Server to your member identity and complete registration.

## 6. Installation failed?

See the [Troubleshooting index](../troubleshooting/README.md). Preserve the exact error text/code before contacting CamDX.

## 7. Advanced / manual installation

Use this section if you need to install without the script, or want to understand each step it automates. This is the secondary path — prefer §2 above for a normal installation.

### 7.1 Supported platforms

| Platform | CamDX package version | Repository |
|---|---|---|
| Ubuntu 22.04 LTS "Jammy Jellyfish" | `7.8.2-1.ubuntu22.04` | `camdx-deb-jammy-7.8.2` |
| Ubuntu 24.04 LTS "Noble Numbat" | `7.8.2-1.ubuntu24.04` | `camdx-deb-noble-7.8.2` |

`amd64` is the only supported architecture. Do not use one track's repository for the other platform.

### 7.2 OS / architecture pre-flight

```bash
. /etc/os-release
printf '%s\n' "$VERSION_CODENAME"
dpkg --print-architecture
```

`VERSION_CODENAME` must be `jammy` or `noble`; architecture must be `amd64`. Stop if either does not match — do not proceed by guessing the closest match.

### 7.3 Clean-host prerequisites

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg locales
```

Create your administrator account now, before installing the Security Server package — the package's own setup grants this account Admin UI rights during installation:

```bash
sudo adduser camdx-systemadmin
```

(Use any name except `xroad`, which is reserved for the X-Road system user.)

### 7.4 Repository signing key

Verify the key's fingerprint before trusting it — do not skip this step:

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

gpg --batch --yes --dearmor \
    -o "$WORKDIR/camdx-archive-keyring.gpg" \
    "$WORKDIR/camdx-apt-key.asc"

sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 \
    "$WORKDIR/camdx-archive-keyring.gpg" \
    /etc/apt/keyrings/camdx-archive-keyring.gpg
```

Expected fingerprint: `B387E4CB3C3DE46723AD8E2E13CA752F04194DBF`. This is a different key from the one signing CamDX's RHEL RPM packages — do not conflate the two.

### 7.5 Repository configuration

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

### 7.6 Candidate-version gate — mandatory before installing

```bash
apt-cache policy xroad-securityserver
```

`Candidate:` must read exactly `7.8.2-1.ubuntu22.04` (Jammy) or `7.8.2-1.ubuntu24.04` (Noble). **If it does not match, stop** — check for a stale or conflicting repository entry in `/etc/apt/sources.list` or `/etc/apt/sources.list.d/`, correct it, `apt update` again, and re-check before installing.

The recommended `install-ubuntu.sh` script (§2) goes one step further than this: it also confirms that the matching candidate version is actually being offered by the expected CamDX repository itself — not just that *some* source produces the right version string — and fails closed if a second, competing source creates ambiguity. This manual path does not automate that check; after confirming the `Candidate:` version above, also look at the indented source line(s) listed under it in the same `apt-cache policy` output and confirm it names the expected `camdx-deb-jammy-7.8.2`/`camdx-deb-noble-7.8.2` repository for your platform, with no other source also offering that version.

### 7.7 Package installation

```bash
sudo apt install xroad-securityserver xroad-database-local
```

`xroad-securityserver` is a meta-package that pulls in the full Security Server service set. `xroad-database-local` selects the local-PostgreSQL path explicitly — the normal, default choice for a standalone deployment. (A remote/external database is an architectural option that exists but is not covered by this guide — confirm the exact supported procedure with CamDX before using it.)

During installation you will be asked for:
- **The administrator account** created in §7.3 — must already exist.
- **The database connection string** — accept the suggested local default.
- **TLS certificate subject information** for the internal service certificate and, separately, for the Admin UI/REST API certificate — a sensible default based on this host's own hostname and IP addresses is offered; override it if you already know this Security Server's public FQDN.

**Do not** install any HA-only component (a dedicated `serverconf` replication cluster, state-sync tooling, an external load balancer) as part of this standalone procedure — those belong to a different deployment model; see [`../deployment-models.md`](../deployment-models.md).

### 7.8 Local Operational Monitoring

Operational Monitoring capability is mandatory for every CamDX Security Server. The default is local monitoring, on this Security Server itself:

```bash
sudo apt install xroad-addon-opmonitoring
```

This single command is sufficient — it pulls in `xroad-opmonitor` as a dependency, and the package's own setup restarts the proxy service automatically; no separate manual restart command is needed.

If this deployment is specifically designed around remote/external Operational Monitoring instead of the local default, **contact CamDX** for the applicable configuration — it is a supported alternative architecture, but this guide's automated local-path commands do not apply to it.

### 7.9 Post-install checks

```bash
systemctl --no-pager --failed
sudo systemctl list-units "xroad-*"
dpkg-query -W -f='${Package}\t${Version}\n' 'xroad*' 2>/dev/null | sort
```

Confirm no X-Road unit appears in the failed list, and every `xroad*` package reports the same version (`7.8.2-1.ubuntu22.04` or `7.8.2-1.ubuntu24.04`, matching your platform). If versions are mixed or mismatched, correct the repository configuration (§7.5–§7.6) rather than attempting an automatic reinstall/repair.

### 7.10 CamDX-specific settings

A small number of settings (`strict-identifier-checks`, `client-http-port`/`client-https-port`, `health-check-port`, `max-records-in-payload`) remain open CamDX policy questions for native installs and are intentionally not set by this guide or the installer — see [`../initial-configuration.md`](../initial-configuration.md) for the current status of each. `message-body-logging = false` is the one setting in this group CamDX requires consistently; see the same document.

### 7.11 Validation checklist

Before proceeding to [Initial Configuration](../initial-configuration.md), confirm:

- [ ] OS/architecture pre-flight passed
- [ ] Repository-key fingerprint verified before install
- [ ] Correct CamDX repository configured for this platform
- [ ] Candidate-version gate passed before installing
- [ ] Every `xroad*` package reports the expected version, no mixed versions
- [ ] Local PostgreSQL is healthy and reachable
- [ ] No X-Road service is in a failed state; all expected services are running
- [ ] Admin UI reachable on `TCP 4000` from the authorized administration network
- [ ] Local Operational Monitoring installed and running (or remote/external topology explicitly confirmed with CamDX)
- [ ] CamDX infrastructure connectivity confirmed available from this host — see [`../network-requirements.md`](../network-requirements.md)

### 7.12 Not covered by this guide

- **Remote/external PostgreSQL** — architectural option, contact CamDX for the supported procedure.
- **Remote/external Operational Monitoring** — supported alternative, contact CamDX for the applicable configuration.
- **High Availability** — out of scope here; contact CamDX before planning a new HA deployment. See [`../README.md`](../README.md#high-availability).
- **Upgrading an existing Security Server** — not this guide; see [`../upgrade/README.md`](../upgrade/README.md).

## 8. References

- [`../network-requirements.md`](../network-requirements.md), [`../provider-connectivity.md`](../provider-connectivity.md), [`../initial-configuration.md`](../initial-configuration.md), [`../troubleshooting/README.md`](../troubleshooting/README.md), [`../upgrade/README.md`](../upgrade/README.md).
- [`../scripts/install-ubuntu.sh`](../scripts/install-ubuntu.sh), [`../scripts/camdx-ss-check`](../scripts/camdx-ss-check).
