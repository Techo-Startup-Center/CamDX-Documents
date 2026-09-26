# CamDX Security Server — RHEL Standalone Installation

## Status / scope

**Status: APPROVED / SAFE-EVIDENCED** for package identity, dependency graph, native systemd units, repository configuration, and the overall installation flow — derived directly from read-only inspection of the frozen, checksum-verified `7.8.2-2.el9` RPM artifacts, from the RHEL 9.8 signed production canary evidence (`~/TI-Director-Brain/initiatives/camdx-xroad-upgrade/evidence/2026-09-11-e2-rhel9-final-release-validation.md`, `.../2026-09-09-e2-rhel9-packaging-findings-and-r2-fix.md`), and from direct operator evidence captured on the validated RHEL 9.8 host (its actual `/etc/yum.repos.d/camdx-rhel9-r2-canary.repo` configuration, a live-confirmed `HTTP 200` against the public production repository's `repomd.xml`, and a live-retrieved and fingerprint-matched signing key). **The public repository `baseurl` and the RHEL signing-key retrieval URL are now CONFIRMED — see §9/§11.** Several other items remain **REQUIRES VERIFICATION** — see §27 — and are not silently resolved here.

This document is for a **fresh installation onto a new host only**. It is **not** an in-place upgrade procedure for a Security Server already running an earlier CamDX/X-Road version. Existing Security Servers may run different historical CamDX versions; do not use this guide as an upgrade path — see [`../upgrade/README.md`](../upgrade/README.md). **Member Migration & Release Readiness remains NOT STARTED / GATED** and is not implied ready by anything in this document. This document does **not** cover High Availability — HA remains **REQUIRES VERIFICATION**, and 7.8.2 does not inherit HA validation from standalone package validation.

This document does not duplicate content owned elsewhere:
- CamDX infrastructure runtime connectivity (Central Server, Management Security Server, TSA, OCSP, Central Monitoring) → [`../network-requirements.md`](../network-requirements.md)
- API provider endpoint connectivity (e-KYC, e-KYB, OCR, etc.) → [`../provider-connectivity.md`](../provider-connectivity.md)
- Member/anchor/key/certificate/subsystem configuration → [`../initial-configuration.md`](../initial-configuration.md)

## 1. Supported platform

| Platform | CamDX package version | Public repository (group) | Path |
|---|---|---|---|
| RHEL 9, x86_64 | `7.8.2-2.el9` | `camdx-release-rpm` | `/rhel/9/7.8.2` |

**Architecture: `x86_64` only.** All 12 compiled (`x86_64`) and 7 architecture-independent (`noarch`) packages in the frozen 19-package inventory were built for `x86_64`; no other CPU architecture appears anywhere in the release evidence, and `aarch64` (or any other architecture) is **not** claimed supported by this document.

**Validation boundary — read this before assuming "RHEL 9" means "any RHEL 9.x minor is validated":**

```text
Packages are built for the EL9 platform family (dist tag: .el9, not pinned to a minor
version — the standard RHEL/Fedora convention for "targets the RHEL 9.x major release").

Direct end-to-end runtime validation (fresh dnf install, SELinux Enforcing, all services,
real API exchange, full OS reboot recovery) exists SPECIFICALLY for:
  RHEL 9.8 x86_64

Other RHEL 9.x minors: NOT independently validated by this initiative. The .el9 build tag
is not, by itself, a compatibility guarantee across every minor version — it only states
the platform family this build targets.
```

Treat RHEL 9.8 as the validated reference point for any GO/production decision. Do not cite the `.el9` package tag alone as evidence that a different RHEL 9.x minor has been validated.

## 2. Before you start

- **Hardware:** 2 vCPU, 4 GB RAM, 100 GB disk, 100 Mbps network (sourced from the legacy CamDX guide; not independently re-benchmarked against 7.8.2 load characteristics in this task).
- **Package-repository connectivity:** installing CamDX packages requires outbound HTTPS access to `repository.camdx.gov.kh`, plus normal access to whatever RHEL 9 repositories (BaseOS/AppStream, EPEL — see §10) are configured for dependency resolution. This is **distinct from CamDX Central Authority runtime connectivity** (Central Server, Management Security Server, TSA, OCSP, Central Monitoring — see [`../network-requirements.md`](../network-requirements.md)). The configuration anchor file itself may be retrieved from the CamDX repository endpoint separately (see [`../initial-configuration.md`](../initial-configuration.md) §3) and does not by itself require Central Authority runtime connectivity to download. However, CamDX runtime connectivity **must** be ready before anchor import/global configuration retrieval, Security Server registration, and later runtime operations in [`../initial-configuration.md`](../initial-configuration.md) — none of that is required merely to configure the repository and install packages at this stage.
- **Time synchronization must be healthy before you proceed past package installation** — see §4 and the pre-flight check there; do not proceed to certificate/registration work with an unsynchronized clock.
- **A non-`xroad` administrator account** will be created during this procedure via an explicit RHEL-specific command (§15), run **before** X-Road services are first started — contrast with the Ubuntu guide's interactive package-installer prompt for the same purpose. Do not name it `xroad` — that name is reserved for the X-Road system user.
- **Do not begin this procedure as an in-place upgrade** of an existing Security Server — see "Status / scope" above.

## 3. Information provided by CamDX (onboarding)

Identical to the Ubuntu guide's §3 — CamDX supplies or confirms Member Name, Member Class, Member Code, Security Server Code (provided/confirmed by CamDX, distinct from the Member Code), Subsystem Code(s), and target environment during onboarding. **Use generic placeholders only when illustrating these fields** — do not reproduce real member-specific onboarding values in this document or in any canonical/public documentation. Have this information ready before proceeding to [`../initial-configuration.md`](../initial-configuration.md).

## 4. Network and DNS prerequisites

Full CamDX infrastructure connectivity (every authorized IP address, per environment and service) is owned by [`../network-requirements.md`](../network-requirements.md) — **not duplicated here**. All addresses authorized there for the applicable environment must be allowlisted before proceeding to [`../initial-configuration.md`](../initial-configuration.md).

Installation-relevant reminders only:

- **Admin UI:** `TCP 4000`, reachable from the authorized administrator network only.
- **Peer Security Server traffic:** `TCP 5500`/`5577`, as applicable to this deployment's role (see [`../network-requirements.md`](../network-requirements.md) §4/§6).
- **DNS / FQDN:** the Security Server's FQDN must be prepared and resolvable before the certificate/registration steps in [`../initial-configuration.md`](../initial-configuration.md).
- **Time synchronization:** must be healthy (NTP or equivalent) before certificate operations — clock skew affects certificate validity checks.

**Time synchronization pre-flight check — required before proceeding to [`../initial-configuration.md`](../initial-configuration.md).** A direct operator observation on the validated RHEL 9.8 host found `timedatectl status` reporting `System clock synchronized: no` and `NTP service: inactive`, with Subscription Manager separately reporting roughly 14 seconds of clock skew — `chronyc tracking`/`chronyc sources` on that host returned `506 Cannot talk to daemon` (no active time-sync daemon running). **This is a real operational finding, not a release-package defect** — it does not reopen any part of the accepted RHEL package validation, and package installation itself does not fail because of clock state. It is recorded here because it directly demonstrates why this prerequisite needs an explicit check rather than a bare assertion:

```bash
timedatectl status
```

Confirm `System clock synchronized: yes` and an active NTP/chrony service before proceeding past package installation to certificate, registration, timestamping, or any production-handoff work — an unsynchronized clock is exactly the kind of condition that silently breaks certificate validity checks later. If this deployment uses `chrony` (a common RHEL 9 default), validate it directly:

```bash
chronyc tracking
chronyc sources -v
```

**This guide does not specify which NTP server or pool this deployment should use** — that is an infrastructure/operator decision, not something to hard-code here (do not invent one, and do not treat any external public NTP pool as a CamDX-endorsed default). Correct the time-sync configuration per this deployment's own approved infrastructure standard before continuing — do not treat the canary host's currently-unsynchronized state as an acceptable baseline to replicate.

No FQDN is invented in this document, and no private lab address is reproduced here.

## 5. Provider connectivity (if applicable)

If this member needs to reach a specific API provider (e-KYC, e-KYB, OCR, or another), that endpoint information is owned by [`../provider-connectivity.md`](../provider-connectivity.md) — **not duplicated here**. Consult that document once the Security Server is registered and ready for peer connectivity.

## 6. OS / architecture pre-flight

Before touching repository configuration, confirm this host actually matches the supported platform:

```bash
. /etc/os-release
printf '%s\n' "$ID"
printf '%s\n' "$VERSION_ID"
uname -m
```

- `$ID` must be `rhel` — this document does not cover Rocky Linux, AlmaLinux, CentOS Stream, or other RHEL-compatible distributions, even though they may be binary-compatible in practice; that compatibility has not been independently evidenced for CamDX 7.8.2 in this task.
- `$VERSION_ID` must begin with `9` — per §1, only RHEL 9.x is a supported track, and only 9.8 carries direct end-to-end runtime evidence.
- `uname -m` must print `x86_64` — per §1, this is the only architecture with direct 7.8.2 package evidence.

**If any check does not match, STOP** — do not continue to repository configuration on an unsupported release/architecture, and do not guess the closest match.

## 7. Clean-host prerequisite bootstrap

Only tools this guide's own commands actually invoke **before** package installation — not a generic host-provisioning checklist:

```bash
sudo dnf install -y curl gnupg2
```

- `curl` — used by §11/§12's repository-verification commands and §9's EPEL retrieval.
- `gnupg2` — provides `/usr/bin/gpg`, used by §9's key fingerprint-verification block. **Confirmed present** on the Rocky Linux 9 (EL9-family) build container this release's own RHEL packaging path uses (`gnupg2-2.3.3-4.el9.x86_64`) — but that is a build image, not necessarily representative of a genuinely minimal RHEL 9 host, so it is listed here explicitly as a required prerequisite for this guide's own commands rather than assumed present.

**`cronie`, `tar`, `acl`, and `tzdata-java` were removed from this bootstrap step** (present in an earlier draft of this document, copied from CamDX's generic Ansible RHEL provisioning role). Reviewed against the actual package evidence: `tar` and `tzdata-java` **are** real, direct `Requires:` of the `xroad-*` packages (confirmed via `rpm -qpR`) — but that means `dnf` will pull them in automatically as part of the §14 install transaction; there is no need to manually pre-stage them. `cronie` and `acl` are **not** `Requires:` of any of the 19 frozen packages, and no canary evidence establishes them as needed — they are removed rather than carried forward merely because a generic provisioning role happens to install them for unrelated purposes.

```bash
sudo timedatectl set-timezone Asia/Phnom_Penh
```

## 8. SELinux — do not disable

**The validated RHEL 9.8 production canary ran with SELinux in `Enforcing` mode, unmodified, throughout the entire fresh-install and runtime validation, including full OS reboot recovery.** This document therefore does **not** instruct disabling SELinux, and does **not** include `setenforce 0` or any SELinux-permissive step as part of a standard installation.

```bash
getenforce
```

Confirm this returns `Enforcing` (the validated state) before proceeding. If this host is not running SELinux Enforcing, that is a deviation from the validated baseline — document it explicitly rather than silently proceeding.

**On `semanage`/`setsebool`:** the `xroad-proxy` package (confirmed via `rpm -qpR` against the frozen `7.8.2-2.el9` RPM) directly `Requires:` `/usr/sbin/semanage` and `/usr/sbin/setsebool` — SELinux management tools, typically provided by `policycoreutils-python-utils` on RHEL 9. However, **read-only inspection of every one of the 19 packages' `%pre`/`%post`/`%preun`/`%postun`/`%posttrans` scriptlets, and of every shipped script inside the extracted `xroad-proxy` payload, found zero invocations of `semanage`, `setsebool`, `restorecon`, or `chcon`.** No SELinux policy module or boolean change is made by any packaged install-time script in this build. The purpose of this dependency was not established in this task. **This guide does not prescribe any SELinux policy command** — the requirement is satisfied simply by having the tool available so `dnf` can resolve the package's declared dependency (this will happen automatically as part of §14's install transaction, per the dependency-resolution gate in §13); whether any deployment scenario actually exercises it is `REQUIRES VERIFICATION` (see §27).

## 9. Repository-key retrieval and identity verification

**The RHEL RPM signing key is a different key from the Ubuntu APT repository key — do not reuse or conflate them.**

**Confirmed RHEL RPM signing-key identifiers** (per `evidence/2026-09-11-e2-rhel9-final-release-validation.md` and `decisions.md`, this initiative):

```
Primary fingerprint: B88F7428D21393DFAFCFDC3DA2F01162FAA86C16
Signing subkey:      464A548B2267196C4F237376AC367CFD31FFE24E
Key ID:              AC367CFD31FFE24E
```

This is confirmed **not** the same key as the Ubuntu APT repository key (`B387E4CB3C3DE46723AD8E2E13CA752F04194DBF`) — neither the primary fingerprint nor either subkey of one matches the other. The private signing key remains Nexus-side and is never referenced beyond these public identifiers.

**Public-key retrieval URL — CONFIRMED by direct operator evidence.** The validated RHEL 9.8 canary host's actual, captured repository configuration (`/etc/yum.repos.d/camdx-rhel9-r2-canary.repo`) references this exact key URL:

```
https://repository.camdx.gov.kh/repository/camdx-anchors/api/gpg/key/0xFAA86C16-pub.asc
```

The operator directly retrieved this URL and confirmed the returned key's fingerprint matches the previously-recorded RHEL signing identity exactly: primary fingerprint `B88F7428D21393DFAFCFDC3DA2F01162FAA86C16`, signing subkey `464A548B2267196C4F237376AC367CFD31FFE24E` (imported locally on that host as `gpg-pubkey-faa86c16-...`, `CamDX RPM Signing <info@camdx.gov.kh>`). **This is no longer an unresolved gap** — the URL, the key it serves, and its fingerprint are all now directly confirmed, superseding the prior round's classification of this as a blocking publication gap.

**This URL path (`0xFAA86C16`) is distinct from the Ubuntu APT key's URL (`0x04194DBF`) — the two remain different keys, and this document continues to verify only the RHEL/RPM key here:**

```
RHEL RPM key:    B88F7428D21393DFAFCFDC3DA2F01162FAA86C16  (this section)
Ubuntu APT key:  B387E4CB3C3DE46723AD8E2E13CA752F04194DBF  (Ubuntu guide §8 — do not confuse)
```

**Still verify the fingerprint yourself before trusting the download — a confirmed URL is not a substitute for verification, it only means you no longer need a side channel to obtain the key.** Download, verify, and persist the *same* verified artifact for both `rpm --import` and the repository's own `gpgkey=` reference (§11) — never import one file and configure `dnf` to trust a separately-referenced, unverified one:

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
  echo "CamDX RHEL signing key fingerprint MISMATCH — expected $EXPECTED_FPR, got $ACTUAL_FPR" >&2
  echo "STOP: do not trust or import this key." >&2
  exit 1
fi

echo "CamDX RHEL signing key fingerprint verified: $ACTUAL_FPR"

# Persist the SAME verified key to one canonical location, used by BOTH rpm --import
# and the repo file's gpgkey= (§11) — never import one file and trust a different one.
sudo install -d -m 0755 /etc/pki/rpm-gpg
sudo install -m 0644 "$WORKDIR/camdx-rhel-key.asc" /etc/pki/rpm-gpg/RPM-GPG-KEY-camdx-rhel9

sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-camdx-rhel9
```

This uses the same single-temporary-GnuPG-home, machine `--with-colons` fingerprint comparison, and STOP-on-mismatch discipline already established for the Ubuntu APT key (§8 of the Ubuntu guide) — never your real keyring, and no trust extended before the match is confirmed. **Deliberately do not let `dnf` fetch and trust the remote `gpgkey=` URL directly** — even though the URL is now confirmed, this guide keeps the stronger verify-then-persist-locally model: the URL is only ever used by this explicit `curl`+fingerprint-check step, and §11's `gpgkey=` always points at the local, already-verified file, never at the remote URL directly. **The persisted file at `/etc/pki/rpm-gpg/RPM-GPG-KEY-camdx-rhel9` is what `rpm --import` actually imports, and is also what §11's `gpgkey=` references — the same verified bytes, in one place, imported and configured consistently.** Do not proceed to §11's repository configuration, or to package installation, without this.

## 10. Repository prerequisite: EPEL

`xroad-base` directly `Requires:` `crudini` (confirmed via `rpm -qpR` against the frozen `7.8.2-2.el9` RPM — used pervasively by the packages' own scripts to read/write `.ini`-style configuration files). `crudini` is not shipped in RHEL 9's BaseOS or AppStream repositories; it is a long-standing EPEL package. This directly confirms — from the package's own dependency metadata, not merely carried forward from the legacy RHEL 8 guide — that EPEL (or an equivalent repository providing `crudini`) must be enabled before `dnf install xroad-securityserver` (§14) can succeed.

```bash
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
```

This URL pattern is CamDX's own Ansible RHEL provisioning role's mechanism for RHEL 9+ (`ansible/roles/xroad-base/tasks/rhel.yml`, this release workspace) — reused here as the same, already-proven approach, not invented for this document.

`jre-21-headless` is also a direct `Requires:` of `xroad-base`, and is **not** provided by any of the 19 `xroad-*` packages themselves (confirmed: no package in the frozen inventory `Provides:` `jre` or `java`). Which repository resolves this capability (the CamDX RPM repository itself, EPEL, RHEL AppStream, or a separate dependency mirror analogous to the Ubuntu track's `xroad-dependencies-deb`) was **not independently confirmed** in this task.

**Neither `crudini` nor `jre-21-headless` resolving successfully is assumed here** — §13 provides a mandatory dependency-resolution gate that proves, before any package state changes, whether these (and every other transitive dependency) actually resolve against the repositories configured at that point. Treat that gate, not this section, as the actual safety check.

## 11. Repository configuration — CONFIRMED

**The public repository `baseurl` is now directly confirmed**, resolving the prior round's `REQUIRES OPERATOR CONFIRMATION` classification. Two independent, converging pieces of direct evidence establish this:

- The validated RHEL 9.8 canary host's own **captured** repository file, `/etc/yum.repos.d/camdx-rhel9-r2-canary.repo`, proves the real Nexus URL pattern for this release (canary variant: repository name `camdx-rpm-7.8.2-r2-canary`, same `/rhel/9/7.8.2` path structure).
- The operator directly tested the **public production** URL and confirmed `HTTP 200`:
  ```bash
  curl -fsSL -o /dev/null -w 'HTTP %{http_code}\n' \
    "https://repository.camdx.gov.kh/repository/camdx-release-rpm/rhel/9/7.8.2/repodata/repomd.xml"
  # → HTTP 200
  ```

**Confirmed public production `baseurl`:**
```
https://repository.camdx.gov.kh/repository/camdx-release-rpm/rhel/9/7.8.2
```

Only after §9's key has been fingerprint-verified and persisted to `/etc/pki/rpm-gpg/RPM-GPG-KEY-camdx-rhel9`:

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
```

**`gpgcheck=1` / `repo_gpgcheck=0` — both now evidenced, not guessed:**

- `gpgcheck=1` (individual **package** signature verification) — proven appropriate: 19/19 signature checks passed at both the canary and public-promotion stages, and the validated canary's own captured `.repo` file uses `gpgcheck=1`.
- `repo_gpgcheck=0` (repository **metadata** signing) — the operator directly tested the confirmed public `baseurl` and found `repodata/repomd.xml.asc` and `repodata/repomd.xml.key` both return `HTTP 404` — no signed-metadata artifact is published alongside `repomd.xml`. The canary host's own captured `.repo` file independently confirms this same posture (`repo_gpgcheck=0`). **Repository metadata signing is not enabled for the current CamDX 7.8.2 RHEL repository baseline** — this is now a confirmed fact, not an open question, and it is a genuinely separate fact from package signing: `gpgcheck=1` protects individual package integrity; `repo_gpgcheck` would additionally protect the repository's own package listing/checksums, and that second layer is not present in this baseline. Do not set `repo_gpgcheck=1` for this repository — doing so would fail, since no signed metadata exists for it to verify.

```bash
sudo dnf clean all
sudo dnf makecache
```

**Deliberately do not let `dnf` fetch and trust `gpgkey=` as a remote URL** — `gpgkey=` above points at the local file persisted and verified in §9, not at the remote key URL directly, keeping the stronger verify-then-persist model even though the key URL itself is now confirmed reachable.

## 12. Pre-install package gate (mandatory, before installation)

**Do not run the install command until this gate passes.**

```bash
dnf info xroad-securityserver
```

The output must show:

```
Version     : 7.8.2
Release     : 2.el9
Repository  : camdx-rhel9    (or whatever repo id you configured in §11)
```

Supplementary check:
```bash
dnf repoquery --qf '%{name} %{version}-%{release} %{repoid}' xroad-securityserver
```

`dnf repoquery` is part of `python3-dnf`, a base component pulled in automatically with `dnf` itself on EL9 — confirmed directly (`rpm -qf` against the actual `repoquery.py` file inside `/usr/lib/python3.9/site-packages/dnf/cli/commands/`, on the Rocky Linux 9 / EL9-family build environment used for this release's own packaging) to belong to `python3-dnf-4.14.0-8.el9.noarch`, not a separate `dnf-plugins-core`/`dnf-utils` package. No extra package is needed for this specific command.

**If the candidate does not resolve to `7.8.2-2.el9` from your configured CamDX repository — STOP. Do not install.** Inspect for a stale or conflicting repository configuration:

```bash
dnf repolist --all
cat /etc/yum.repos.d/camdx.repo
dnf repoquery --qf '%{name} %{version}-%{release} %{repoid}' xroad-securityserver
```

Look specifically for a leftover legacy RHEL 8 repository entry (the legacy guide's stale `.../rhel/8/7.2.2` path) or a duplicate/conflicting `xroad*` repository definition. Remove or correct it, `sudo dnf clean all && sudo dnf makecache` again, and re-run this gate before proceeding.

**Do not proceed to §13 with an unresolved or unverified `gpgkey=`** (§9/§11) — a candidate-version match alone does not substitute for signature-key verification.

## 13. Dependency-resolution gate (mandatory, before installation)

**§12 proves the `xroad-securityserver` package itself resolves. It does not prove its full dependency tree resolves** — including the currently-unconfirmed items from §10 (`crudini`/EPEL, `jre-21-headless`). This gate proves the **actual canonical install transaction** — `xroad-database-local` + `xroad-securityserver` together — resolves cleanly against the repositories configured at this point, **without changing any package state**:

```bash
sudo dnf install --assumeno xroad-database-local xroad-securityserver
```

`--assumeno` runs `dnf`'s full dependency resolution and prints the complete transaction summary (every package that would be installed, including transitive dependencies such as `crudini`, `jre-21-headless`, `postgresql-server`, `postgresql-contrib`), then automatically answers "no" to the confirmation prompt — **no package is installed, no RPM state changes.**

- **Expected result on success:** a full transaction table is printed, listing `xroad-database-local`, `xroad-securityserver`, and every dependency (directly confirming `crudini` and `jre-21-headless` do resolve from your configured repositories), followed by `Operation aborted.` and a nonzero exit code. **The nonzero exit code here is expected and is not a failure** — it reflects `--assumeno` declining the transaction, not a resolution error.
- **Failure indicator:** `dnf` reports a dependency error (`Error: Unable to find a match`, `nothing provides ...`, `Problem: ...`) **before** reaching the transaction summary/confirmation stage. **STOP** — do not proceed to §14. Re-check §10 (EPEL enabled and current) and §11 (repository correctly configured) before retrying.

This is the appropriate, evidence-based gate for the currently-open `crudini`/EPEL and `jre-21-headless` resolution questions (§10, §27) — it proves them empirically against this specific host's actual configured repositories, rather than assuming either way.

## 14. Package installation

After completing the preceding prerequisites and passing the mandatory pre-install gates in §§12–13:

**Unlike the Ubuntu/Debian meta-package, `xroad-securityserver` on RHEL does not itself `Require:` a database package** — confirmed via `rpm -qpR` against the frozen `xroad-securityserver-7.8.2-2.el9.noarch.rpm`: it requires `xroad-addon-messagelog`, `xroad-addon-metaservices`, `xroad-addon-proxymonitor`, `xroad-addon-wsdlvalidator`, `xroad-proxy`, and `xroad-proxy-ui-api`, but no `xroad-database-*` package. The database requirement surfaces one level down: `xroad-proxy` requires the **virtual capability** `xroad-database` (confirmed via `rpm -qpR`: `xroad-database >= 7.8.2-2.el9`, `xroad-database <= 7.8.2-2.el9.1`). **The virtual `xroad-database` requirement can be satisfied by either `xroad-database-local` or `xroad-database-remote`** (both confirmed, via `rpm -qp --provides`, to `Provide: xroad-database`). This document's package-level inspection does not establish how `dnf`'s resolver would choose between multiple providers if neither were specified explicitly — **the canonical standalone procedure below sidesteps that question entirely by explicitly selecting `xroad-database-local` on the install command line, rather than relying on package-manager provider selection:**

**Default (standalone) path — local PostgreSQL:**
```bash
sudo dnf install xroad-database-local xroad-securityserver
```

**Remote/external PostgreSQL path — see §17 first. This document does not provide an executable remote-database install sequence — read §17 before deviating from the command above.**

During installation, `dnf` does **not** interactively prompt for an admin account name or a certificate Subject DN the way the Debian/Ubuntu package installer does — package scriptlet inspection confirms no interactive prompt anywhere in the 19 packages' `%pre`/`%post` scripts. The `xroad` system user, groups, and directory structure are created automatically and silently by `xroad-base`'s `%post` scriptlet.

**Services are enabled, but not started, by the RPM install itself.** Confirmed via scriptlet inspection: every service-shipping package's `%post` calls `systemd-update-helper install-system-units`, which applies systemd's preset policy (`xroad-base` writes `/usr/lib/systemd/system-preset/90-xroad.preset` containing `enable xroad-*.service`) — this **enables** the units for the next boot but does **not** start them immediately, unlike Ubuntu's `dh_installsystemd`-based packaging, which does. **Do not start any X-Road service yet — see §15: administrator creation happens first, before the first service start, in the canonical fresh-install sequence.**

**Do not** install any HA-only component (a dedicated `serverconf` PostgreSQL cluster, replication tooling, an external load balancer) as part of this standalone procedure — HA remains `REQUIRES VERIFICATION` (see "Status / scope" above), not to be assumed ready by anything in this document.

## 15. Administrator creation, then service start

**Revised fresh-install sequencing, corrected from an earlier draft of this document that started services first and then had to repair stale group state as a follow-up fix.** For a fresh install, create the administrator **before** any X-Road service is started for the first time:

```bash
sudo xroad-add-admin-user camdx-systemadmin
```

**Read-only inspection of this script's actual implementation** (`/usr/share/xroad/bin/xroad-add-admin-user.sh`, shipped inside the `xroad-proxy` package, extracted and read directly — not merely observed at runtime) confirms exactly what it does, and confirms it does **not** interact with, require, or wait on any running systemd service — it is pure user/group/`/etc/shadow` manipulation:

1. Creates the CamDX admin-role groups (`xroad-security-officer`, `xroad-registration-officer`, `xroad-service-administrator`, `xroad-system-administrator`, `xroad-securityserver-observer`) if they do not already exist.
2. **Conditionally** ensures `/etc/shadow` is group-readable and adds the **`xroad` system account** (not the admin username you are creating) to the `shadow` group — but **only if** the `xroad` account cannot already read `/etc/shadow` (`sudo -u xroad test -r /etc/shadow`). This step is entirely independent of, and runs before, the account-creation step below.
3. Creates (or updates) the target admin username and adds it to the admin-role groups from step 1.

Because no X-Road service has been started yet at this point, there is no already-running process to hold stale supplementary-group state — this reordering avoids creating the problem in the first place, rather than fixing it afterward.

**Now start the X-Road services:**

```bash
sudo systemctl start xroad-base xroad-signer xroad-confclient xroad-proxy xroad-proxy-ui-api xroad-monitor xroad-addon-messagelog
```

Each service process starts **after** `xroad-add-admin-user` has already run, so each inherits the final, correct supplementary-group state from the moment it starts — no corrective restart should be necessary for a fresh install performed in this order.

**Restart rule — for deviations from this order, or later configuration changes, not the standard fresh-install path:** if `xroad-add-admin-user` is executed **after** `xroad-proxy-ui-api` is already running (e.g. `xroad-add-admin-user` is re-run later to add a second administrator, or this guide's step order was not followed), restart `xroad-proxy-ui-api` so the live process refreshes its supplementary groups:

```bash
sudo systemctl restart xroad-proxy-ui-api
```

**Evidence-precision note, preserved exactly:** the RHEL 9.8 canary's original observation (`evidence/2026-09-11-e2-rhel9-final-release-validation.md` §6.4) was made under the *old* order (services started, then `xroad-add-admin-user` run against an already-live process) — that is where the stale-group symptom and the need for a corrective restart came from, and where this document's earlier draft's evidence originates. Reading the script source confirms its conditional `shadow`-group logic is real and *capable of* producing that exact state; **the exact triggering path of that specific historical canary session was not separately logged**, so this document states the script's logic as confirmed, not that this exact historical run is proven to have been caused by it — the same distinction preserved from the prior round, now applied to the corrected forward-looking sequence rather than recreated as an unsupported flat causal claim.

Confirm access:
```
https://<SECURITY_SERVER_IP_OR_FQDN>:4000
```

## 16. Firewalld

RHEL 9 ships with `firewalld` enabled by default. **This document does not instruct disabling it, and does not publish blanket public-zone opens.** A rule that accepts `TCP 4000`/`5500`/`5577` from the entire `public` zone (i.e. from any source) is broader than CamDX's own network guidance — Admin UI access must be restricted to the authorized administrator network, and peer traffic to the deployment's actual authorized peer/CamDX source topology, not opened to all sources.

**The following are templates, not literal values — replace every placeholder before running them, per this deployment's actual authorized topology in [`../network-requirements.md`](../network-requirements.md):**

```bash
# TEMPLATE — replace <ZONE>, <ADMIN_CIDR>, <AUTHORIZED_PEER_CIDR> with this
# deployment's actual values from ../network-requirements.md before running.

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

Do not use the `public` zone with an unscoped `--add-port` as a shortcut merely to get past this step quickly — that is exactly the broad-open pattern this section removes.

**`TCP 8080` was also opened during the canary**, for "the intended trusted-subnet host-firewall rule" enabling internal API/client access **during that specific canary's tested configuration only**. **This is not generalized into a universal CamDX client-proxy port policy here** — `client-http-port`/`client-https-port` remains a separate, broader, unresolved CamDX policy question (see [`../initial-configuration.md`](../initial-configuration.md) §12 and §27 below). If this deployment uses the stock `8080`/`8443` client-proxy ports, open the corresponding port(s) with an equally source-scoped rule for your actual trusted-subnet CIDR; do not open `8080` to a broad zone merely because the canary happened to use it.

## 17. PostgreSQL / database handling

**Default (standalone) path:** install `xroad-database-local` alongside `xroad-securityserver` (§14). This installs `postgresql-server` and `postgresql-contrib` as its own `Requires:` (confirmed via `rpm -qpR` against `xroad-database-local-7.8.2-2.el9.noarch.rpm`) — **no specific PostgreSQL major version is pinned by the CamDX package itself**; the actual version resolved depends on RHEL 9's default `postgresql` module/package stream at install time, and this task found no direct evidence establishing a specific version number to document as authoritative. Do not invent one.

Local database initialization is handled automatically by `xroad-proxy`'s `%post`/`%posttrans` scriptlets calling `/usr/share/xroad/scripts/xroad-initdb.sh` on first install (confirmed via direct script inspection of the frozen `7.8.2-2.el9` package). This script:

- Detects whether a remote database is already configured (`postgres.connection.password` set in `/etc/xroad/xroad.properties` or `/etc/xroad.properties`) and, if so, skips local PostgreSQL entirely.
- Otherwise runs `postgresql-setup --initdb`, then — this is the **RHEL9-PKG-01 fix**, confirmed present in the actual packaged script — explicitly runs `systemd-tmpfiles --create` (with a defensive `mkdir`/`chown`/`chmod` fallback) before starting PostgreSQL, so the `/run/postgresql` runtime directory exists even though `postgresql-server` was just installed in the same transaction. It then polls `pg_isready` (bounded, 10 attempts, 1s apart) before handing off to `setup_serverconf_db.sh`/`setup_messagelog_db.sh`.

**This fix is specific to `7.8.2-2.el9` — the earlier `7.8.2-1.el9` build does not contain it and is not a supported installation target.** Do not use `-1.el9` artifacts or reproduce any `-1.el9`-era workaround; `-2.el9` is the minimum approved RHEL build for this release, and its pre-install candidate gate (§12) exists specifically to prevent an accidental `-1.el9` install.

### 17.1 Remote / external PostgreSQL — architectural option, not a validated 7.8.2 procedure

Confirmed directly from RPM metadata, and stated here as fact only — **no executable procedure follows**:

- `xroad-database-remote` exists as a package in the frozen `7.8.2-2.el9` inventory.
- It `Provides: xroad-database` (confirmed via `rpm -qp --provides`) — the same virtual capability `xroad-database-local` provides, i.e. it is a valid alternative to the default path.
- It requires only the `postgresql` client package (confirmed via `rpm -qpR`) — **not** `postgresql-server`/`postgresql-contrib` — consistent with it not installing a local database server.
- The packaged `xroad-initdb.sh` script (§17 above) detects a pre-configured remote database via `postgres.connection.password` being set in `/etc/xroad/xroad.properties` or `/etc/xroad.properties`, and skips local initialization when it is — confirming this file/key pair is the genuine detection mechanism, not a guess.

**Detailed CamDX 7.8.2 RHEL 9 standalone remote-PostgreSQL procedure: `REQUIRES VERIFICATION`.** This document does **not** provide executable `dnf install xroad-database-remote`, credential-handling, or `/etc/xroad.properties` configuration commands — that procedure (exact package selection order, file permissions, credential handling, version-compatibility requirements) has not been independently validated end to end against `7.8.2-2.el9` in this documentation task, and publishing partial copy-paste commands without full validation would contradict this section's own classification. If a remote/external database is required for this deployment, confirm the exact supported procedure and version constraints with CamDX before proceeding — do not assemble one from the facts above.

Do **not** copy HA-style replication assumptions (a dedicated separate `serverconf` cluster, streaming replication) into this section — those are HA-only concerns, out of scope for a standalone deployment.

## 18. Operational Monitoring selection

Operational Monitoring **capability is mandatory** for a CamDX Security Server deployment. For a standalone RHEL installation:

- **Default: local Operational Monitoring**, running on this Security Server itself.
- **Supported alternative: remote/external Operational Monitoring.** Remote/external Operational Monitoring uses a dedicated Operational Monitoring node outside the Security Server. Depending on the approved deployment architecture, that node may serve one or more Security Servers. This is a supported architecture, **not** an HA-only special case — but a detailed, evidenced standalone procedure for configuring a Security Server to use a remote/external Opmonitor node has not been established. **Status: `REQUIRES VERIFICATION`.**

For the normal (local, default) standalone path:

```bash
sudo dnf install xroad-addon-opmonitoring
sudo systemctl restart xroad-opmonitor
sudo systemctl restart xroad-proxy
```

`xroad-addon-proxymonitor` is **not** installed separately here — confirmed via `rpm -qpR` that it is already a direct `Requires:` of `xroad-securityserver` itself, so it is present on this host from §14 onward. **`xroad-opmonitor` is confirmed, via direct `rpm -qpR` inspection of `xroad-addon-opmonitoring-7.8.2-2.el9.x86_64.rpm`, to be a mandatory dependency** — installing `xroad-addon-opmonitoring` will always pull in `xroad-opmonitor`. If it is nonetheless absent, **STOP and inspect** (`dnf repoquery --installed xroad-opmonitor`, `rpm -qa | grep xroad`) rather than improvising an installation.

**The `sudo systemctl restart xroad-proxy` step above is a confirmed, RHEL-specific requirement — not a generic troubleshooting suggestion, and not transferred from Ubuntu (where no such step is prescribed, since it is not evidenced there).** Two independent lines of evidence converge on this:

1. **Direct canary observation** (`evidence/2026-09-11-e2-rhel9-final-release-validation.md` §6.5): "After installing `xroad-addon-opmonitoring`, `xroad-proxy` needed a restart before `getSecurityServerOperationalData` became available."
2. **Package scriptlet inspection** (this task): `xroad-addon-opmonitoring`'s own `%postun` scriptlet contains logic (`mark-restart-system-units xroad-proxy.service`) that marks `xroad-proxy` for restart automatically — but **only in the upgrade path** (`$1 -ge 1` on package removal-during-upgrade), which does not execute on a fresh install of a package that has no prior version. **On a fresh install — the case this document covers — no packaged automation restarts `xroad-proxy` for you.** The requirement is real (confirmed by the canary) but is not automated by the RPM for a first-time install, which is exactly why this guide prescribes it as an explicit manual step rather than assuming the package handles it.

Whichever topology applies to this specific deployment should be stated explicitly in this deployment's own records.

## 19. Signature verification

**`gpgcheck=1` verifies individual package signatures — this is proven appropriate for this release** (per canary/promotion evidence: 19/19 signature checks passed at both the canary and public-promotion stages). Once the fingerprint-verified key from §9 is imported (`sudo rpm --import`), `dnf`/`rpm` verify package signatures automatically against it during install.

**`repo_gpgcheck` (repository *metadata* signing) is a separate fact from package signing, and is now confirmed `0` for this repository, not merely left unset** — see §11 for the direct evidence (a live `HTTP 404` on both `repomd.xml.asc` and `repomd.xml.key` against the confirmed public `baseurl`, corroborated by the canary host's own captured `.repo` file using `repo_gpgcheck=0`). Do not equate "19/19 RPM signature checks passed" with "the repository's `repomd.xml` is itself signed" — these are different mechanisms protecting different things (individual package integrity vs. the repository's own package listing/checksums), and only the first is enabled for this baseline.

To manually confirm a downloaded/installed package's signature against the imported key:

```bash
rpm -K /path/to/xroad-securityserver-7.8.2-2.el9.noarch.rpm
rpm -qa gpg-pubkey --qf '%{name}-%{version}-%{release} %{summary}\n'
```

The second command lists imported GPG keys by their RPM-internal short ID and summary — cross-check the listed key against the confirmed key ID `AC367CFD31FFE24E` (§9) before trusting a "signatures OK" result.

**The local `7.8.2-2.el9` RPM artifacts inspected throughout this document are themselves unsigned** (confirmed: `rpm -qp --qf "%{SIGPGP} %{SIGGPG}"` returns `(none)` `(none)` on every one of the 19 packages) — these are the pre-signing final-candidate build used for read-only evidence inspection in this task, not the signed public artifacts a member would actually download from `camdx-release-rpm`. This document does not claim to have verified a real signature against a real downloaded package; it documents the verification *mechanism* an operator should use against the actual signed public packages.

## 20. Package/version verification

```bash
rpm -qa --qf '%{name}\t%{version}-%{release}\n' 'xroad*' | sort
```

Expected version, every `xroad*` package:
```
7.8.2-2.el9
```

**If mixed or unexpected versions are found — STOP.** Do not proceed to [`../initial-configuration.md`](../initial-configuration.md) with a misaligned package set. Capture diagnostics before making any change:

```bash
dnf repoquery --qf '%{name} %{version}-%{release} %{repoid}' xroad-securityserver
rpm -qa --qf '%{name}\t%{version}-%{release}\n' 'xroad*' | sort
dnf repolist --all
systemctl --no-pager --failed
journalctl -u 'xroad-*' --no-pager --since "-1 hour"
```

Correct the repository definition first (§11/§12) and re-run the candidate gate. **Do not attempt an automatic `dnf reinstall`, `dnf downgrade`, or `rpm --force`** as a presumed fix — none of these recovery behaviors has been validated for this package set. Because this is a fresh-host procedure with no prior production state to preserve, rebuilding the host from a clean image may be preferable to improvising a package-state repair — this is an operator decision to make deliberately, not an automatic step this guide prescribes.

## 21. Native systemd unit inventory

**Derived directly from the frozen `7.8.2-2.el9` RPM contents** (`rpm -qpl`, read-only, all 19 packages; no package extracted, rebuilt, or installed to obtain this — not inferred from Ubuntu or container behavior):

| Unit | Shipped by package | Unit type | Notes |
|---|---|---|---|
| `xroad-base.service` | `xroad-base` | **One-shot** — confirmed by directly reading the actual shipped unit file (`rpm2cpio`-extracted, read-only, from `xroad-base-7.8.2-2.el9.x86_64.rpm`): `Type=oneshot`, `RemainAfterExit=yes`, `ExecStart=/usr/share/xroad/scripts/xroad-base.sh` — native RHEL evidence, not inferred from Ubuntu | Do **not** expect `active (running)` for this unit — `active (exited)` is the healthy state (`RemainAfterExit=yes` is exactly what makes that the correct terminal state), not a fault. See §24. |
| `xroad-confclient.service` | `xroad-confclient` | Long-running | Global configuration client |
| `xroad-monitor.service` | `xroad-monitor` | Long-running | Environmental/system monitoring |
| `xroad-proxy.service` | `xroad-proxy` | Long-running | Core message-exchange proxy |
| `xroad-proxy-ui-api.service` | `xroad-proxy-ui-api` | Long-running | Admin UI / management REST API |
| `xroad-signer.service` | `xroad-signer` | Long-running | Signing/authentication key operations |
| `xroad-addon-messagelog.service` | `xroad-addon-messagelog` | Long-running | Message log archiver |
| `xroad-opmonitor.service` | `xroad-opmonitor` | Long-running | Local Operational Monitoring daemon. **Present only when local OPMON is installed (§18)** — confirmed not part of `xroad-securityserver`'s own `Requires:`. |
| `xroad-autologin.service` | `xroad-autologin` | **Long-running, `Type=simple`** — confirmed by directly reading the actual shipped unit file (`rpm2cpio`-extracted, read-only, from `xroad-autologin-7.8.2-2.el9.noarch.rpm`): `Type=simple`, `User=xroad`/`Group=xroad`, `ExecStart=/usr/share/xroad/autologin/xroad-autologin-retry.sh`, `Restart=on-failure` | **Not installed by default** — an optional utility that automatically enters the software token PIN on `xroad-signer` start (confirmed via package description and file listing). Has real security implications (the PIN must be stored on-host for this to function) and is **out of scope for this baseline fresh-install procedure**; not covered further here. |

**`xroad-addon-proxymonitor` ships no systemd unit file at all** — confirmed by direct `rpm -qpl` inspection of `xroad-addon-proxymonitor-7.8.2-2.el9.x86_64.rpm` (zero `.service`/`.target`/`.timer` entries). Its `Requires:` (`xroad-monitor`, `xroad-proxy`, plus generic `systemd`) confirms it adds no separate daemon of its own — consistent with the same finding independently confirmed for the Ubuntu/Debian build of this component.

## 22. Reboot validation — two distinct checkpoints

The RHEL 9.8 canary has been validated to include full OS reboot recovery — but this covers two distinct levels of state, and this guide only speaks to the first:

- **Package-install-level check (in scope for this document):** after completing §6–§18, services should start correctly and survive a restart at the package/service level. A reboot at this stage mainly verifies service auto-start (via the `90-xroad.preset` enablement, §14) and persistent package/configuration state.
- **Full deployment-level reboot validation (out of scope for this document, belongs after [`../initial-configuration.md`](../initial-configuration.md)):** confirming that Security Server *identity*, certificates, registration, subsystem status, and Operational Monitoring state all persist correctly through a reboot is only meaningful once those things exist. The canary's own full-reboot PASS (API/UI/OPMON all functional post-reboot) was performed on a fully *configured* Security Server, not a package-installation-only one — do not treat a reboot performed immediately after this document's own steps as equivalent evidence.

## 23. Proceed to Common Initial Configuration

**RHEL package installation complete.**

Do not attempt member/key/certificate/subsystem configuration here — that entire workflow (configuration anchor import, Member Class/Member Code, Member Name verification, Security Server Code, software token/PIN, timestamping service, AUTH/SIGN key generation, CSR submission, certificate import, authentication certificate registration, subsystem registration, and final registration status checks) is owned by [`../initial-configuration.md`](../initial-configuration.md), identically to the Ubuntu track.

## 24. CamDX-specific settings — do not apply unresolved values automatically

The following remain **CamDX policy questions**, not settled by this document — see [`../initial-configuration.md`](../initial-configuration.md) §12 for the full classification table and reasoning. Do **not** turn any of these into an unconditional required command here merely because a historical CamDX value exists:

| Setting | Upstream default | CamDX legacy documented value | Status |
|---|---|---|---|
| `strict-identifier-checks` | `true` (fresh installs, X-Road 7.3 onward) | Not present at all in the legacy RHEL source (present in the legacy Ubuntu source as `false`) | REQUIRES VERIFICATION |
| `client-http-port` | `8080` | `80` (legacy RHEL source frames this as an *optional* override, not a default) | REQUIRES VERIFICATION |
| `client-https-port` | `8443` | `443` (same framing) | REQUIRES VERIFICATION |
| `health-check-port` | `0` (disabled) | `5588` (validated only in the container/Sidecar deployment) | REQUIRES VERIFICATION for native installs |
| `max-records-in-payload` | `10000` | `30000` (legacy CamDX override; legacy key spelling `max-records-in-playload` was a documentation typo) | REQUIRES VERIFICATION |

`message-body-logging = false` is the one setting in this group classified **REQUIRED BY CAMDX** in [`../initial-configuration.md`](../initial-configuration.md) §12. All other settings above should be confirmed against current CamDX policy before being applied as a default for new 7.8.2 installations.

## 25. Validation checklist

Before proceeding to [`../initial-configuration.md`](../initial-configuration.md), confirm:

- [ ] OS/architecture pre-flight passed (`rhel` + `9.x` + `x86_64`) — §6
- [ ] `getenforce` shows `Enforcing` (the validated baseline) — §8
- [ ] Repository-key fingerprint verified, persisted to `/etc/pki/rpm-gpg/RPM-GPG-KEY-camdx-rhel9`, and imported — §9
- [ ] `/etc/yum.repos.d/camdx.repo` uses the confirmed `baseurl` (§11) — reachable, `repomd.xml` returns `HTTP 200`
- [ ] `timedatectl status` shows `System clock synchronized: yes` before proceeding past this checklist — §4
- [ ] Pre-install candidate gate resolved to `7.8.2-2.el9` from the correct CamDX repository — §12
- [ ] Dependency-resolution dry-run (`--assumeno`) succeeded for `xroad-database-local xroad-securityserver` — §13
- [ ] `xroad-add-admin-user` was run **before** any X-Road service was first started — §15
- [ ] `rpm -qa` shows every `xroad*` package aligned to `7.8.2-2.el9`, no mixed versions — §20
- [ ] PostgreSQL (local default, per §17, or remote per §17.1) is healthy and reachable
- [ ] `systemctl --no-pager --failed` shows no X-Road-related failures
- [ ] All expected long-running `xroad-*` services are `active (running)`; `xroad-base.service` shows `active (exited)`, which is its correct healthy one-shot state, not a failure — §21
- [ ] Admin UI is reachable on `TCP 4000`, restricted to the authorized administrator network — §16
- [ ] `firewalld` rich rules use this deployment's actual authorized CIDRs, not a blanket zone-wide open — §16
- [ ] Operational Monitoring topology (local or remote/external) is explicitly identified for this deployment — §18
- [ ] If using the local/default OPMON path, `xroad-opmonitor` is installed/running **and** `xroad-proxy` has been restarted — §18
- [ ] CamDX infrastructure connectivity (per [`../network-requirements.md`](../network-requirements.md)) is confirmed available from this host
- [ ] Ready to proceed to [`../initial-configuration.md`](../initial-configuration.md)

**Do not claim** member registration PASS, certificate registration PASS, real API exchange PASS, or full deployment-level reboot recovery at this stage — those are outcomes of the *later* configuration steps in [`../initial-configuration.md`](../initial-configuration.md) and the full reboot checkpoint in §22, not of package installation alone.

## 26. Troubleshooting

For connectivity problems after installation, see [`../troubleshooting/connectivity.md`](../troubleshooting/connectivity.md). For a mixed-version or failed-install condition, see §20 — capture diagnostics, correct the repository definition, and treat host rebuild as a deliberate operator decision rather than following an unvalidated automatic repair command.

## 27. Items requiring verification

Collected from throughout this document, in one place. **None of these are blocking a self-service member installation any longer** — the repository `baseurl`, the RHEL signing-key retrieval URL, and the `repo_gpgcheck` posture (all previously blocking) are now resolved by direct operator evidence; see §9/§11/§19. The items below are standard, non-blocking `REQUIRES VERIFICATION` items.

1. **`crudini`/EPEL and `jre-21-headless` live resolution** (§10) — confirmed as real package-level `Requires:`; the §13 dependency-resolution gate is the actual empirical check to run on each target host, but this task could not run it against a live host itself. This is a per-host operational validation gate, not a publication blocker.
2. **SELinux `semanage`/`setsebool` purpose** (§8) — a real declared dependency of `xroad-proxy`, but no invocation found anywhere in the inspected scriptlets/scripts; the actual purpose and whether any scenario exercises it is unconfirmed.
3. **`strict-identifier-checks`** CamDX policy for 7.8.2 fresh installs (§24).
4. **`client-http-port`/`client-https-port`** — which value CamDX 7.8.2 native installs should standardize on (§24); the canary's `8080` usage is not generalized into policy (§16).
5. **`health-check-port`** for native installs (§24).
6. **`max-records-in-payload`** CamDX override value for 7.8.2 (§24).
7. **Remote/external Operational Monitoring** — detailed standalone (non-HA) implementation procedure (§18).
8. **Local PostgreSQL major version** actually pulled in on a fresh RHEL 9 install (§17) — still not directly established from evidence; no version invented.
9. **Remote/external PostgreSQL** — no executable procedure provided pending full 7.8.2-specific end-to-end validation (§17.1).
10. **Package-state recovery procedure** (§20) — no validated automatic repair step exists; treated as an operator decision, not prescribed.
11. **High Availability** — remains `REQUIRES VERIFICATION` entirely, not addressed by this document.

**Operational follow-up (not a release-package defect):** the validated RHEL 9.8 canary host was directly observed with an unsynchronized system clock and no active NTP/chrony daemon (§4) — this is a host/infrastructure configuration matter for that specific host, not a defect in the `7.8.2-2.el9` packages, and does not reopen any part of the accepted RHEL package validation. §4 now includes an explicit pre-flight check and STOP condition for this.

None of the numbered items above are guessed at or resolved in this document.

## 28. References

- Legacy source: `rhel_standalone_security_server_installation_and_configuration.md` (this repository, `main` branch) — treated as historical evidence only, given its RHEL 8 / X-Road 7.3.2 baseline and stale `.../rhel/8/7.2.2` repository path; not carried forward except where separately re-confirmed against `7.8.2-2.el9` evidence in this document.
- Read-only inspection of the frozen `7.8.2-2.el9` RPM contents (`~/engineering/camdx-xroad-7.8.2-release/rhel9-r2-rpms/`, checksums verified against `camdx-7.8.2-rhel9-r2-SHA256SUMS.txt`) — the authoritative basis for dependency graph, systemd units, and scriptlet behavior throughout this document. `xroad-rpm-el9-e2-amd64` (the Rocky Linux 9 + `rpm-build` container image used for this release's own build path) was used as the inspection environment; no package was rebuilt, modified, or installed.
- `evidence/2026-09-11-e2-rhel9-final-release-validation.md`, `evidence/2026-09-09-e2-rhel9-packaging-findings-and-r2-fix.md` (this initiative) — RHEL 9.8 signed production canary, RHEL9-PKG-01/02 defect resolution, signing/promotion verification.
- `evidence/2026-09-21-e2-container-registry-publication-preparation.md` (this initiative) — an independent, unrelated task's read-only Nexus REST API repository-catalog listing, used as corroborating evidence for the `camdx-release-rpm` repository group's existence and its underlying `yum`-format hosted repository, ahead of the direct confirmation below.
- **Direct operator evidence, captured on the validated RHEL 9.8 host** (this round): its actual `/etc/yum.repos.d/camdx-rhel9-r2-canary.repo` file; a live `HTTP 200` against `https://repository.camdx.gov.kh/repository/camdx-release-rpm/rhel/9/7.8.2/repodata/repomd.xml`; live `HTTP 404` results against `repodata/repomd.xml.asc` and `repodata/repomd.xml.key` on that same confirmed `baseurl`; a live retrieval of `https://repository.camdx.gov.kh/repository/camdx-anchors/api/gpg/key/0xFAA86C16-pub.asc` with its fingerprint independently matched against the previously-recorded RHEL signing identity; and `timedatectl`/`chronyc` output showing that host's current time-synchronization state. This is the authoritative basis for §9's and §11's now-confirmed values.
- CamDX's own Ansible RHEL provisioning role (`ansible/roles/xroad-base/tasks/rhel.yml`, `ansible/roles/xroad-base/templates/xroad.repo.j2`, this release workspace) — used only as structural reference for the `.repo` file's field layout and the EPEL-install command pattern; its actual `baseurl`/`gpgkey` values point at upstream NIIS infrastructure and are not reused for CamDX's own repository.
- [`../network-requirements.md`](../network-requirements.md), [`../provider-connectivity.md`](../provider-connectivity.md), [`../initial-configuration.md`](../initial-configuration.md), [`../troubleshooting/connectivity.md`](../troubleshooting/connectivity.md), [`../upgrade/README.md`](../upgrade/README.md).

## 29. Document change history

| Date | Change |
|---|---|
| 2026-09-24 | Initial placeholder draft created as part of the CamDX-Documents 7.8.2 documentation architecture modernization — package identity/repository path only, most OS-level behavior explicitly deferred as `REQUIRES VERIFICATION` pending direct evidence. |
| 2026-09-25 (round 1) | Full evidence-driven rewrite. Replaced every placeholder/deferred item with direct evidence from read-only inspection of the frozen, checksum-verified `7.8.2-2.el9` RPM artifacts and the RHEL 9.8 signed production canary evidence. Corrected the placeholder's repository path and the placeholder's incorrect reuse of the Ubuntu APT key's retrieval URL for the RHEL signing key. Documented SELinux Enforcing as the validated baseline. Explained the RHEL-specific `xroad-database` virtual-capability install requirement. Resolved the canary's admin/PAM `shadow`-group observation via `xroad-add-admin-user.sh` source inspection. Confirmed the local-OPMON `xroad-proxy` restart requirement is RHEL-specific. Derived the native systemd unit inventory directly from RPM contents. |
| 2026-09-25 (round 2) | Targeted operational correction, following a HOLD gate on round 1's publication-readiness: removed the asserted-`baseurl` `.repo` block and the asserted `repo_gpgcheck=1` (neither was evidenced at the time), classified the repository `baseurl` and the RHEL signing-key public URL as a blocking publication gap, fixed a key-persistence inconsistency, revised the clean-host bootstrap against actual command usage, added a dependency-resolution dry-run gate, reordered admin creation before first service start, removed blanket firewalld opens and the executable remote-PostgreSQL commands, corrected the database-provider wording, narrowed the RHEL 9.x compatibility claim, and added a one-shot/long-running systemd distinction. |
| 2026-09-25 (round 3) | Final narrow correction: the operator supplied direct evidence from the validated RHEL 9.8 host itself, resolving round 2's remaining blockers. (1) **Public repository `baseurl` CONFIRMED** — the operator's own captured canary `.repo` file plus a live, operator-executed `HTTP 200` against `https://repository.camdx.gov.kh/repository/camdx-release-rpm/rhel/9/7.8.2/repodata/repomd.xml` replace the prior round's derived/unconfirmed candidate; §11 now publishes an executable `.repo` block with this confirmed value, no longer classified `REQUIRES OPERATOR CONFIRMATION`. (2) **RHEL signing-key public URL CONFIRMED** — `https://repository.camdx.gov.kh/repository/camdx-anchors/api/gpg/key/0xFAA86C16-pub.asc`, operator-retrieved and fingerprint-matched exactly against the previously-recorded identity (`B88F7428D21393DFAFCFDC3DA2F01162FAA86C16`); the "blocking publication gap" classification is removed, while the Ubuntu-APT-key-vs-RHEL-key distinction and the verify-before-trust discipline are both preserved — the guide still verifies the downloaded key's fingerprint itself and still keeps `dnf`'s `gpgkey=` pointed at the locally-persisted, already-verified file rather than the remote URL directly. (3) **`repo_gpgcheck` CONFIRMED `0`, not merely unset** — the operator directly found `repomd.xml.asc`/`repomd.xml.key` both `HTTP 404` against the confirmed public `baseurl`, corroborated by the canary host's own captured `.repo` file; §11/§19 now state plainly that repository-metadata signing is not enabled for the current 7.8.2 RHEL baseline, rather than leaving it as an open question. (4) **Added a time-synchronization pre-flight check and STOP condition** (§4) in response to a new operator observation (the canary host's clock was unsynchronized, no active NTP/chrony daemon) — documented explicitly as an operational finding, not a release-package defect, and not reopening any part of the accepted RHEL package validation; no specific NTP server is hard-coded. (5) **`xroad-base.service`'s one-shot classification is now confirmed by directly reading the actual shipped RHEL unit file** (`Type=oneshot`, `RemainAfterExit=yes`, extracted read-only from the frozen `xroad-base` RPM) rather than by convention with the Ubuntu build. (6) Removed the now-resolved items (repository `baseurl`, signing-key URL, `repo_gpgcheck`) from §27's unresolved-items list and renumbered the remainder; none of the remaining items are blocking. |
| 2026-09-25 (round 4, this round) | Two final non-blocking editorial cleanups, applied after ChatGPT/operator **APPROVAL** of this document: (1) §14's prerequisite prose listed `§6, §8, §9, §11, §12, §13` and accidentally omitted §10 (EPEL) — reworded to "After completing the preceding prerequisites and passing the mandatory pre-install gates in §§12–13," removing the incomplete enumeration rather than patching it with another incomplete list; the actual installation sequence is unchanged. (2) `xroad-autologin.service`'s unit type in §21 is now confirmed by directly reading the actual shipped unit file (`rpm2cpio`-extracted, read-only, from `xroad-autologin-7.8.2-2.el9.noarch.rpm`): `Type=simple`, `User=xroad`/`Group=xroad`, `ExecStart=/usr/share/xroad/autologin/xroad-autologin-retry.sh`, `Restart=on-failure` — confirmed long-running, replacing the prior round's unproven "Long-running (when installed)" label with directly-evidenced unit semantics; still not installed by default and still out of scope for this baseline procedure. No other content changed. |
