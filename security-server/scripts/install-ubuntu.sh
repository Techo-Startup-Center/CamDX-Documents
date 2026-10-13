#!/usr/bin/env bash
#
# install-ubuntu.sh — safe fresh installation of the CamDX Security Server
# 7.8.2 on supported Ubuntu platforms (22.04 Jammy / 24.04 Noble, amd64).
#
# This script is for a FRESH Security Server only. It refuses to run
# against a host that already has a Security Server installed, has any
# other X-Road package installed, or whose /etc/xroad state is
# ambiguous. It does not configure member identity, Security Server
# Code, software token, keys, certificates, or registration — that is
# Initial Configuration's job (see ../initial-configuration.md), not
# this script's.
#
# Usage:
#   sudo ./install-ubuntu.sh [--admin-user NAME]
#   sudo ./install-ubuntu.sh --preflight
#   sudo ./install-ubuntu.sh --help
#
# MODE: safe preseed, based on the validated frozen-package interface.
# The only Debconf value this script preseeds is the admin
# username — a non-secret string. Every other installation
# question is left to the package's own evidenced, computed default
# under a noninteractive frontend. No secret is ever preseeded, printed,
# accepted via a flag/environment variable, or logged.
#
# A newly-created administrator account is asked to set its OS/PAM
# password interactively, via the normal 'adduser' prompt — the
# X-Road native Admin UI authenticates through this host's configured
# PAM authentication by default, so a disabled-password account would
# not be able to log in.
#
set -euo pipefail

PROG_NAME="$(basename "$0")"
CAMDX_KEY_FPR_EXPECTED="B387E4CB3C3DE46723AD8E2E13CA752F04194DBF"
CAMDX_KEY_URL="https://repository.camdx.gov.kh/repository/camdx-anchors/api/gpg/key/0x04194DBF-pub.asc"
CAMDX_KEYRING="/etc/apt/keyrings/camdx-archive-keyring.gpg"
CAMDX_REPO_LIST="/etc/apt/sources.list.d/camdx-7.8.2.list"

ADMIN_USER=""
PREFLIGHT_ONLY=0

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
log()  { printf '%s\n' "$*" >&2; }
info() { log "[INFO] $*"; }
warn() { log "[WARN] $*"; }
fail() { log "[FAIL] $*"; log "STOP: installation aborted."; exit 1; }

usage() {
  cat <<'EOF'
install-ubuntu.sh — CamDX Security Server 7.8.2 Ubuntu installer

Usage:
  sudo ./install-ubuntu.sh [options]

Options:
  --admin-user NAME   Administrator account to create/use for the
                       X-Road Admin UI and management API. If this
                       account does not exist, it is created and you
                       will be asked to set its password interactively.
                       If it already exists, it is used as-is — its
                       password is never changed by this script. If
                       omitted, you will be prompted for a name.
  --preflight          Run read-only checks only. Does not install
                        packages, modify repositories, create users,
                        or change time configuration.
  --help                Show this help and exit.

This script is for a FRESH Security Server installation only. It will
refuse to run against a host that already has a Security Server
installed, has any other X-Road package installed, or whose /etc/xroad
state is ambiguous. It never deletes existing configuration and never
offers a --force override.

Certificate subject/SAN values are not configurable by this v1 script —
the package's own evidenced, host-derived default is used. This is a
v1 scope limitation, not a statement that custom values are unsupported
in general; see the advanced/manual path in the installation guide if
you need a specific certificate subject now.

After a successful run:
  sudo ./camdx-ss-check
then continue to Initial Configuration — see ../initial-configuration.md.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --admin-user)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        log "Missing value for --admin-user"
        usage
        exit 2
      fi
      ADMIN_USER="$2"; shift 2 ;;
    --preflight)
      PREFLIGHT_ONLY=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      log "Unknown option: $1"; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# 1. Root check
# ---------------------------------------------------------------------------
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "This script must be run as root (sudo ./$PROG_NAME ...)."
  fi
}

# ---------------------------------------------------------------------------
# 2. Platform detection
# ---------------------------------------------------------------------------
PLATFORM_CODENAME=""
PLATFORM_REPO=""
PLATFORM_EXPECTED_VERSION=""

detect_platform() {
  if [ ! -r /etc/os-release ]; then
    fail "Cannot read /etc/os-release — unable to determine platform."
  fi
  # shellcheck disable=SC1091
  . /etc/os-release

  if [ "${ID:-}" != "ubuntu" ]; then
    fail "Unsupported OS (ID=${ID:-unknown}). This script supports Ubuntu 22.04/24.04 only."
  fi

  case "${VERSION_CODENAME:-}" in
    jammy)
      PLATFORM_CODENAME="jammy"
      PLATFORM_REPO="camdx-deb-jammy-7.8.2"
      PLATFORM_EXPECTED_VERSION="7.8.2-1.ubuntu22.04"
      ;;
    noble)
      PLATFORM_CODENAME="noble"
      PLATFORM_REPO="camdx-deb-noble-7.8.2"
      PLATFORM_EXPECTED_VERSION="7.8.2-1.ubuntu24.04"
      ;;
    *)
      fail "Unsupported Ubuntu release (VERSION_CODENAME=${VERSION_CODENAME:-unknown}). This script supports jammy (22.04) and noble (24.04) only."
      ;;
  esac

  local arch
  arch="$(dpkg --print-architecture)"
  if [ "$arch" != "amd64" ]; then
    fail "Unsupported architecture ($arch). Only amd64 is supported."
  fi

  info "Platform: Ubuntu $PLATFORM_CODENAME, amd64 — expecting package version $PLATFORM_EXPECTED_VERSION"
}

# ---------------------------------------------------------------------------
# 3. Existing-install / partial-install safety gate
#
# State model (read-only — safe to reuse verbatim from --preflight):
#   A. xroad-securityserver fully installed       -> STOP: EXISTING SECURITY SERVER
#   B. xroad-securityserver known to dpkg in any
#      OTHER (non-"install ok installed") state
#      — unpacked, half-configured, half-installed,
#      triggers-awaited, triggers-pending, residual
#      "config-files", reinstreq, or any other
#      abnormal/partial state                     -> STOP: AMBIGUOUS/PARTIAL X-ROAD INSTALLATION
#   C. xroad-securityserver unknown to dpkg, but
#      ANY other xroad* package is known to dpkg
#      in ANY non-absent state (installed, partial,
#      or residual config-files alike)             -> STOP: AMBIGUOUS/PARTIAL X-ROAD INSTALLATION
#   D. non-empty /etc/xroad with no X-Road
#      package state at all                        -> STOP: AMBIGUOUS X-ROAD STATE
#   E. repository/key files already present but
#      no X-Road package/state                     -> not an error; proceed (this script
#                                                      re-verifies the key fingerprint and
#                                                      rewrites the repo file deterministically
#                                                      regardless of what is already there)
#   F. none of the above                            -> FRESH
#
# Every xroad* package known to dpkg at all — in ANY state, including a
# residual "config-files" state left behind by a removal that was never
# purged — is treated as non-fresh. This script never purges, repairs,
# or otherwise modifies that package state automatically; it only
# reports the package name, its dpkg status, and its version (never
# anything secret-bearing) and stops.
# ---------------------------------------------------------------------------
check_existing_install() {
  local all_xroad
  all_xroad="$(dpkg-query -W -f='${Package}\t${Status}\t${Version}\n' 'xroad*' 2>/dev/null || true)"

  if [ -n "$all_xroad" ]; then
    local ss_line
    ss_line="$(printf '%s\n' "$all_xroad" | awk -F'\t' '$1=="xroad-securityserver"{print; exit}')"

    if [ -n "$ss_line" ]; then
      local ss_status
      ss_status="$(printf '%s' "$ss_line" | cut -f2)"
      if [ "$ss_status" = "install ok installed" ]; then
        fail "EXISTING SECURITY SERVER: xroad-securityserver is already installed on this host (dpkg status: $ss_status). This script is for a FRESH installation only — it will not reinstall or modify an existing Security Server. Run 'sudo ./camdx-ss-check' to assess its current state, or see ../troubleshooting/README.md if something is wrong."
      fi
      fail "AMBIGUOUS / PARTIAL X-ROAD INSTALLATION: xroad-securityserver is known to dpkg in a non-standard state (dpkg status: $ss_status). This script will not proceed over a partial or abnormal X-Road package state — inspect it manually (dpkg -l xroad-securityserver) before continuing. No package will be purged, repaired, or modified automatically."
    fi

    local other_xroad
    other_xroad="$(printf '%s\n' "$all_xroad" | awk -F'\t' '{print $1"="$3" ("$2")"}')"
    fail "AMBIGUOUS / PARTIAL X-ROAD INSTALLATION: xroad-securityserver is not known to dpkg, but the following X-Road package(s) are, in a non-absent state (installed, partial, or residual config-files alike): $(printf '%s' "$other_xroad" | tr '\n' ' '). This script will not proceed over an unexpected X-Road package state — inspect it manually before continuing. No package will be purged, repaired, or modified automatically."
  fi

  if [ -d /etc/xroad ] && [ -n "$(ls -A /etc/xroad 2>/dev/null)" ]; then
    fail "AMBIGUOUS X-ROAD STATE: /etc/xroad already exists and is not empty, but no X-Road package is installed. This script will not overwrite it. Inspect /etc/xroad manually before proceeding."
  fi

  if [ -f "$CAMDX_KEYRING" ] || [ -f "$CAMDX_REPO_LIST" ]; then
    info "Repository/key preparation from a prior run detected ($CAMDX_KEYRING / $CAMDX_REPO_LIST) — no X-Road package is installed, so this is not blocking. This run will re-verify the key fingerprint and rewrite the repository file deterministically."
  fi

  info "FRESH — no existing or partial X-Road installation detected."
}

# ---------------------------------------------------------------------------
# 4. Time synchronization gate
#
# mode="preflight": read-only, never prompts. An indeterminate result is
# reported as a WARN only.
# mode="install" (default): an indeterminate result asks for explicit
# operator confirmation before continuing.
# In both modes, a clearly-unsynchronized clock is a hard stop (fail()
# itself makes no changes, so this is safe to call during --preflight
# too).
# ---------------------------------------------------------------------------
check_time_sync() {
  local mode="${1:-install}"

  if ! command -v timedatectl >/dev/null 2>&1; then
    warn "Time sync: timedatectl not found — cannot determine state automatically. Confirm manually that this host's clock is synchronized (clock skew breaks certificate/registration operations later)."
    return
  fi

  local synced
  synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"

  case "$synced" in
    yes)
      info "Time sync: synchronized (NTPSynchronized=yes)."
      ;;
    no)
      fail "Time sync: NOT synchronized (NTPSynchronized=no). Fix clock synchronization before installing — certificate and registration operations later depend on it. This script does not configure or replace your organization's NTP policy."
      ;;
    *)
      warn "Time sync: could not be determined (timedatectl returned '${synced}')."
      if [ "$mode" = "preflight" ]; then
        warn "Confirm manually that this host's clock is synchronized before installing. (--preflight never prompts.)"
      else
        read -r -p "Time synchronization could not be confirmed. Continue anyway? [y/N] " confirm
        case "$confirm" in
          y|Y|yes|YES) info "Continuing on explicit operator confirmation." ;;
          *) fail "Aborted — time synchronization could not be confirmed." ;;
        esac
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 5. Prerequisites
# ---------------------------------------------------------------------------
install_prerequisites() {
  info "Installing prerequisite packages (ca-certificates curl gnupg locales)..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg locales
}

# ---------------------------------------------------------------------------
# 6. Administrator account — PAM-authenticated
#
# If ADMIN_USER already exists: used as-is, password never touched.
# If it does not exist: created via the normal 'adduser' prompt flow,
# which asks the operator to set a password interactively. No password
# is ever accepted via a flag, environment variable, stdin pipe, or a
# generated default, and none is ever logged.
# ---------------------------------------------------------------------------
ensure_admin_user() {
  if [ -z "$ADMIN_USER" ]; then
    if [ ! -t 0 ]; then
      fail "No --admin-user was supplied and this installation is not running interactively. Supply --admin-user <name>, or run interactively."
    fi
    read -r -p "Administrator account name to create/use for the Admin UI: " ADMIN_USER
  fi

  if [ -z "$ADMIN_USER" ]; then
    fail "No administrator account name supplied."
  fi

  if [ "$ADMIN_USER" = "xroad" ]; then
    fail "The account name 'xroad' is reserved for the X-Road system user. Choose a different administrator account name."
  fi

  if ! [[ "$ADMIN_USER" =~ ^[a-z][-a-z0-9_]*$ ]]; then
    fail "Invalid administrator account name: '$ADMIN_USER'. Use a normal lowercase Linux username."
  fi

  if getent passwd "$ADMIN_USER" >/dev/null 2>&1; then
    info "Administrator account '$ADMIN_USER' already exists — using it as-is. Its password is not changed by this script."
    info "This account must be able to authenticate through this host's configured PAM authentication — the native Admin UI uses PAM by default."
    return
  fi

  if [ ! -t 0 ]; then
    fail "Administrator account '$ADMIN_USER' does not exist, and this script is not running with an interactive terminal — creating a new account requires setting its password interactively. Either run this script interactively, or create/provision the '$ADMIN_USER' account (with a working PAM password) yourself first, then re-run with --admin-user $ADMIN_USER."
  fi

  info "Creating administrator account '$ADMIN_USER' — you will now be asked to set its password."
  adduser --gecos "" "$ADMIN_USER"
}

# ---------------------------------------------------------------------------
# 7. Signing key
#
# Runs as a subshell function (body in "(...)" rather than "{...}") so
# that a "trap ... EXIT" registered inside it fires on EVERY exit from
# this function — normal completion, an explicit fail()/exit call, or
# an early errexit-triggered failure of curl/gpg/install before the
# function would otherwise return — guaranteeing the temporary GnuPG
# homedir is removed in every case. A "trap ... RETURN" (the prior
# implementation) does not fire on exit/errexit, only on a normal
# function return, and so leaked the temp directory on any failure
# path. A failure inside this subshell still aborts the whole
# installation: this subshell's own exit status is non-zero, and the
# parent script's own 'set -e' aborts on that non-zero result exactly
# as it would for any other failing command.
# ---------------------------------------------------------------------------
install_signing_key() (
  set -euo pipefail

  info "Retrieving and verifying the CamDX repository signing key..."

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT
  install -d -m 0700 "$workdir/gnupg-home"

  curl -fsSL "$CAMDX_KEY_URL" -o "$workdir/camdx-apt-key.asc"

  gpg --homedir "$workdir/gnupg-home" --no-default-keyring --batch --quiet \
      --import "$workdir/camdx-apt-key.asc"

  local actual_fpr
  actual_fpr="$(gpg --homedir "$workdir/gnupg-home" --no-default-keyring --batch \
      --with-colons --list-keys \
    | awk -F: '$1=="fpr"{print $10; exit}')"

  if [ "$actual_fpr" != "$CAMDX_KEY_FPR_EXPECTED" ]; then
    fail "CamDX repository key fingerprint MISMATCH — expected $CAMDX_KEY_FPR_EXPECTED, got $actual_fpr. Do not trust, dearmor, or install this key."
  fi

  info "CamDX repository key fingerprint verified: $actual_fpr"

  gpg --batch --yes --dearmor \
      -o "$workdir/camdx-archive-keyring.gpg" \
      "$workdir/camdx-apt-key.asc"

  install -d -m 0755 /etc/apt/keyrings
  install -m 0644 "$workdir/camdx-archive-keyring.gpg" "$CAMDX_KEYRING"
)

# ---------------------------------------------------------------------------
# 8. Repository + provenance
#
# active_source_lines(): print only the "active" (non-comment) lines of
# a given classic one-line .list file (simple leading-'#' filter). Used
# directly only for .list files — see classify_source_match() below for
# deb822 .sources files, which require stanza-level "Enabled:" parsing
# to avoid treating a disabled stanza as active.
# ---------------------------------------------------------------------------
active_source_lines() {
  local f="$1"
  grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -v '^[[:space:]]*$' || true
}

# classify_source_match <file> <substring>
#
# Prints one of: ACTIVE, AMBIGUOUS, DISABLED, NONE — the strongest
# classification found for any line/stanza in <file> containing
# <substring> (a plain substring, not a regex).
#
# For a classic .list file: a non-comment matching line is ACTIVE;
# otherwise NONE.
#
# For a deb822 .sources file: the file is split into stanzas on blank
# lines, comment lines (leading '#') are ignored. A stanza containing
# the substring is classified by its own "Enabled:" field: "Enabled: no"
# -> DISABLED; "Enabled: yes" or no "Enabled:" field at all (the deb822
# default is enabled) -> ACTIVE; any other/malformed "Enabled:" value
# -> AMBIGUOUS. If multiple stanzas match, ACTIVE outranks AMBIGUOUS
# outranks DISABLED, so this function never under-reports a real active
# or ambiguous conflict. This is a deliberately conservative, v1-scope
# parser — it does not handle every deb822 edge case (multi-line field
# continuations, unusual whitespace), but it never calls a disabled
# (Enabled: no) stanza "active", and it never silently treats an
# undetermined-enablement stanza as a safe PASS.
# ---------------------------------------------------------------------------
classify_source_match() {
  local f="$1" pattern="$2"
  case "$f" in
    *.sources)
      awk -v pat="$pattern" '
        function flush() {
          if (uri_match) {
            if (status == "no") { s = "DISABLED" }
            else if (status == "yes" || status == "") { s = "ACTIVE" }
            else { s = "AMBIGUOUS" }
            if (s == "ACTIVE") { best = "ACTIVE" }
            else if (s == "AMBIGUOUS" && best != "ACTIVE") { best = "AMBIGUOUS" }
            else if (s == "DISABLED" && best == "NONE") { best = "DISABLED" }
          }
          uri_match = 0
          status = ""
        }
        BEGIN { best = "NONE" }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { flush(); next }
        {
          if (index($0, pat) > 0) { uri_match = 1 }
          if ($0 ~ /^[[:space:]]*Enabled:[[:space:]]*/) {
            val = $0
            sub(/^[[:space:]]*Enabled:[[:space:]]*/, "", val)
            gsub(/[[:space:]]+$/, "", val)
            status = tolower(val)
          }
        }
        END { flush(); print best }
      ' "$f" 2>/dev/null
      ;;
    *)
      if active_source_lines "$f" | grep -qF "$pattern"; then
        printf 'ACTIVE\n'
      else
        printf 'NONE\n'
      fi
      ;;
  esac
}

check_conflicting_repos() {
  local f state
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    [ "$f" = "$CAMDX_REPO_LIST" ] && continue
    state="$(classify_source_match "$f" "repository.camdx.gov.kh/repository/camdx-deb-")"
    case "$state" in
      ACTIVE)
        fail "A conflicting CamDX repository entry was found (active, not commented-out) in $f. This script will not automatically remove it. Review and correct it manually (e.g. an old track or a stale version), then re-run this script."
        ;;
      AMBIGUOUS)
        fail "A conflicting or ambiguous CamDX repository stanza was found in $f — its enablement (Enabled: yes/no) could not be safely determined by this v1 parser. This script will not automatically remove it or guess about it. Review it manually, then re-run this script."
        ;;
    esac
  done
}

configure_repository() {
  info "Configuring the CamDX $PLATFORM_CODENAME repository..."
  check_conflicting_repos
  echo "deb [arch=all,amd64 signed-by=$CAMDX_KEYRING] https://repository.camdx.gov.kh/repository/$PLATFORM_REPO $PLATFORM_CODENAME main" \
    > "$CAMDX_REPO_LIST"
  apt-get update -qq
}

# ---------------------------------------------------------------------------
# 9. Provenance gate — proves BOTH expected version AND expected
#    repository provenance for each directly-installed package, using
#    native 'apt-cache policy' output (read-only).
# ---------------------------------------------------------------------------
check_package_provenance() {
  local pkg="$1"
  local policy
  policy="$(apt-cache policy "$pkg" 2>/dev/null || true)"

  if [ -z "$policy" ]; then
    fail "Provenance gate failed for $pkg: apt-cache policy returned nothing (package unknown to apt)."
  fi

  local candidate
  candidate="$(printf '%s\n' "$policy" | awk '/Candidate:/{print $2; exit}')"

  if [ "$candidate" != "$PLATFORM_EXPECTED_VERSION" ]; then
    fail "Provenance gate failed for $pkg: candidate version '${candidate:-<none>}' does not match expected '$PLATFORM_EXPECTED_VERSION'. Do not install. Check for a stale/conflicting repository entry and re-run after correcting it."
  fi

  # Extract the source line(s) listed directly under the matching
  # candidate version in the "Version table:" section.
  local sources
  sources="$(printf '%s\n' "$policy" | awk -v ver="$candidate" '
    $0 ~ ("^ *"ver" ") {capture=1; next}
    capture && /^ *[0-9]+ / {print; next}
    capture {capture=0}
  ')"

  if [ -z "$sources" ]; then
    fail "Provenance gate failed for $pkg: could not determine which source is offering candidate $candidate."
  fi

  if ! printf '%s\n' "$sources" | grep -q "repository.camdx.gov.kh/repository/$PLATFORM_REPO "; then
    fail "Provenance gate failed for $pkg: candidate $candidate is not confirmed as being offered by the expected CamDX repository ($PLATFORM_REPO). Source(s) found: $(printf '%s' "$sources" | tr '\n' ';')"
  fi

  local distinct_repo_count
  distinct_repo_count="$(printf '%s\n' "$sources" | awk '{print $2}' | sort -u | wc -l)"
  if [ "$distinct_repo_count" -gt 1 ]; then
    fail "Provenance gate failed for $pkg: candidate $candidate is offered by more than one source, creating ambiguous provenance. Sources: $(printf '%s' "$sources" | tr '\n' ';')"
  fi

  info "Provenance confirmed for $pkg: $candidate via $PLATFORM_REPO"
}

check_all_provenance() {
  check_package_provenance xroad-securityserver
  check_package_provenance xroad-database-local
  check_package_provenance xroad-addon-opmonitoring
}

# ---------------------------------------------------------------------------
# 10. Package installation (MODE A — safe preseed)
# ---------------------------------------------------------------------------
install_packages() {
  info "Preparing non-interactive package installation..."

  # The only Debconf value preseeded by this v1 script is the admin
  # username — a non-secret string, based on the validated
  # frozen-package interface. Every other Debconf question in this
  # flow (database-host, service-subject/
  # -altsubject, proxy-ui-api-subject/-altsubject, proxy-memory)
  # resolves to its own evidenced, computed default under a
  # noninteractive frontend — none of them is preseeded here.
  echo "xroad-common xroad-common/username string $ADMIN_USER" | debconf-set-selections

  info "Installing xroad-securityserver (local PostgreSQL path)..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y xroad-securityserver xroad-database-local
}

# ---------------------------------------------------------------------------
# 11. Local Operational Monitoring
# ---------------------------------------------------------------------------
install_local_opmon() {
  info "Installing local Operational Monitoring (default path)..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y xroad-addon-opmonitoring

  if ! dpkg-query -W -f='${Status}' xroad-opmonitor 2>/dev/null | grep -q "install ok installed"; then
    fail "xroad-opmonitor is not installed after installing xroad-addon-opmonitoring. This should be impossible (xroad-opmonitor is a hard dependency) — inspect the package state (apt-cache policy xroad-opmonitor; dpkg-query -W xroad-opmonitor) rather than retrying blindly."
  fi

  # xroad-addon-opmonitoring's own postinst already restarts xroad-proxy
  # automatically, based on the validated frozen-package interface. No
  # additional manual restart is issued here.
  info "Local Operational Monitoring installed."
}

# ---------------------------------------------------------------------------
# 12. Result
# ---------------------------------------------------------------------------
print_result() {
  local installed_version
  installed_version="$(dpkg-query -W -f='${Version}' xroad-securityserver 2>/dev/null || echo "unknown")"

  cat <<EOF

CamDX Security Server 7.8.2 installation complete

Platform: Ubuntu $PLATFORM_CODENAME
Package:  $installed_version

This installation is NOT yet registered or configured with CamDX.

Next:
  sudo ./camdx-ss-check

Then:
  Complete Initial Configuration — see ../initial-configuration.md
EOF
}

# ---------------------------------------------------------------------------
# Preflight-only mode — strictly read-only, never prompts
# ---------------------------------------------------------------------------
run_preflight() {
  info "Running preflight checks (read-only — no changes will be made)..."
  detect_platform
  check_existing_install
  check_time_sync preflight

  if command -v curl >/dev/null 2>&1; then
    # Probe actual APT repository metadata (the "InRelease" index), not the
    # bare repository directory root — the root path has no reason to
    # serve anything and legitimately returns 404 on a correctly
    # configured repository; InRelease is what apt itself fetches first
    # and is a direct, accurate signal of whether this platform's track
    # is actually published and reachable.
    local metadata_url="https://repository.camdx.gov.kh/repository/$PLATFORM_REPO/dists/$PLATFORM_CODENAME/InRelease"
    if curl -fsSL --max-time 10 -o /dev/null "$metadata_url"; then
      info "CamDX repository metadata is reachable ($metadata_url)."
    else
      warn "CamDX repository metadata is not reachable ($metadata_url). This does not necessarily mean a network/firewall problem — check connectivity, DNS resolution, and that this platform's track is published, before proceeding."
    fi
  else
    warn "curl not available — cannot check CamDX repository reachability yet (it will be installed as a prerequisite during a real run)."
  fi

  check_conflicting_repos || true

  info "Preflight complete."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  require_root

  if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
    run_preflight
    exit 0
  fi

  detect_platform
  check_existing_install
  check_time_sync install
  install_prerequisites
  ensure_admin_user
  install_signing_key
  configure_repository
  check_all_provenance
  install_packages
  install_local_opmon
  print_result
}

main
