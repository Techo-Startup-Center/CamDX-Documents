# CamDX Security Server — Network Requirements

```text
CamDX infrastructure IP/port matrix: CURRENT / OPERATOR-CONFIRMED
Generic member/client-side port guidance: PARTIALLY VERIFIED
FQDNs and future address-removal notices: PENDING AUTHORITATIVE CONFIRMATION
```

```text
Applies to: CamDX Development and Production environments
Scope: CamDX Member Security Server connectivity
Software dependency: Version-independent unless explicitly stated
Last reviewed: 2026-09-24
```

This is the **single authoritative CamDX Security Server network requirements document**. All CamDX Security Server installation guides (Ubuntu, RHEL, container) must link here for CamDX infrastructure connectivity rather than embedding their own copies of these tables.

This document does **not** list individual API Provider Security Server endpoints. For provider-specific connectivity (a specific ministry's or member's externally reachable Security Server/VIP), see [`provider-connectivity.md`](./provider-connectivity.md).

## 1. Terminology and IP address policy

- **Outbound** — a connection initiated *from* the Member Security Server *toward* CamDX infrastructure.
- **Inbound** — a connection initiated *from* CamDX infrastructure *toward* the Member Security Server.

**CamDX IP addresses to allow:** for each CamDX service below, every listed IP address is currently authorized and must be allowed/allowlisted. This document does **not** classify individual addresses as "current," "transition," "old," "new," "previous," "replacement," "deprecated," or "retiring" — every address listed for a given service is simply an **authorized CamDX IP address** for that service today.

**Allowlist policy:** all CamDX IP addresses listed in this document should remain allowlisted for the applicable service and environment. CamDX may issue a future notice removing one or more addresses. Until such a notice is issued, members should retain **all** listed addresses in their firewall/allow-list configuration. Members must not remove an address merely because multiple addresses are listed for the same service — a longer list is not evidence that any particular entry is about to be removed. No retirement date is asserted anywhere in this document; none is invented.

## 2. CamDX infrastructure connectivity (outbound: Member Security Server → CamDX)

### 2.1 Development environment

| Service | Authorized CamDX IP addresses | Ports | Protocol |
|---|---|---|---|
| Central Server | `160.30.9.210`, `103.216.51.117` | `4001`, `443` | TCP |
| Management Security Server | `160.30.9.210`, `103.118.47.131` | `5500`, `5577` | TCP |
| Timestamping Service | `160.30.9.210`, `103.216.51.117` | `10000` | TCP |
| OCSP Service | `160.30.9.210`, `103.216.51.117` | `10000` | TCP |

### 2.2 Production environment

| Service | Authorized CamDX IP addresses | Ports | Protocol |
|---|---|---|---|
| Central Server | `160.30.9.73`, `103.118.45.170`, `110.74.196.74` | `4001`, `443` | TCP |
| Management Security Server | `160.30.9.77`, `110.74.196.75`, `110.74.196.68` | `5500`, `5577` | TCP |
| Timestamping Service | `160.30.9.73`, `103.118.45.170`, `110.74.196.74` | `443` | TCP |
| OCSP Service | `160.30.9.73`, `103.118.45.170`, `110.74.196.74` | `443` | TCP |

## 3. CamDX infrastructure connectivity (inbound: CamDX → Member Security Server)

### 3.1 Production environment — Central Monitoring

| Service | Authorized CamDX source IP addresses | Destination ports on the Member Security Server | Protocol |
|---|---|---|---|
| Central Monitoring | `160.30.9.2`, `160.250.86.2`, `103.118.45.177`, `110.74.196.69` | `5500`, `5577` | TCP |

Direction, stated explicitly: **Outbound** = Member Security Server → CamDX (§2 above). **Inbound** = CamDX Central Monitoring → Member Security Server (this section). This inbound connectivity is required so the CamDX Operator can monitor the ecosystem and provide statistics/support to Members, and is only relevant in Production.

### 3.2 Development environment — Central Monitoring

Not applicable — no Central Monitoring inbound connectivity is used in the Development environment, consistent with the legacy standalone guides (`N/A` in both source documents).

## 4. Generic member connectivity

| Connection | Direction | Target ports | Protocol | Notes |
|---|---|---|---|---|
| Security Server → peer Security Server (data exchange partner) | Outbound | `5500`, `5577` | TCP | Applies to both service-consumer-initiated and service-producer-initiated peer exchange; see §6 |
| Peer Security Server → Security Server | Inbound | `5500`, `5577` | TCP | Same ports as above; peer/server-to-server X-Road protocol and OCSP-related traffic (see §6) |
| Consumer information system → Security Server | Inbound | `80`/`8080` (HTTP), `443`/`8443` (HTTPS) | TCP | Source is in the member's internal network. **Exact client-proxy port is deployment-specific — see §8, status REQUIRES VERIFICATION.** |
| Security Server → producer information system | Outbound | `80`, `443`, other as agreed | TCP | Target is in the member's internal network |
| Administrator → Security Server Admin UI | Inbound | `4000` | TCP | Source should be restricted to the internal/administrative network |
| Security Server → local Operational Monitoring daemon | Outbound (internal) | `2080` | TCP | Source is in the internal network. Applies to the local (default) Operational Monitoring deployment model; a remote/external Operational Monitoring deployment instead reaches its dedicated node over the network — see [`initial-configuration.md`](./initial-configuration.md) §12 for the local-vs-remote Operational Monitoring policy. |

These generic rules are sourced from the CamDX legacy Ubuntu and RHEL standalone guides' network-ports tables, which were consistent with each other on every row except the consumer-information-system inbound port (Ubuntu documented `80, 443`; RHEL documented `8080, 8443`) — flagged explicitly in §8 as the one genuinely unresolved item in this table, not silently picked.

## 5. Network architecture guidance

- **Firewall:** restrict inbound traffic to explicitly defined sources wherever possible; do not open the ports in §2–§4 to unrestricted source ranges. Both outbound and inbound rules should be scoped as narrowly as the environment allows.
- **Routing / NAT:** where a Security Server's public address differs from its private address (NAT), the *public* address is what must be reachable for peer Security Server traffic (TCP `5500`/`5577`) and any inbound flows in §3/§4. Where NAT or a VIP is used, ensure the externally reachable Security Server/VIP address and the actual observed source address are correctly reflected in firewall and provider allow-list rules.
- **FQDN / DNS:** a Security Server's registered FQDN (used in its authentication certificate and in peer configuration) must resolve correctly both internally (for administrators) and externally (for peer Security Servers), consistent with however the member's DNS/NAT is architected.
- **`/etc/hosts`:** a static hosts-file override is sometimes used as a temporary workaround when DNS is not yet fully in place (for example, during initial bring-up before public DNS propagates). Any such override must be treated as explicitly temporary and documented, not left as an undocumented permanent fixture — this exact situation has occurred previously in CamDX's own infrastructure history and should not be repeated silently.
- **F5 / VIP / load balancer:** where a member or CamDX places a load balancer or VIP in front of a Security Server (or Security Server cluster, see the HA documents), the load balancer must transparently pass through TCP `5500`/`5577` for peer traffic; source-IP-based rules on the CamDX or provider side should account for whichever address the peer actually observes as the origin (the VIP's address, if source NAT is applied by the load balancer).
- **Intermediary proxy:** if any intermediary reverse proxy or CDN sits in front of an HTTP(S)-based interface (e.g. a REST API interface consumers reach), confirm it supports the required protocol behavior for X-Road message exchange (chunked transfer, appropriate size limits) rather than assuming a generic web-proxy configuration is sufficient.
- **Source/destination interpretation:** every row in §2–§4 states its direction explicitly (Outbound = initiated by the Member Security Server; Inbound = initiated by CamDX or a peer). Do not assume symmetry — a service being reachable outbound does not imply the reverse direction is required or permitted.
- **Address-list handling:** apply **every** address listed for a given service in §2–§3, per the allowlist policy in §1. Do not remove any listed address unilaterally.

## 6. Member-to-member (peer) connectivity model

CamDX API data exchange between members follows this general path:

```
Consumer Information System
        ↓
Consumer Security Server
        ↓
Provider Security Server / Provider VIP
        ↓
Provider Information System
```

The consumer's information system does **not** normally connect directly to the provider's internal backend application server — all traffic is mediated by the provider's Security Server (or its VIP/load balancer, if the provider operates one). Generic Security Server-to-Security Server connectivity uses TCP `5500` (message exchange) and `5577` (OCSP-related exchange) in both directions, per §4 — this reflects standard X-Road Security Server behavior and is consistent with CamDX's own documented port usage.

Provider-specific public destination IP/FQDN information (i.e. *which* address a consumer should actually connect to in order to reach a specific provider's Security Server) is maintained separately in [`provider-connectivity.md`](./provider-connectivity.md), not in this document.

## 7. Operational Monitoring connectivity

Operational Monitoring is a **mandatory** capability for a CamDX Security Server deployment (see [`initial-configuration.md`](./initial-configuration.md) §12 for the full policy). Two supported topologies exist:

- **Local Operational Monitoring (default topology):** the Security Server reaches its own local Operational Monitoring daemon over `TCP 2080` on the internal network (§4).
- **Remote / external Operational Monitoring (supported alternative topology):** the Security Server instead reaches a dedicated, shared Operational Monitoring node — see the HA documents for the one topology currently documented using this model. The specific network path to a remote/external Operational Monitoring node is deployment-specific and is documented alongside that deployment's own architecture, not duplicated here.

The relevant deployment guide for a given Security Server should specify explicitly which of the two models is in use.

## 8. Items requiring confirmation

The CamDX infrastructure IP/port matrix in §2–§3 above is operator-confirmed and authoritative for this documentation round — it is not flagged for re-verification. The following, narrower items remain genuinely unresolved:

1. **Consumer-information-system inbound port** — the legacy Ubuntu guide lists `80, 443`; the legacy RHEL guide lists `8080, 8443`. §4 reproduces both as a flagged discrepancy rather than silently picking one. **Status: REQUIRES VERIFICATION.**
2. **Authoritative FQDNs** for the Central Server, Management Security Server, Timestamping Service, OCSP Service, and Central Monitoring — no canonical FQDN evidence was available to this task; only IP addresses are documented. **Status: PENDING AUTHORITATIVE CONFIRMATION.** If/when FQDNs are confirmed, they should be added here in a structured table (Service / Environment / FQDN / IP addresses / Protocol / Ports / Purpose).
3. **Future address-removal notices** — none has been issued for any address in §2–§3. Any future CamDX notice removing a specific address should be reflected here once issued, with the notice referenced, not anticipated in advance. **Status: PENDING AUTHORITATIVE CONFIRMATION.**

## 9. Change history

| Date | Change |
|---|---|
| 2026-09-24 | Initial canonical network-requirements document established as part of the CamDX-Documents 7.8.2 documentation architecture modernization. Consolidated CamDX infrastructure connectivity previously duplicated across the legacy Ubuntu and RHEL standalone guides. |
| 2026-09-24 | Review pass: no corrections required at that time; full matrix independently verified exact against the authoritative values supplied. |
| 2026-09-24 | Policy correction round (final operator decision): replaced the "current infrastructure IP" vs. "transition IP" address classification with a single union model — every address listed for a service is simply an authorized CamDX IP address for that service, with no implied chronology; added the explicit allowlist-retention policy (§1); removed the historical private-lab NAT/VIP example previously referenced from the legacy Ansible illustration, replaced with generic NAT/VIP guidance (§5); added an explicit Operational Monitoring connectivity section (§7) reflecting the mandatory/local-default/remote-supported-alternative policy; reworded the document status model to distinguish the operator-confirmed CamDX infrastructure matrix (no longer flagged as unverified) from the genuinely unresolved items (client-proxy port ambiguity, FQDNs, future removal notices). No IP or port value was changed by this policy round. |
