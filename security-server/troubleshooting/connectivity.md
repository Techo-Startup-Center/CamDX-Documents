# CamDX Security Server — Connectivity Troubleshooting

## Status / scope

**Status: SAFE/EVIDENCED (diagnostic technique and layered flow) — canonical operator troubleshooting guide for CamDX 7.8.2 network/connectivity failures**, covering Ubuntu standalone, RHEL 9 standalone, and container deployments. Derived from [`../network-requirements.md`](../network-requirements.md), [`../provider-connectivity.md`](../provider-connectivity.md), [`../initial-configuration.md`](../initial-configuration.md), [`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md), [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md), [`../container/deployment.md`](../container/deployment.md), `release-notes/7.8.2.md`, and applicable validated E2 evidence (referenced by filename throughout, never by reproducing private/internal addresses).

**This document diagnoses. It does not duplicate the canonical CamDX IP matrix or the provider endpoint registry, and it does not prescribe unvalidated remediation.**

- The full CamDX infrastructure IP/port matrix (Central Server, Management Security Server, TSA, OCSP, Central Monitoring) is owned by [`../network-requirements.md`](../network-requirements.md) — **not reproduced here**.
- Provider-specific endpoint profiles (e-KYC, e-KYB, OCR, etc.) are owned by [`../provider-connectivity.md`](../provider-connectivity.md) — **not reproduced here**.
- This document is **not** an installation guide, **not** an upgrade/migration procedure, and **not** an HA guide. HA topology troubleshooting is out of scope; HA itself remains `REQUIRES VERIFICATION` per every other CamDX 7.8.2 document.

**Covers:** CamDX Central Server connectivity, Management Security Server connectivity, TSA, OCSP, Central Monitoring, Security Server peer connectivity, consumer information-system/client-proxy connectivity, provider endpoint connectivity, DNS, TLS, routing, host firewall, upstream firewall/NAT/VIP, clock/time synchronization, and container port publishing.

## 1. Troubleshooting model

**Diagnose before you change anything.** Work through the layers below in order — do not jump straight to a firewall-rule change, a certificate-validation bypass, or a service restart before confirming which layer is actually failing. Every command in this document is read-only **unless explicitly labeled as a controlled remediation** (§10 lists exactly what this document refuses to prescribe as remediation).

```text
 1. Identify source host and destination role
 2. Confirm environment: DEV or PROD
 3. Confirm authoritative destination IP/port
 4. DNS resolution where FQDN is involved
 5. Route/path check
 6. TCP reachability
 7. TLS handshake where TLS applies
 8. Host firewall
 9. Upstream firewall / NAT / VIP
10. Application/service process
11. X-Road-specific logs/status
12. PKI/time checks when certificates are involved
```

Two rules apply throughout:

- **A successful ICMP `ping` is not proof that TCP/application connectivity works.** ICMP and the target TCP service can be filtered independently — many infrastructure paths permit one and not the other. Use `ping` only as a limited, early routing/reachability signal, never as confirmation that a specific port or service is reachable.
- **Do not start with a firewall-rule change.** A firewall rule that looks wrong is not necessarily the fault — confirm DNS, routing, and TCP-level behavior first, so a rule is not modified based on a misdiagnosis.

## 2. Before you start — evidence to gather

Collecting this up front makes every later step, and any eventual escalation (§9), faster:

| Field | Notes |
|---|---|
| Platform | Ubuntu (Jammy/Noble), RHEL 9, or container |
| CamDX package/image version | e.g. `7.8.2-1.ubuntu24.04`, `7.8.2-2.el9`, or the container digest (§7 of [`../container/deployment.md`](../container/deployment.md)) |
| Environment | Development or Production — **the two environments use different CamDX infrastructure addresses**, see [`../network-requirements.md`](../network-requirements.md) §2 |
| Source host role | Security Server itself, an administrator's workstation, a consumer information system, a provider information system |
| Destination role | Central Server / Management Security Server / TSA / OCSP / Central Monitoring / peer Security Server / provider endpoint / Admin UI / OPMON daemon |
| Destination FQDN/IP/port | From [`../network-requirements.md`](../network-requirements.md) or [`../provider-connectivity.md`](../provider-connectivity.md) — see §3.1 below on confirming the *authoritative* value, not a guessed or cached one |
| Timestamp of the observed failure | |
| Observed error (exact text) | |

## 3. Layered diagnostic flow

### 3.1 Identify source host and destination role

Before running any command, state explicitly which of the roles in [`../network-requirements.md`](../network-requirements.md) §2–§4 applies: is the Security Server itself the source (outbound to CamDX infrastructure or to a peer/provider), or is it the destination (an administrator reaching the Admin UI, a peer Security Server reaching this one, Central Monitoring reaching this one in Production)? The applicable port set, and which direction (inbound/outbound) needs troubleshooting, follow directly from this — do not guess at a port to test before this is established.

### 3.2 Confirm environment: DEV or PROD

CamDX Development and Production use **different** infrastructure IP addresses for the same logical service (Central Server, Management Security Server, TSA, OCSP — see [`../network-requirements.md`](../network-requirements.md) §2.1 vs §2.2). Confirm which environment this Security Server is deployed against before testing any specific address — testing a Production address from a Development deployment (or vice versa) produces a misleading failure that looks like a network problem but is actually a wrong-target problem.

### 3.3 Confirm the authoritative destination IP/port

Look up the destination in the authoritative source — [`../network-requirements.md`](../network-requirements.md) for CamDX infrastructure and generic peer/client-proxy/Admin UI/OPMON ports, or [`../provider-connectivity.md`](../provider-connectivity.md) for a specific provider's endpoint — rather than relying on a locally cached value, a value from an old configuration export, or a value copied from an unrelated deployment. See §6 below for the CamDX-side port-role reference (Admin UI, peer, client-proxy, health endpoint) and §5 of `network-requirements.md` for the union address-list policy (every listed address is authorized; do not assume any one is more "current" than another).

### 3.4 DNS resolution

```bash
getent hosts <hostname>
```

`getent hosts` uses the host's actual configured resolution order (`/etc/nsswitch.conf`, typically `files dns`). It is the preferred NSS-aware baseline check on the validated Ubuntu/RHEL platforms, and is also confirmed present in the frozen container image — a read-only inspection of the published 7.8.2 image (`docker create`/`docker cp`, no run) directly confirmed `/usr/bin/getent` is shipped in it. Prefer it as the baseline check across all three platforms; do not assume it is universally present on every possible Linux host beyond these validated ones. Where `dig`/`nslookup` are already installed, they can additionally confirm the DNS answer directly against a specific resolver:

```bash
dig +short <hostname>
dig +short <hostname> @<resolver-authoritative-for-this-deployment>
# or, if `dig` is unavailable:
nslookup <hostname>
```

Neither `dig` nor `nslookup` is assumed present — both come from an optional package (`dnsutils` on Ubuntu, `bind-utils` on RHEL) not installed by any CamDX package; install it only if you intend to use it for this specific check.

**If `getent hosts` returns something unexpected — an internal/private address where a public CamDX address was expected, or a different address than a real external DNS query returns — see §4 below before concluding the DNS server itself is broken.** A local static override is one of the most common causes of exactly this symptom, and it is genuinely evidenced in this initiative's own build infrastructure (§4).

### 3.5 Route/path check

```bash
ip route get <destination-ip>
```

Confirms which local route/interface the host will actually use to reach the destination, and whether a route exists at all. Useful before a TCP test to rule out an obviously wrong egress interface (e.g. traffic unexpectedly routing over a management interface instead of the intended egress path).

```bash
traceroute <destination-ip-or-hostname>
# or, if unavailable:
tracepath <destination-ip-or-hostname>
```

Identifies roughly where in the path a connection stops responding — a local gateway, an intermediate hop, or the destination itself. Neither tool is guaranteed installed by default on a minimal host; install only if needed. Treat the last responding hop as an approximate signal, not a definitive fault location — many networks intentionally rate-limit or suppress ICMP TTL-exceeded/port-unreachable responses at some hops without that indicating a fault there.

### 3.6 TCP reachability

```bash
nc -vz <destination-ip-or-hostname> <port>
```

Tests the specific port, not just whether the host responds to ICMP. **Do not reduce every TCP failure to "a firewall rule" — the exact failure mode is itself diagnostic, and DNS (§3.4) and routing (§3.5) failures are separate, earlier layers, not TCP-layer symptoms.** Capture and report the exact error text from `nc`/`curl`/`openssl` rather than paraphrasing it as "connection failed":

| Result | What it normally means | Where to look next |
|---|---|---|
| **Timeout** (no response at all within the connection window) | Packet filtering that silently drops rather than rejects (common for both local and upstream firewalls), a routing/path loss, or a genuinely unresponsive/unreachable endpoint | §3.5 (route/path), §3.8 (host firewall), §3.9 (upstream firewall/NAT/VIP) |
| **Connection refused** | The destination host was reached at the network/transport layer, but no process is listening on that port, or an active reject (e.g. an explicit deny rule, rather than a silent drop) occurred | §3.10 (is the expected service/process actually running and bound to this port?), then §3.8/§3.9 only if the process is confirmed running and listening |
| **Connection reset** (RST received, possibly after the connection was briefly established) | The TCP path itself was reachable, but something actively terminated the connection — this can be the application itself (e.g. rejecting the request), a load balancer/VIP in front of the real destination, or a stateful firewall/policy device resetting rather than dropping | §3.9 (upstream firewall/NAT/VIP — see §4 for the VIP-specific pattern), §3.10 (application/service behavior), and the destination's own logs where available |

A single "TCP failure" is not a diagnosis — the three outcomes above point at materially different layers, and a firewall rule is only one of several possible causes, most directly implicated by a timeout or an active refuse, not automatically by every failure mode. `nc` is not guaranteed installed; where it is unavailable, a Bash TCP probe is an equivalent read-only fallback — note that this fallback cannot always distinguish refused from reset as cleanly as `nc -v` or `curl -v` can, so prefer those where available:

```bash
timeout 5 bash -c "cat < /dev/null > /dev/tcp/<destination-ip-or-hostname>/<port>" && echo "OPEN" || echo "CLOSED/FILTERED"
```

For a locally listening service (e.g. confirming the Admin UI or health endpoint is actually bound and listening on this host before testing it from elsewhere):

```bash
ss -lntp
```

### 3.7 TLS handshake (where TLS applies)

Only after §3.6 confirms the TCP port itself is reachable — a TLS failure and a TCP failure look different and should not be conflated.

```bash
openssl s_client -connect <hostname>:<port> -servername <hostname> </dev/null
```

Shows the full certificate chain, negotiated protocol/cipher, and any handshake failure reason — the most complete read-only TLS diagnostic available, and applicable only to a genuinely TLS-terminating endpoint. **Not every CamDX-relevant port uses TLS — check which protocol actually applies before choosing an example.** The Admin UI (`4000`) is HTTPS; the container health endpoint (`5588`, container-only, see §5) is plain HTTP — **do not imply TCP `5588` uses TLS.**

For an HTTPS-facing endpoint such as the Admin UI, prefer a normal, certificate-validating request first:

```bash
curl -v https://127.0.0.1:4000/
```

Only bypass certificate validation where doing so is intentional and clearly labeled as diagnostic-only — for example, to confirm the HTTP layer itself responds even though the certificate is expired, self-signed, or issued by an untrusted CA:

```bash
curl -vk https://127.0.0.1:4000/
```

For the container health endpoint (`5588`), which is plain HTTP, not HTTPS, in the validated deployment:

```bash
curl -v http://127.0.0.1:5588/
```

For a non-standard port, always write it explicitly as part of the authority component (`https://<hostname>:<port>/` or `http://<hostname>:<port>/`, matching the endpoint's actual protocol), never appended separately or omitted — the port and the protocol are both part of what is being tested.

**`curl -k` (or `openssl s_client` output showing a chain that does not validate) may be used only to distinguish a TCP/HTTP-reachability problem from a trust-chain problem**, and only against an endpoint that genuinely uses TLS. Label any output gathered this way explicitly as "certificate validation bypassed for diagnostic purposes only." **This is never presented as a fix** — do not leave a deployment running with certificate validation disabled, and do not suggest disabling it in application configuration as a way to "resolve" a TLS finding (see §10).

### 3.8 Host firewall

Confirm the required rule is actually present in the local host firewall configuration — read-only inspection first:

**RHEL (`firewalld`):**
```bash
sudo firewall-cmd --list-all
```

**Ubuntu, if `ufw` is in use:** the canonical CamDX Ubuntu installation guide ([`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md)) does not itself prescribe a specific host-firewall tool or configuration — this is a deployment-specific choice (bare-metal host firewall, cloud security group, or none, depending on the environment). Where `ufw` is in use:
```bash
sudo ufw status verbose
```
Where `nftables`/`iptables` is used directly instead (not evidenced as a CamDX-standard choice, included only as a fallback read-only check where relevant to this specific deployment):
```bash
sudo nft list ruleset
# or
sudo iptables -L -n -v
```

**Container:** the container image does not run its own host firewall — any firewall enforcement happens on the Docker host itself, using whatever tool that host uses (the checks above apply to the host, not to the container). Additionally confirm which interface/address a port is actually published on, since a port bound to `127.0.0.1` only (the validated default for the Admin UI and health endpoint, see §6) is not reachable from another host by design, not by firewall block:
```bash
docker port camdx-security-server
```

A rule present in the configuration but scoped to the wrong source (a CIDR that excludes the actual observed source address) produces the same "should be reachable but isn't" symptom as a missing rule — check the actual source, not just whether *a* rule with the right port number exists. See [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md) §16 for the CamDX-recommended `firewall-cmd` rich-rule template pattern (scoped by source CIDR, never a blanket zone-wide open) if a genuinely missing rule needs to be added as a controlled remediation.

### 3.9 Upstream firewall / NAT / VIP

If the host firewall (§3.8) is confirmed correctly configured but the connection still fails, the block may be upstream — a network firewall, a NAT device, or a load balancer/VIP in front of either endpoint. See §4 below for the specific F5/VIP/NAT/hosts-file diagnostic patterns, and [`../network-requirements.md`](../network-requirements.md) §5 for the architecture guidance on NAT/VIP address handling. This layer usually cannot be fully diagnosed from the Security Server host alone — a `traceroute` (§3.5) stopping partway, or a connection that resets rather than times out, are useful signals to bring to whichever team controls that upstream device.

### 3.10 Application / service process

Confirm the destination service itself is actually running before concluding the network path is at fault. As §3.6 details, a correctly open port with nothing listening behind it typically produces **connection refused**, and a listening-but-unhealthy or actively-rejecting process can produce **connection reset** — these are two distinct signals, not interchangeable, and neither is the same as a **timeout** (more often a filtering/routing symptom, per §3.6's table). A refused or reset result *can* also originate from an upstream device (a firewall actively rejecting, or a load balancer/VIP resetting) rather than the destination application itself — §3.9 and §4 cover that distinction; do not assume the application layer is at fault merely because the failure was refused/reset rather than a timeout. See §8 for the native/container-specific commands (`systemctl status`, `docker exec ... supervisorctl status`).

### 3.11 X-Road-specific logs/status

Once the network layers above are confirmed (or ruled out), the X-Road application's own logs and status commands usually explain the remaining failure directly — see §8 for the exact native (`journalctl`) and container (`docker logs`) commands, including the container-specific `xroad-confclient` log-tag naming detail.

### 3.12 PKI / time checks

Certificate validity, registration status, and timestamping/OCSP all depend on correct system time. See §7 for the full clock-skew diagnostic and its CamDX-specific evidence.

## 4. F5 / VIP / NAT / `/etc/hosts` cases

**A local `/etc/hosts` mapping can silently redirect the Security Server to a different address than the one DNS would otherwise resolve — including to a member-controlled VIP instead of the intended CamDX or peer address, or to an internal address instead of a public one.** This is not a hypothetical concern: this initiative's own container-image build infrastructure directly encountered exactly this symptom — a package-repository hostname resolved to one address via a host's static `/etc/hosts` override, but to a *different* address via real DNS when queried from inside a container that (correctly) does not inherit the host's `/etc/hosts` (see `evidence/2026-09-18-e2-container-https-preflight.md` and `evidence/2026-09-18-e2-container-final-https-build.md` in this initiative's evidence — the specific internal addresses involved are infrastructure-internal and are not reproduced in this canonical document). The general lesson transfers directly to Security Server connectivity troubleshooting: **never assume a hostname resolves the same way on every host, or the same way inside a container as on its Docker host.**

**Distinguish these four things explicitly — do not conflate them:**

| Concept | How to check | What it tells you |
|---|---|---|
| **DNS/FQDN resolution** (the authoritative, intended answer for *this deployment*) | `dig +short <hostname> @<resolver-authoritative-for-this-deployment>` — query whichever resolver/view is actually authoritative or intended for this Security Server's deployment, not automatically a public/external one; split-horizon DNS, organization-specific views, and internal authoritative resolution can legitimately return a different, equally correct answer than a public resolver | The value the deployment's own intended resolver returns for this hostname, bypassing any local `/etc/hosts` override |
| **Local hosts-file override** | `getent hosts <hostname>` compared against the DNS answer above; also inspect `cat /etc/hosts` directly for a matching line | Whether *this specific host* is using a different address than real DNS would provide, and why |
| **VIP address** | Compare the resolved/overridden address against the known VIP address for this destination, if one is documented for this deployment (e.g. a provider's load-balancer entry point in [`../provider-connectivity.md`](../provider-connectivity.md), or a member's own F5/load-balancer address in front of their Security Server) | Whether traffic is intentionally being sent to a front-end device rather than directly to a single server |
| **Real destination address** | The authoritative value from [`../network-requirements.md`](../network-requirements.md) or [`../provider-connectivity.md`](../provider-connectivity.md) | The value everything above should ultimately be reconciled against |
| **Outbound NAT / source IP** | `ip route get <destination-ip>` (§3.5) shows the egress interface; the *actual* source IP as observed by the remote side may differ from the host's own address if NAT/source-NAT is applied upstream — this can only be confirmed from the remote side's own logs, or from a provider/CamDX-side source-IP registration record (see [`../provider-connectivity.md`](../provider-connectivity.md) §5) | Whether the address the destination sees as the source matches what is allow-listed there |

**Diagnostic sequence for this class of issue:**

1. Determine which DNS resolver or view is authoritative or intended for **this specific Security Server deployment** — an internal/organization resolver for an internal-only name, or the public DNS system for a name expected to have a public answer. Do not assume a public/external resolver is automatically more authoritative than an organization-internal one; split-horizon DNS and internal authoritative views are legitimate, not a fault by themselves.
2. Query that resolver directly, e.g. `dig +short <hostname> @<resolver-authoritative-for-this-deployment>` — this is the value that *should* apply for this deployment.
3. Compare that result against `getent hosts <hostname>` on the affected host — if they differ, inspect `/etc/hosts` on that specific host for a static entry.
4. If a static entry exists, determine whether it is a deliberate, documented, temporary workaround (see [`../network-requirements.md`](../network-requirements.md) §5's guidance that any such override "must be treated as explicitly temporary and documented, not left as an undocumented permanent fixture") or an accidental leftover.
5. Compare against a separate public/external resolver **only** when this specific hostname is actually expected to have a public DNS answer (e.g. it is meant to be reachable from outside the organization) — for a genuinely internal-only name, a *different* public-resolver answer (or no answer at all) is expected and is not itself evidence of a fault.
6. If a load balancer/VIP/F5 is in the path (on either the member's side or a peer/provider's side), confirm explicitly whether the address being tested is the VIP's own address or the address of an individual backend server behind it — a VIP performing Layer-4 passthrough should forward TCP `5500`/`5577` transparently (per [`../network-requirements.md`](../network-requirements.md) §5); a failure specific to one backend node behind the VIP looks different (intermittent, or affecting only some sessions) than a failure at the VIP itself (consistently affecting all traffic).
7. If a container is involved anywhere in this path, remember it has its **own** independent `/etc/hosts` and DNS resolution, separate from its Docker host — an override present on the host does not apply inside the container, and vice versa. Confirm resolution from *inside* the actual process that needs it:
   ```bash
   docker exec camdx-security-server getent hosts <hostname>
   ```

**Do not reproduce any real member-specific VIP address, private topology, or internal CamDX infrastructure address when documenting or escalating a case of this kind — use placeholders (`<VIP_ADDRESS>`, `<REAL_DESTINATION_ADDRESS>`) in any shared write-up, exactly as this document does.**

## 5. Port semantics reference

Do not use this table as a substitute for [`../network-requirements.md`](../network-requirements.md) — it is a diagnostic quick-reference for *which role* a port serves, not the authoritative connectivity matrix.

| Port | Role | Applies to |
|---|---|---|
| `4000` | Admin UI — restricted administration path | Native (Ubuntu/RHEL) and container, identically |
| `5500` | Security Server peer / server-to-server connectivity (message exchange) | Native and container, identically |
| `5577` | Security Server peer / server-to-server connectivity, OCSP-related — **not a log-collection port** | Native and container, identically |
| `8080` / `8443` | Consumer information-system / client-proxy path | **Container:** confirmed as the image's own stock declared/exposed ports (see [`../container/deployment.md`](../container/deployment.md) §14). **Native:** the CamDX-standard client-proxy port is a separate, still-open policy question (legacy Ubuntu documentation used `80`/`443`, legacy RHEL used `8080`/`8443` as the stock default with `80`/`443` as an optional override) — **the container's stock `8080`/`8443` exposure must not be used to resolve this native question**; see [`../initial-configuration.md`](../initial-configuration.md) §12, status `REQUIRES VERIFICATION`. |
| `5588` | Health-check endpoint | **Container only**, and only where explicitly enabled — validated bound to `127.0.0.1` in the reference deployment. For native installs, whether to enable this endpoint at all is a separate, unresolved question (`REQUIRES VERIFICATION`, evidence base is container/Sidecar-specific — [`../initial-configuration.md`](../initial-configuration.md) §12). |
| `2080` | Security Server → local Operational Monitoring daemon (internal) | Native and container, applies to the local (default) OPMON topology only — see §6 below and [`../network-requirements.md`](../network-requirements.md) §4/§7 |

## 6. Operational Monitoring troubleshooting

CamDX policy, unchanged and preserved here: **Operational Monitoring capability is MANDATORY. Local Operational Monitoring is the default topology. Remote/external Operational Monitoring is a supported alternative**, not an HA-only mechanism (see [`../initial-configuration.md`](../initial-configuration.md) §12 and [`../network-requirements.md`](../network-requirements.md) §7).

**Do not confuse these two distinct things when troubleshooting or reporting a finding:**

- **Remote retrieval/query of operational data** — a separate monitoring client successfully calling `getSecurityServerOperationalData` (or an equivalent query) against this Security Server's *local* OPMON daemon, over the network. This has been directly validated for both the container path and the RHEL native path.
- **A remote/external Opmonitor-node topology** — the Security Server itself being configured to send its operational data to a dedicated Opmonitor node elsewhere, instead of running local OPMON. **For native deployments, remote/external Operational Monitoring remains a supported alternative architecture and is not HA-only** — a dedicated remote/external Operational Monitoring node may serve one or more Security Servers, depending on the approved deployment architecture (see [`../network-requirements.md`](../network-requirements.md) §7 and [`../initial-configuration.md`](../initial-configuration.md) §12). The CamDX High Availability documents are one existing example/evidence source that uses this topology — they are cited here only as an example, and **must not** be read as defining the only valid remote/external OPMON architecture. **However, the detailed CamDX 7.8.2 standalone (non-HA) configuration procedure for this topology has not yet been independently validated and remains `REQUIRES VERIFICATION`** — no executable remote-OPMON configuration is invented here or anywhere else in this initiative's documentation. For the **container path, the mechanism itself remains separately `REQUIRES VERIFICATION`** — no configuration mechanism for pointing the image at a remote/external Opmonitor node was found in the image ([`../container/deployment.md`](../container/deployment.md) §12/§22 item 2).

**Diagnostic steps, local OPMON topology:**

1. Confirm the local OPMON process/service is actually running:
   - **Native:** `systemctl status xroad-opmonitor`
   - **Container:** `docker exec camdx-security-server supervisorctl status xroad-opmonitor` (confirmed baked-in and running by default — see [`../container/deployment.md`](../container/deployment.md) §12/§13)
2. Confirm the internal OPMON port (`2080`) is reachable from the Security Server process itself. **`2080` is internal — never test it from a remote host, and never publish/map it to a host port merely to make this check possible.** The correct check runs in a different context per platform:
   - **Native Ubuntu/RHEL** — run directly on the Security Server host:
     ```bash
     sudo ss -lntp | grep ':2080'
     ```
   - **Container** — `2080` is internal to the Security Server container itself and is **not** published to the Docker host; running `ss` on the Docker host will not show it and is the wrong context for this check. A read-only inspection of the frozen 7.8.2 image (`docker create`/`docker cp`, no run) directly confirmed `ss` **is** present inside the image (shipped via the installed `iproute2` package), so the correct in-container check is:
     ```bash
     docker exec camdx-security-server ss -lntp | grep ':2080'
     ```
     Do not assume `ss` (or any other tool) is present in a future image build without separately re-confirming it — if it is ever found absent, do not install additional tooling merely for this check. Fall back instead to the directly-evidenced log-based signal, which requires no extra tooling at all: confirm `xroad-opmonitor` is running, then look for the query being logged:
     ```bash
     docker exec camdx-security-server supervisorctl status xroad-opmonitor
     docker logs camdx-security-server 2>&1 | grep -Ei '\[xroad-opmonitor\]|getSecurityServerOperationalData|query_data'
     ```
     A genuine query produces a log line of the form `OpMonitoringServiceHandlerImpl - Sending request to http://localhost:2080/query_data`, paired with a response-status log line — this confirms `2080` traffic is actually flowing without needing a port-level tool at all (source of this evidenced log pattern: the CamDX Sidecar Operations & Troubleshooting Runbook, §12 References below).
3. **RHEL native — a confirmed, RHEL-specific requirement:** after freshly installing `xroad-addon-opmonitoring`, `xroad-proxy` must be explicitly restarted before remote querying of operational data works — this is not automated by the RPM on a fresh install (see [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md) §18 for the full two-part evidence: direct canary observation plus scriptlet inspection showing the package's own auto-restart marking logic is upgrade-path-only). If troubleshooting a fresh RHEL install where OPMON querying does not yet work, confirm this restart has actually been performed:
   ```bash
   sudo systemctl restart xroad-proxy
   ```
4. **Ubuntu native — do not assume the RHEL finding transfers.** Whether `xroad-proxy` also needs a restart on Ubuntu is explicitly `REQUIRES VERIFICATION` (not evidenced either way) per [`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md) §12/§18. If OPMON querying does not work on a fresh Ubuntu install, treat it as an evidence-collection case (capture the exact symptom, logs, and sequence performed) rather than applying the RHEL restart as an assumed fix.
5. **Container — no equivalent restart step exists or is needed**, since OPMON runs from the container's first start rather than being installed after the fact (see [`../container/deployment.md`](../container/deployment.md) §12).
6. If local OPMON is confirmed running and reachable internally, but a remote query still fails, work through §3's layered flow (§3.6–§3.9) against the querying client's own network path to this Security Server, using `5500`/`5577` (the ports the query itself travels over, per [`../network-requirements.md`](../network-requirements.md) §7) — not port `2080`, which is internal-only.

## 7. Time / PKI troubleshooting

CamDX relies on certificates, OCSP, TSA timestamping, TLS, and Central Authority registration workflows — all of which depend on correct system time. **Include a clock-skew check whenever a certificate, registration, timestamping, or TLS-handshake symptom is being investigated**, even if time was not the first suspect. **The requirement is that the underlying host clock be correctly synchronized before PKI/certificate/OCSP/TSA/registration/TLS diagnosis proceeds — confirm that using whichever time-synchronization mechanism this specific deployment actually uses, on the correct host.**

**Execution context matters and differs by platform — run this check on the right host:**

- **Native Ubuntu/RHEL:** run directly on the Security Server host itself, since that host's own clock is what the Security Server process depends on.
- **Container:** run on the **Docker host**, not inside the Security Server container. The container's process-supervision model is Supervisor, not systemd (see [`../container/deployment.md`](../container/deployment.md) §13) — no systemd instance, `systemd-timedated`, or `chronyd` service is confirmed running inside the container, and this document does not prescribe `timedatectl`/`chronyc` *inside* the container without direct image evidence establishing such a running mechanism. It is the Docker host's clock that the containerized Security Server process actually observes (containers share the host kernel's clock), so that is the correct place to check.

Where `timedatectl` is the applicable mechanism (native Ubuntu/RHEL, or the Docker host itself):

```bash
timedatectl status
```

Where `chrony` is the installed time-sync daemon on that same host:

```bash
chronyc tracking
chronyc sources -v
```

If a different NTP client is in use on a given host, use its equivalent status command instead. **This document does not invent or hard-code an NTP server** — no specific pool/server is prescribed here; that remains an infrastructure/operator decision, consistent with every other CamDX 7.8.2 document.

**This exact class of finding is directly evidenced, not hypothetical:** the validated RHEL 9.8 production canary was directly observed with `timedatectl status` reporting `System clock synchronized: no` and `NTP service: inactive`, with `chronyc tracking`/`chronyc sources` returning `506 Cannot talk to daemon` (no active time-sync daemon running at all), alongside roughly 14 seconds of Subscription-Manager-reported clock skew (see [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md) §4). **This was classified as a real operational finding, not a release-package defect** — it does not indicate that package installation itself depends on correct time, but it directly explains why certificate/registration/timestamping work can fail or misbehave until the relevant host's time-sync daemon is confirmed active and synchronized. **Confirm that the host clock is synchronized using the deployment's configured time-synchronization mechanism before continuing PKI/registration/TLS diagnosis** — where `timedatectl` is the applicable mechanism, `System clock synchronized: yes` is the expected healthy result.

**Certificate-chain diagnosis:** use `openssl s_client` (§3.7) to inspect the actual presented chain and any handshake-level error; **never disable certificate validation in application configuration as a way to "resolve" a chain or expiry finding** (see §10) — `curl -k` may only be used, explicitly labeled, to separate a TCP/HTTP-reachability question from a trust-chain question (§3.7).

**Open, unresolved compatibility item — not a troubleshooting fix, flagged for awareness only:** an open engineering finding (`MV-GC-01`, see `evidence/2026-09-02-e1b-g3-runtime-opmon-validation.md`) notes that the current CamDX production configuration anchor is HTTPS-only and was found not directly consumable in one specific tested scenario, while a test anchor containing an HTTP-form bootstrap source succeeded (after which configuration itself downloaded over HTTPS). **Production remediation for this item is not yet decided and is out of scope for this document.** If global-configuration/anchor download fails in a way that does not match a straightforward DNS/TCP/TLS/time cause after working through §3, note this open item when escalating (§9) rather than attempting to invent a fix here.

## 8. Log sources — platform differences

| Platform | Service/process status | Logs |
|---|---|---|
| **Ubuntu / RHEL (native)** | `systemctl status <unit>` (e.g. `xroad-proxy`, `xroad-signer`, `xroad-confclient`, `xroad-opmonitor`) | `journalctl -u 'xroad-*' --no-pager --since "-1 hour"` (adjust the `--since` window as needed); `systemctl --no-pager --failed` to confirm no X-Road unit is in a failed state |
| **Container** | `docker exec camdx-security-server supervisorctl status` (Supervisor, not systemd — see [`../container/deployment.md`](../container/deployment.md) §13) | `docker logs camdx-security-server` |

**Container-specific logging detail, evidenced directly and preserved here:** the `xroad-confclient` process's `docker logs` output is tagged `[xroad-confclient-service]`, **not** `[xroad-confclient]` as the Supervisor program name would suggest — search logs for the correct tag when troubleshooting global-configuration retrieval inside a container deployment (see [`../container/deployment.md`](../container/deployment.md) §13).

**Container-specific persistence detail, evidenced directly and preserved here:** `docker logs` output and `/var/log/supervisor/` contents are **both lost on container recreation** (`docker compose up -d --force-recreate` or equivalent) — they are tied to the container's ephemeral layer, not to the persisted `/etc/xroad` named volume. If a container is about to be deliberately recreated and recent log history might be needed for an ongoing investigation, capture `docker logs` output (and any non-empty `/var/log/supervisor` files) **before** the recreation (see [`../container/deployment.md`](../container/deployment.md) §10/§19). Restart and host reboot, by contrast, preserve the existing container ID and its log history — only recreation discards it.

## 9. Diagnostic evidence bundle — before escalating to CamDX

Collect the following before opening a support case — this speeds up diagnosis significantly and avoids a back-and-forth for basic facts:

```text
Platform / OS (Ubuntu Jammy/Noble, RHEL 9, or container):
CamDX package/image version:
Target environment (Development / Production):
Source Security Server (member/environment, not a real onboarding value if this record leaves the operator's own organization):
Destination role / FQDN / IP / port:
DNS result (getent hosts, and a real-resolver dig/nslookup result if gathered):
Route result (ip route get / traceroute or tracepath):
TCP result (nc -vz or the /dev/tcp fallback — record the exact outcome: timeout, refused, or reset, per §3.6):
TLS result (openssl s_client or curl -v; note explicitly if -k/bypass was used and why):
Relevant service/process state (systemctl status / supervisorctl status):
Relevant logs (journalctl or docker logs excerpt, redacted per below):
Time-sync state (timedatectl status / chronyc tracking — on the Security Server host for native, on the Docker host for container, per §7):
Host-firewall state (firewall-cmd --list-all / ufw status verbose, or the container host's port-publishing state):
```

**Do not include in this bundle, or in anything shared externally:**

- Private keys, PINs, tokens, or passwords of any kind
- Full, unredacted configuration files containing secrets (e.g. an entire `.env` file, `db.properties`, or `local.ini` with live credentials)
- Real member-specific onboarding values, if this bundle will leave the member's own organization
- Private/internal-only IP topology not already part of the public CamDX connectivity documentation

**Redact sensitive or member-specific values from logs and command output before sharing them externally** — a log excerpt showing a certificate subject, an internal hostname, or a source IP may need redaction depending on who the bundle is being shared with; use judgment consistent with the constraints in [`../provider-connectivity.md`](../provider-connectivity.md) §6.

## 10. Prohibited / unsafe remediation patterns

**This document diagnoses. It does not publish any of the following as a troubleshooting fix, regardless of how it might appear to resolve a symptom in the moment:**

- Blanket firewall disable (`firewall-cmd --set-default-zone=trusted` or equivalent, `ufw disable`, or an unscoped zone-wide port open)
- SELinux disable (`setenforce 0`, or making SELinux permissive) — the validated RHEL baseline runs Enforcing throughout (see [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md) §8); a connectivity symptom is not evidence that SELinux itself is the cause, and disabling it is not offered here as a diagnostic shortcut
- Certificate-validation bypass presented as a fix (see §3.7/§7 — `curl -k`/an unvalidated TLS chain may be used only as a labeled diagnostic signal, never left in place as a resolution)
- Automatic package reinstall/repair (e.g. `apt install --reinstall`) as a presumed fix for a package-state problem — not validated for this package set (see [`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md) §16)
- Automatic downgrade to an earlier package/image version
- Destructive database repair (dropping/recreating a database, or an unvalidated data-repair script)
- HA failover commands — HA remains `REQUIRES VERIFICATION`; no failover procedure is documented anywhere in this initiative
- Migration/upgrade commands — Member Migration & Release Readiness remains `NOT STARTED`/gated; this document is not a migration procedure

**Any state-changing remediation that genuinely is required and is not already directly validated elsewhere in this documentation set** (for example, adding a missing, correctly source-scoped firewall rule, or restarting a specific service per §6's evidenced RHEL OPMON requirement) **must be clearly separated from pure diagnosis, and must not be invented beyond what this document or the platform-specific installation guide already documents as validated.** Where no validated remediation exists for a given finding, say so and classify it `REQUIRES VERIFICATION` rather than improvising one.

## 11. Unresolved items

None of these are guessed at or resolved by this document:

1. **Native client-proxy port standardization** (`8080`/`8443` vs. `80`/`443`) — the container's stock `8080`/`8443` exposure is a container-specific fact and is explicitly not used to resolve this native question (§5; [`../initial-configuration.md`](../initial-configuration.md) §12).
2. **`health-check-port` (`5588`) for native installs** — evidence base is container/Sidecar-specific; whether native Ubuntu/RHEL installs should also enable this endpoint remains unconfirmed (§5).
3. **Ubuntu OPMON restart-sequence completeness** — whether `xroad-proxy` also needs a restart for remote operational-data querying to function on native Ubuntu is not evidenced either way; the RHEL finding is explicitly not transferred (§6).
4. **Container remote/external OPMON mechanism** — no configuration mechanism found in the image; remains `REQUIRES VERIFICATION` (§6).
5. **`MV-GC-01` — production configuration-anchor HTTPS-only compatibility** — open engineering finding, production remediation not yet decided, out of scope for this document (§7).
6. **Authoritative FQDNs** for CamDX infrastructure services beyond the documented IP addresses — not established; see [`../network-requirements.md`](../network-requirements.md) §8.
7. **HA connectivity topology** — out of scope for this document; HA itself remains `REQUIRES VERIFICATION`.

## 12. References

- [`../network-requirements.md`](../network-requirements.md) — the authoritative CamDX infrastructure IP/port matrix; not duplicated here.
- [`../provider-connectivity.md`](../provider-connectivity.md) — provider-specific endpoint profiles; not duplicated here.
- [`../initial-configuration.md`](../initial-configuration.md) — OPMON policy (§12), CamDX-specific settings and their unresolved-port classifications.
- [`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md), [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md), [`../container/deployment.md`](../container/deployment.md) — platform-specific service/process/log commands, firewall templates, and the evidenced OPMON-restart/clock-skew findings this document draws from directly.
- `~/TI-Director-Brain/initiatives/camdx-xroad-upgrade/evidence/2026-09-18-e2-container-https-preflight.md`, `evidence/2026-09-18-e2-container-final-https-build.md` — the directly-evidenced host-vs-container DNS/`/etc/hosts` divergence case referenced in §4 (internal addresses not reproduced here).
- `~/TI-Director-Brain/initiatives/camdx-xroad-upgrade/evidence/2026-09-02-e1b-g3-runtime-opmon-validation.md` — source of the `MV-GC-01` open compatibility finding referenced in §7.
- `~/TI-Director-Brain/initiatives/camdx-xroad-upgrade/evidence/2026-09-11-e2-rhel9-final-release-validation.md` — source of the RHEL OPMON `xroad-proxy` restart finding and the clock-skew observation referenced in §6/§7.
- `~/engineering/camdx-xroad-7.8.2-release/docs/camdx-7.8.2-sidecar-operations-troubleshooting.md` — the CamDX Sidecar Operations & Troubleshooting Runbook; source of the evidenced `2080`/`getSecurityServerOperationalData` log-line pattern referenced in §6, and of the container port-binding table cross-referenced in §5; consult directly for troubleshooting detail beyond this guide's scope.
- Read-only inspection of the frozen, published container image (`docker create`/`docker cp`, never `docker run`) performed directly for this round: confirmed `ss` (via the installed `iproute2` package) and `getent` are both present in the image; confirmed `timedatectl` is present as a binary but no running systemd/`chronyd` time-sync service is evidenced inside the container (consistent with Supervisor, not systemd, being the container's process-supervision model — see [`../container/deployment.md`](../container/deployment.md) §13).

## 13. Change history

| Date | Change |
|---|---|
| 2026-09-24 | Created as part of the CamDX-Documents 7.8.2 documentation architecture modernization — a minimal generic-diagnostic placeholder (DNS, routing, TCP, TLS, local firewall, support-case checklist). |
| 2026-09-25 (round 1) | Full modernization pass, replacing the placeholder with the canonical CamDX 7.8.2 connectivity troubleshooting guide across Ubuntu, RHEL 9, and container deployments. Adopted a 12-step layered diagnostic model (source/destination role → environment → authoritative address → DNS → route → TCP → TLS → host firewall → upstream firewall/NAT/VIP → application/process → X-Road logs/status → PKI/time), explicitly ordered so no layer is skipped ahead of a firewall or certificate-validation change. Added a dedicated F5/VIP/NAT/`/etc/hosts` section, generalized from this initiative's own directly-evidenced host-vs-container DNS-divergence incident (private addresses not reproduced). Added a port-role quick-reference explicitly preserving the container-vs-native `8080`/`8443` non-transfer rule and the `5577`-is-not-a-log-collection-port fact. Added an Operational Monitoring troubleshooting section preserving the mandatory/local-default/remote-supported-alternative policy and the RHEL-specific (not Ubuntu-transferred) `xroad-proxy` restart requirement, and distinguishing remote data *retrieval* from a remote/external Opmonitor-node *topology*. Added a time/PKI section carrying forward the RHEL 9.8 canary's directly-observed unsynchronized-clock finding and the open, unresolved `MV-GC-01` anchor/HTTPS compatibility item, without inventing a fix for either. Added platform-specific log-source guidance, including the evidenced `xroad-confclient` → `[xroad-confclient-service]` container log-tag detail and the `docker logs`/`/var/log/supervisor` recreation-loss fact. Added a redaction-aware diagnostic evidence-collection bundle and an explicit list of remediation patterns this document refuses to prescribe (blanket firewall disable, SELinux disable, certificate-validation bypass as a fix, automatic reinstall/downgrade, destructive database repair, HA failover, migration procedures). |
| 2026-09-25 (round 2, this round) | Targeted platform & policy correction, following a HOLD gate on round 1's content: (1) **Fixed a remote/external OPMON policy contradiction** — §6 previously stated the remote/external Opmonitor-node topology "is documented only for the HA architecture" for native installs, which conflicted with the approved CamDX policy that this topology is a supported alternative, not HA-only. Corrected to state plainly that remote/external OPMON remains a supported alternative for native deployments, that the HA documents are cited only as one existing example/evidence source (not the exclusive definition of the topology), and that the detailed CamDX 7.8.2 standalone (non-HA) configuration procedure for it has not yet been independently validated and remains `REQUIRES VERIFICATION` — no executable remote-OPMON configuration is invented. The container path's own, separate `REQUIRES VERIFICATION` classification is preserved unchanged. (2) **Fixed the port `2080` diagnostic** — the prior single `ss -lntp | grep 2080` command was ambiguous/wrong for a container deployment if run on the Docker host, since `2080` is internal to the Security Server container and never published there. Split into an explicit native (`sudo ss -lntp | grep ':2080'`, run on the Security Server host) and container case; for the container case, a read-only inspection of the frozen 7.8.2 image (`docker create`/`docker cp`, no run) directly confirmed `ss` is present (via the installed `iproute2` package), so `docker exec camdx-security-server ss -lntp | grep ':2080'` is used, with an explicit instruction not to assume `ss` in a future image build and a directly-evidenced log-based fallback (`supervisorctl status xroad-opmonitor` plus a `docker logs` grep for the `OpMonitoringServiceHandlerImpl - Sending request to http://localhost:2080/query_data` pattern, sourced from the existing CamDX Sidecar Operations & Troubleshooting Runbook) requiring no additional tooling. Added an explicit statement that `2080` is internal, must never be tested from a remote host, and must never be published/mapped merely to troubleshoot it. (3) **Corrected DNS resolver terminology** — replaced every "known-good external resolver" reference (§3.4 table via cross-reference, §4's table and diagnostic sequence) with "resolver-authoritative-for-this-deployment," since split-horizon DNS, organization-specific views, and internal authoritative resolution can legitimately return a different, equally correct answer than a public resolver; the diagnostic sequence now explicitly determines which resolver is authoritative/intended for this deployment first, and compares against a public/external resolver only when the specific hostname is actually expected to have a public answer. (4) **Fixed the time-sync platform execution boundary** — §7 now states explicitly that native Ubuntu/RHEL checks run on the Security Server host itself, while container-deployment checks run on the **Docker host**, not inside the Security Server container; states that the container's process-supervision model is Supervisor, not systemd, and that no running systemd/`chronyd` service is confirmed inside the container (a read-only image inspection this round found the `timedatectl` binary present but no evidence of a running time-sync daemon inside the container), so `timedatectl`/`chronyc` are not prescribed *inside* the container. Softened "Confirm `System clock synchronized: yes` before troubleshooting any further" to "confirm that the host clock is synchronized using the deployment's configured time-synchronization mechanism before continuing PKI/registration/TLS diagnosis," with `System clock synchronized: yes` retained only as the expected healthy result where `timedatectl` is the applicable mechanism. No NTP server is invented. (5) **Softened the universal `getent` claim** — "available on every Linux host without an extra package" replaced with "the preferred NSS-aware baseline check on the validated Ubuntu/RHEL platforms," plus the specific, directly-evidenced fact (from this round's read-only image inspection) that `getent` is also confirmed present in the frozen container image. (6) **Corrected the HTTP-vs-HTTPS diagnostic examples** — §3.7 previously showed only an HTTPS `curl` example while describing "the Admin UI, or a health endpoint" together; the container health endpoint (`5588`) is plain HTTP, not HTTPS, in the validated deployment. Added protocol-correct examples: a normal certificate-validating `curl -v https://127.0.0.1:4000/` for the Admin UI first, `curl -vk https://127.0.0.1:4000/` only where certificate validation is intentionally and explicitly bypassed for diagnosis, and `curl -v http://127.0.0.1:5588/` for the container health endpoint, with an explicit statement that TCP `5588` must not be described as using TLS. `curl -k` remains diagnostic-only, never a fix. |
| 2026-09-26 (round 3, this round) | Non-blocking precision correction, applied after ChatGPT/operator **APPROVAL** of round 2's content: **corrected the TCP-failure interpretation in §3.6**, which previously reduced every `nc -vz` failure to "usually points at a firewall rule" — too strong a generalization. Added a table distinguishing timeout (packet filtering/silent drop, path loss, or an unresponsive endpoint — point to §3.5/§3.8/§3.9), connection refused (destination reached, nothing listening on that port, or an active reject — point to §3.10 first), and connection reset (path reached, connection actively terminated — investigate the application/load-balancer/VIP as well as policy, per §3.9/§4), and instructed operators to capture the exact `nc`/`curl`/`openssl` error text rather than paraphrasing every failure as "connection failed." Reworded §3.10 so it no longer implies refused/reset/timeout are diagnostically identical outcomes that merely "can look identical to a firewall block" — they are now stated as distinct signals pointing at different layers. Updated §9's evidence-bundle TCP-result field to ask for the exact outcome (timeout/refused/reset). No change to the layered flow's structure or step count. |
