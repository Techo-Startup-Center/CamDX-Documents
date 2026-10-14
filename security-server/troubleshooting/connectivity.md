# CamDX Security Server - Connectivity Troubleshooting

This is the canonical troubleshooting guide for CamDX 7.8.2 network/connectivity failures, covering Ubuntu, RHEL 9, and container deployments. It diagnoses; it does not duplicate the CamDX IP matrix, see [`../network-requirements.md`](../network-requirements.md) for that, or prescribe unvalidated remediation.

## 1. Diagnose before you change anything

Work through these in order. Do not jump straight to a firewall-rule change, a certificate-validation bypass, or a service restart before confirming which layer is actually failing.

```text
1. Identify source host, destination role, and environment (DEV or PROD)
2. Confirm the authoritative destination IP/port
3. DNS resolution where an FQDN is involved
4. Route/path check
5. TCP reachability
6. TLS handshake where TLS applies
7. Host firewall
8. Upstream firewall / NAT / VIP
9. Application/service process
10. X-Road-specific logs/status
11. PKI/time checks when certificates are involved
```

Two rules apply throughout:

- A successful ICMP `ping` is not proof that TCP/application connectivity works. Use `ping` only as a limited, early routing signal.
- Do not start with a firewall-rule change. Confirm DNS, routing, and TCP-level behavior first.

## 2. Before you start: evidence to gather

| Field | Notes |
|---|---|
| Platform | Ubuntu (Jammy/Noble), RHEL 9, or container |
| CamDX package/image version | |
| Environment | Development or Production. The two environments use different CamDX infrastructure addresses, see [`../network-requirements.md`](../network-requirements.md) |
| Source host role | Security Server itself, an administrator's workstation, a consumer information system, a provider information system |
| Destination role | Central Server / Management Security Server / TSA / OCSP / Central Monitoring / peer Security Server / provider endpoint / Admin UI / OPMON daemon |
| Destination FQDN/IP/port | Look up the authoritative value in [`../network-requirements.md`](../network-requirements.md) rather than a cached or guessed value |
| Timestamp of the observed failure | |
| Observed error (exact text) | |

## 3. DNS resolution

```bash
getent hosts <hostname>
```

Where available, confirm against a direct query:

```bash
dig +short <hostname>
# or, if dig is unavailable:
nslookup <hostname>
```

If `getent hosts` returns something unexpected (an internal/private address where a public CamDX address was expected, or a different address than a direct DNS query returns), check for a local `/etc/hosts` override (§8) before concluding the DNS server itself is broken.

## 4. Route/path check

```bash
ip route get <destination-ip>
```

```bash
traceroute <destination-ip-or-hostname>
# or, if unavailable:
tracepath <destination-ip-or-hostname>
```

Treat the last responding hop as an approximate signal, not a definitive fault location; some networks suppress ICMP responses at intermediate hops without that indicating a fault there.

## 5. TCP reachability

```bash
nc -vz <destination-ip-or-hostname> <port>
```

If `nc` is unavailable:

```bash
timeout 5 bash -c "cat < /dev/null > /dev/tcp/<destination-ip-or-hostname>/<port>" && echo "OPEN" || echo "CLOSED/FILTERED"
```

For a locally listening service:

```bash
ss -lntp
```

Capture the exact result, it is diagnostic:

| Result | Usually means | Where to look next |
|---|---|---|
| Timeout | Packet filtering that silently drops, a routing issue, or an unresponsive endpoint | Route check (§4), host firewall (§7), upstream firewall/NAT/VIP (§8) |
| Connection refused | The host was reached, but nothing is listening on that port, or an active reject occurred | Is the expected service actually running (§9)? Then §7/§8 only if the process is confirmed running |
| Connection reset | The path was reachable, but something actively terminated the connection, possibly the application, a load balancer/VIP, or a stateful firewall | Upstream firewall/NAT/VIP (§8), application behavior (§9), the destination's own logs |

## 6. TLS handshake (where TLS applies)

Only after §5 confirms the TCP port itself is reachable.

```bash
openssl s_client -connect <hostname>:<port> -servername <hostname> </dev/null
```

For an HTTPS endpoint such as the Admin UI, prefer a certificate-validating request first:

```bash
curl -v https://127.0.0.1:4000/
```

Only bypass certificate validation where doing so is intentional and clearly labeled as diagnostic-only, for example to confirm the HTTP layer itself responds even though the certificate is expired or untrusted:

```bash
curl -vk https://127.0.0.1:4000/
```

For the container health endpoint (`5588`), which is plain HTTP, not HTTPS:

```bash
curl -v http://127.0.0.1:5588/
```

Never leave certificate validation disabled as a fix; `-k`/an unvalidated chain is a diagnostic signal only.

## 7. Host firewall

**RHEL (`firewalld`):**

```bash
sudo firewall-cmd --list-all
```

**Ubuntu, if `ufw` is in use:**

```bash
sudo ufw status verbose
```

**Container:** the image does not run its own host firewall; enforcement happens on the Docker host. Confirm which interface a port is actually published on:

```bash
docker port camdx-security-server
```

A rule present but scoped to the wrong source produces the same symptom as a missing rule. Check the actual source, not just whether a rule with the right port number exists. See your platform's installation guide for the firewall rule template if a genuinely missing rule needs to be added.

## 8. Upstream firewall / NAT / VIP / `/etc/hosts`

A local `/etc/hosts` mapping can silently redirect the Security Server to a different address than DNS would otherwise resolve. Never assume a hostname resolves the same way on every host, or the same way inside a container as on its Docker host.

1. Determine which DNS resolver is authoritative for this deployment, and query it directly.
2. Compare that result against `getent hosts <hostname>` on the affected host. If they differ, inspect `/etc/hosts` for a static entry.
3. If a static entry exists, determine whether it is a deliberate, documented, temporary workaround, or an accidental leftover. Any such override must be treated as explicitly temporary and documented.
4. If a load balancer/VIP is in the path, confirm whether the address being tested is the VIP's own address or an individual backend server behind it. A VIP performing Layer-4 passthrough should forward TCP `5500`/`5577` transparently.
5. If a container is involved, remember it has its own independent `/etc/hosts` and DNS resolution, separate from its Docker host:
   ```bash
   docker exec camdx-security-server getent hosts <hostname>
   ```

Use placeholders for any real member-specific VIP address, private topology, or internal CamDX infrastructure address in a public or unapproved channel when escalating a case of this kind. See §14 for sharing real network details with CamDX through an approved support channel when CamDX requests them.

## 9. Application / service status

Confirm the destination service itself is actually running before concluding the network path is at fault.

- **Native Ubuntu/RHEL:** `systemctl status <unit>` (e.g. `xroad-proxy`, `xroad-signer`, `xroad-confclient`, `xroad-opmonitor`)
- **Container:** `docker exec camdx-security-server supervisorctl status`

## 10. X-Road-specific logs

- **Native:** `journalctl -u 'xroad-*' --no-pager --since "-1 hour"` (adjust the window as needed); `systemctl --no-pager --failed` to confirm no X-Road unit is in a failed state.
- **Container:** `docker logs camdx-security-server`. The `xroad-confclient` process is tagged `[xroad-confclient-service]` in `docker logs`, not `[xroad-confclient]`; search for the correct tag.

`docker logs` output and `/var/log/supervisor/` are both lost on container recreation (not on restart or host reboot). Capture them first if recent history might be needed before a deliberate recreation.

## 11. Time / PKI

Certificates, OCSP, timestamping, TLS, and Central Authority registration all depend on correct system time. Include a clock-skew check whenever investigating any of these symptoms.

- **Native Ubuntu/RHEL:** run on the Security Server host itself.
- **Container:** run on the Docker host, not inside the Security Server container; the container shares the Docker host's kernel clock.

```bash
timedatectl status
```

Where `chrony` is the installed time-sync daemon:

```bash
chronyc tracking
chronyc sources -v
```

## 12. Port reference

| Port | Role | Applies to |
|---|---|---|
| `4000` | Admin UI | Native and container |
| `5500` | Security Server peer traffic | Native and container |
| `5577` | Security Server peer traffic, OCSP-related, not a log-collection port | Native and container |
| `8080` / `8443` | Consumer information-system / client-proxy path | The exact ports your deployment uses are deployment-specific; confirm with CamDX during onboarding if unsure |
| `5588` | Health-check endpoint | Container, bound to `127.0.0.1` by default |
| `2080` | Security Server to local Operational Monitoring daemon (internal) | Native and container, local OPMON topology only |

## 13. Operational Monitoring troubleshooting

1. Confirm the local OPMON process is running:
   - **Native:** `systemctl status xroad-opmonitor`
   - **Container:** `docker exec camdx-security-server supervisorctl status xroad-opmonitor`
2. `2080` is internal; never test it from a remote host or publish it to a host port.
   - **Native:** `sudo ss -lntp | grep ':2080'`
   - **Container:** `docker exec camdx-security-server ss -lntp | grep ':2080'`
3. **RHEL native:** after freshly installing `xroad-addon-opmonitoring`, `xroad-proxy` must be explicitly restarted before remote querying of operational data works:
   ```bash
   sudo systemctl restart xroad-proxy
   ```
4. **Container:** no equivalent restart is needed; OPMON runs from the container's first start.
5. If local OPMON is confirmed running and reachable internally but a remote query still fails, work through §5 to §8 against the querying client's own network path, using `5500`/`5577`, not `2080`.

If your deployment requires a remote/external Operational Monitoring topology, contact CamDX.

## 14. Diagnostic evidence bundle, before escalating to CamDX

```text
Platform / OS:
CamDX package/image version:
Target environment (Development / Production):
Destination role / FQDN / IP / port:
DNS result:
Route result:
TCP result (exact outcome: timeout, refused, or reset):
TLS result (note explicitly if -k/bypass was used and why):
Relevant service/process state:
Relevant logs (redacted per below):
Time-sync state:
Host-firewall state:
```

**Never include, in this bundle or anything shared externally:**

- Private keys, PINs, tokens, or passwords of any kind.
- Full, unredacted configuration files containing secrets.
- Real member-specific onboarding values, if this bundle will leave your organization.

Do not post real internal IPs, VIP addresses, or private network topology in public or unapproved channels. When troubleshooting routing, firewall, NAT, DNS, or VIP issues, CamDX may request the minimum network details actually needed through an approved support channel; share only what is requested, and only through that channel.

## 15. Unsafe actions to avoid

This document never prescribes any of the following as a fix:

- Blanket firewall disable, or an unscoped zone-wide port open.
- Disabling SELinux (`setenforce 0`, or making it permissive).
- Certificate-validation bypass left in place rather than used as a labeled diagnostic signal.
- Automatic package reinstall/repair as a presumed fix for a package-state problem.
- Automatic downgrade to an earlier package/image version.
- Destructive database repair (dropping/recreating a database, or an unvalidated data-repair script).
- HA failover commands.
- Migration/upgrade commands.

If a genuinely required remediation is not already documented in your platform's installation guide, contact CamDX rather than improvising one.

## 16. References

- [`../network-requirements.md`](../network-requirements.md), [`../initial-configuration.md`](../initial-configuration.md).
- [`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md), [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md), [`../container/deployment.md`](../container/deployment.md).
- [Troubleshooting index](./README.md), [Error reference](./error-reference.md).
