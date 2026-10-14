# Install CamDX Security Server on Ubuntu

**Supported:** Ubuntu 24.04 LTS, Ubuntu 22.04 LTS, amd64, CamDX 7.8.2

This guide gets a fresh Security Server installed and ready for [Initial Configuration](../initial-configuration.md). It does not configure your member identity, Security Server Code, token, keys, certificates, or registration. That is a separate step, covered there.

## 1. Before you start

- A fresh, supported Ubuntu host (22.04 or 24.04, amd64), not an existing Security Server.
- Root/sudo access.
- The Security Server's FQDN/DNS prepared, if you have one ready.
- A synchronized system clock.
- CamDX connectivity and firewall rules prepared, see [`../network-requirements.md`](../network-requirements.md).
- Your onboarding information at hand for the next step (Member Class, Member Code, Security Server Code, Subsystem Code(s), all provided or confirmed by CamDX, not chosen by you).

## 2. Recommended installation

From a checked-out copy of this repository:

```bash
cd security-server/scripts
sudo ./install-ubuntu.sh
```

The script will:
- confirm this host is a supported platform and architecture;
- refuse to continue if a Security Server is already installed here, or if the host's X-Road package/`/etc/xroad` state is partial or ambiguous;
- ask for (or accept via `--admin-user`) the administrator account to use for the Admin UI. If that account does not already exist, you will be asked to set its OS password interactively (it authenticates through this host's normal PAM login, the same as any other account). If it already exists, it is used as-is and its password is never changed;
- verify the CamDX repository signing key, configure the repository, and confirm both the exact expected package version and that it is actually being offered by the CamDX repository (not a conflicting source) before installing anything;
- install the Security Server with a local database and local Operational Monitoring (CamDX's default path).

Run `./install-ubuntu.sh --help` for all options, or `--preflight` to check readiness without making any changes.

If your environment cannot use the supported installer, contact CamDX before performing a manual installation.

## 3. Verify

```bash
sudo ./camdx-ss-check
```

Expected output ends with:

```text
Summary: PASS=... WARN=0 FAIL=0 SKIP=...

READY FOR INITIAL CONFIGURATION
```

If it instead reports `ACTION REQUIRED`, resolve the listed `FAIL` items before continuing, see [Installation failed?](#6-installation-failed) below.

## 4. Admin UI

```text
https://<SECURITY_SERVER_FQDN_OR_IP>:4000
```

Access should be limited to your authorized administration network, see [`../network-requirements.md`](../network-requirements.md).

## 5. Continue

**Installation is complete. Member/CamDX registration is not.**

Continue to [Initial Configuration](../initial-configuration.md) to connect this Security Server to your member identity and complete registration.

## 6. Installation failed?

See the [Troubleshooting index](../troubleshooting/README.md). Preserve the exact error text/code before contacting CamDX.

## 7. References

- [`../network-requirements.md`](../network-requirements.md), [`../initial-configuration.md`](../initial-configuration.md), [`../troubleshooting/README.md`](../troubleshooting/README.md).
- [`../scripts/install-ubuntu.sh`](../scripts/install-ubuntu.sh), [`../scripts/camdx-ss-check`](../scripts/camdx-ss-check).
