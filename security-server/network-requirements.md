# CamDX Security Server - Network Requirements

This is the authoritative CamDX Security Server network requirements document. Confirm these rules before installation, and again if something is not connecting afterward.

## 1. IP address policy

- **Outbound**: a connection initiated from the Member Security Server toward CamDX infrastructure.
- **Inbound**: a connection initiated from CamDX infrastructure toward the Member Security Server.

Every IP address listed below for a given service is currently authorized and must be allowed in your firewall. Keep all listed addresses allowlisted; CamDX will notify you before removing one.

## 2. CamDX infrastructure connectivity (outbound: Member Security Server to CamDX)

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

## 3. CamDX infrastructure connectivity (inbound: CamDX to Member Security Server)

### 3.1 Production environment: Central Monitoring

| Service | Authorized CamDX source IP addresses | Destination ports | Protocol |
|---|---|---|---|
| Central Monitoring | `160.30.9.2`, `160.250.86.2`, `103.118.45.177`, `110.74.196.69` | `5500`, `5577` | TCP |

This inbound connectivity lets CamDX monitor the ecosystem and provide statistics/support to members. It is only required in Production; no Central Monitoring inbound connectivity is used in Development.

## 4. Generic member connectivity

| Connection | Direction | Target ports | Protocol | Notes |
|---|---|---|---|---|
| Security Server to peer Security Server | Outbound | `5500`, `5577` | TCP | Applies to both service-consumer-initiated and service-producer-initiated exchange, see §6 |
| Peer Security Server to Security Server | Inbound | `5500`, `5577` | TCP | Same ports as above |
| Consumer information system to Security Server | Inbound | Deployment-specific (HTTP/HTTPS) | TCP | Source is in the member's internal network. The exact client-proxy port depends on your deployment; confirm it as part of your CamDX configuration/onboarding if needed. |
| Security Server to producer information system | Outbound | `80`, `443`, other as agreed | TCP | Target is in the member's internal network |
| Administrator to Security Server Admin UI | Inbound | `4000` | TCP | Restrict the source to your internal/administrative network |
| Security Server to local Operational Monitoring daemon | Outbound (internal) | `2080` | TCP | Applies to the local (default) Operational Monitoring deployment; see §7 |

## 5. Network architecture guidance

- **Firewall**: restrict inbound traffic to explicitly defined sources. Do not open the ports in §2 to §4 to unrestricted source ranges.
- **Routing / NAT**: where a Security Server's public address differs from its private address (NAT), the public address is what must be reachable for peer traffic (TCP `5500`/`5577`) and the inbound flows in §3/§4.
- **FQDN / DNS**: your Security Server's registered FQDN (used in its authentication certificate and peer configuration) must resolve correctly both internally (for administrators) and externally (for peer Security Servers).
- **F5 / VIP / load balancer**: if you place a load balancer or VIP in front of a Security Server, it must transparently pass through TCP `5500`/`5577` for peer traffic.
- **Intermediary proxy**: if a reverse proxy or CDN sits in front of an HTTP(S) interface, confirm it supports the protocol behavior X-Road message exchange needs (chunked transfer, appropriate size limits).

## 6. Member-to-member (peer) connectivity model

CamDX API data exchange between members follows this path:

```
Consumer Information System
    to Consumer Security Server
    to Provider Security Server / Provider VIP
    to Provider Information System
```

Your information system does not connect directly to a provider's internal backend. All traffic is mediated by the provider's Security Server (or its VIP/load balancer). Security Server to Security Server connectivity uses TCP `5500` (message exchange) and `5577` (OCSP-related exchange) in both directions.

Provider-specific endpoint details (which address to connect to for a specific provider) are provided through the applicable CamDX service onboarding process.

## 7. Operational Monitoring connectivity

Operational Monitoring is a mandatory capability for a CamDX Security Server (see [`initial-configuration.md`](./initial-configuration.md)). Two topologies are supported:

- **Local Operational Monitoring (default)**: the Security Server reaches its own local Operational Monitoring daemon over TCP `2080` on the internal network.
- **Remote / external Operational Monitoring (supported alternative)**: the Security Server reaches a dedicated Operational Monitoring node outside the Security Server, which may serve one or more Security Servers depending on the approved topology. This is not an HA-only mechanism. Contact CamDX if you need this topology.
