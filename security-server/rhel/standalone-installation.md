# CamDX Security Server - RHEL Standalone Installation

**Supported:** RHEL 9, x86_64, CamDX 7.8.2

This document is for a fresh installation onto a new host only. If this is an existing CamDX Security Server, do not use this fresh-install procedure. Contact CamDX for coordinated migration guidance. This document does not cover High Availability; if your organization requires HA, contact CamDX before deployment.

This guide gets a fresh Security Server installed and ready for [Initial Configuration](../initial-configuration.md). It does not configure your member identity, Security Server Code, token, keys, certificates, or registration, that is a separate step, covered there.

## 1. Before you start

- Hardware: 2 vCPU, 4 GB RAM, 100 GB disk, 100 Mbps network.
- Outbound HTTPS access to `repository.camdx.gov.kh`, plus your normal RHEL 9 BaseOS/AppStream repository access for dependency resolution.
- A synchronized system clock (checked in §2).
- CamDX connectivity and firewall rules prepared, see [`../network-requirements.md`](../network-requirements.md).
- Your onboarding information at hand for Initial Configuration (Member Class, Member Code, Security Server Code, Subsystem Code(s), all provided or confirmed by CamDX, not chosen by you).
- A non-`xroad` administrator account will be created during this procedure (§5), before any X-Road service is first started.

## 2. OS, architecture, and time check

```bash
. /etc/os-release
printf '%s\n' "$ID"
printf '%s\n' "$VERSION_ID"
uname -m
```

- `$ID` must be `rhel`.
- `$VERSION_ID` must begin with `9`.
- `uname -m` must print `x86_64`.

Stop if any of these do not match; do not continue on an unsupported release or architecture.

```bash
timedatectl status
```

Confirm `System clock synchronized: yes` and an active NTP/chrony service before proceeding past package installation. If this deployment uses `chrony`:

```bash
chronyc tracking
chronyc sources -v
```

This guide does not specify which NTP server or pool to use; that is your own infrastructure decision.

SELinux: this procedure does not require, and does not instruct, disabling SELinux.

```bash
getenforce
```

Confirm this returns `Enforcing` before proceeding.

## 3. Repository setup

```bash
sudo dnf install -y curl gnupg2
```

### 3.1 Signing key

The RHEL RPM signing key is different from the Ubuntu APT repository key; do not reuse or conflate them. Expected fingerprint: `B88F7428D21393DFAFCFDC3DA2F01162FAA86C16`.

```bash
set -euo pipefail

EXPECTED_FPR="B88F7428D21393DFAFCFDC3DA2F01162FAA86C16"
KEY_URL="https://repository.camdx.gov.kh/repository/camdx-anchors/api/gpg/key/0xFAA86C16-pub.asc"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
install -d -m 0700 "$WORKDIR/gnupg-home"

curl -fsSL "$KEY_URL" -o "$WORKDIR/camdx-rhel-key.asc"

gpg --homedir "$WORKDIR/gnupg-home" --no-default-keyring --batch --quiet \
    --import "$WORKDIR/camdx-rhel-key.asc"

ACTUAL_FPR="$(gpg --homedir "$WORKDIR/gnupg-home" --no-default-keyring --batch \
    --with-colons --list-keys \
  | awk -F: '$1=="fpr"{print $10; exit}')"

if [ "$ACTUAL_FPR" != "$EXPECTED_FPR" ]; then
  echo "CamDX RHEL signing key fingerprint MISMATCH, expected $EXPECTED_FPR, got $ACTUAL_FPR" >&2
  echo "STOP: do not trust or import this key." >&2
  exit 1
fi

echo "CamDX RHEL signing key fingerprint verified: $ACTUAL_FPR"

sudo install -d -m 0755 /etc/pki/rpm-gpg
sudo install -m 0644 "$WORKDIR/camdx-rhel-key.asc" /etc/pki/rpm-gpg/RPM-GPG-KEY-camdx-rhel9

sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-camdx-rhel9
```

### 3.2 EPEL

A package dependency (`crudini`) is not shipped in RHEL 9's BaseOS or AppStream repositories; it is provided by EPEL.

```bash
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
```

### 3.3 CamDX repository

```bash
sudo tee /etc/yum.repos.d/camdx.repo <<'EOF'
[camdx-rhel9]
name=CamDX Security Server repository for RHEL 9
baseurl=https://repository.camdx.gov.kh/repository/camdx-release-rpm/rhel/9/7.8.2
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-camdx-rhel9
metadata_expire=86400
EOF

sudo dnf clean all
sudo dnf makecache
```

## 4. Pre-install check

```bash
dnf info xroad-securityserver
```

The output must show `Version: 7.8.2`, `Release: 2.el9`, from your configured CamDX repository. If the candidate does not resolve to `7.8.2-2.el9`, stop. Check for a stale or conflicting repository entry under `/etc/yum.repos.d/`, correct it, run `sudo dnf clean all && sudo dnf makecache` again, and re-check.

```bash
sudo dnf install --assumeno xroad-database-local xroad-securityserver
```

This prints the full transaction (every package that would be installed, including dependencies) and then aborts without making any change; a nonzero exit code here is expected. If `dnf` instead reports a dependency error before reaching the transaction summary, stop and recheck §3.

## 5. Install

```bash
sudo dnf install xroad-database-local xroad-securityserver
```

Do not install any HA-only component (a dedicated `serverconf` replication cluster, external load balancer) as part of this standalone procedure.

Create the administrator account **before** starting any X-Road service for the first time:

```bash
sudo xroad-add-admin-user camdx-systemadmin
```

(Use any name except `xroad`, which is reserved for the X-Road system user.)

- **If the account does not already exist**, `xroad-add-admin-user` creates it and then runs the standard `passwd` prompt interactively, asking you to set its password on the spot. Run this command from an interactive terminal; the password you set here is what you will use to log into the Admin UI.
- **If the account already exists**, `xroad-add-admin-user` only adds it to the required groups. It does not touch the existing password; log in with whatever password that account already has.

Start the X-Road services:

```bash
sudo systemctl start xroad-base xroad-signer xroad-confclient xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog
```

If you create or add an administrator account after `xroad-proxy-ui-api` is already running, restart it so it picks up the new group membership:

```bash
sudo systemctl restart xroad-proxy-ui-api
```

Local Operational Monitoring (the default, standard standalone configuration):

```bash
sudo dnf install xroad-addon-opmonitoring
sudo systemctl restart xroad-opmonitor
sudo systemctl restart xroad-proxy
```

Both restarts above are required on RHEL for a fresh installation.

If your deployment needs a remote/external Operational Monitoring or a remote/external PostgreSQL topology, contact CamDX before deployment.

## 6. Firewall

RHEL 9 ships with `firewalld` enabled by default. Do not disable it, and do not open these ports to an entire zone. Restrict every rule to this deployment's actual authorized network:

```bash
# Replace <ZONE> and <ADMIN_CIDR>, <AUTHORIZED_PEER_CIDR> with this deployment's
# actual values before running.
#
# <ADMIN_CIDR> is your own organization's approved administration network,
# not a CamDX-published address; set it according to your own internal policy.
#
# <AUTHORIZED_PEER_CIDR> is the peer Security Server address range applicable
# to this deployment; confirm it through your CamDX onboarding/connectivity
# information, not from this guide.

sudo firewall-cmd --zone=<ZONE> \
  --add-rich-rule='rule family="ipv4" source address="<ADMIN_CIDR>" port port="4000" protocol="tcp" accept' \
  --permanent

sudo firewall-cmd --zone=<ZONE> \
  --add-rich-rule='rule family="ipv4" source address="<AUTHORIZED_PEER_CIDR>" port port="5500" protocol="tcp" accept' \
  --permanent

sudo firewall-cmd --zone=<ZONE> \
  --add-rich-rule='rule family="ipv4" source address="<AUTHORIZED_PEER_CIDR>" port port="5577" protocol="tcp" accept' \
  --permanent

sudo firewall-cmd --reload
```

## 7. Verify

```bash
rpm -qa --qf '%{name}\t%{version}-%{release}\n' 'xroad*' | sort
```

Every `xroad*` package should report `7.8.2-2.el9`. If versions are mixed, stop and correct the repository configuration (§3.3/§4) before proceeding.

```bash
systemctl show -p ActiveState -p SubState -p Result --value xroad-base
```

Expect `active`, `exited`, `success`. `xroad-base.service` is a one-shot unit; `active`/`exited` is its correct healthy state, not a failure.

```bash
systemctl is-active xroad-confclient xroad-signer xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog xroad-opmonitor
```

Expect `active` for every unit listed.

```bash
sudo -u postgres pg_isready
```

Expect `accepting connections`, confirming the local PostgreSQL database is up and reachable.

```bash
systemctl --no-pager --failed
```

Expect no X-Road unit in the failed list.

## 8. Admin UI

```text
https://<SECURITY_SERVER_IP_OR_FQDN>:4000
```

Access should be limited to your authorized administration network, see [`../network-requirements.md`](../network-requirements.md).

## 9. Continue

**Installation is complete. Member/CamDX registration is not.**

Continue to [Initial Configuration](../initial-configuration.md) to connect this Security Server to your member identity and complete registration.

## 10. Installation failed?

See [`../troubleshooting/README.md`](../troubleshooting/README.md). Preserve the exact error text/code before contacting CamDX.

## 11. References

- [`../network-requirements.md`](../network-requirements.md), [`../initial-configuration.md`](../initial-configuration.md), [`../troubleshooting/connectivity.md`](../troubleshooting/connectivity.md).
