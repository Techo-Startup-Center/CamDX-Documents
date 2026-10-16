# CamDX Security Server - HA Deployment Profile

Complete this profile before starting a native HA installation ([Ubuntu](./ubuntu/high-availability-installation.md) or [RHEL](./rhel/high-availability-installation.md)). It is a working checklist for your own deployment, not a document you submit to CamDX, except where a row below says otherwise. Keep it with your deployment records; the installation guides refer back to specific rows by name.

**What this profile governs:** this is the member's own deployment worksheet and source of truth for the values the runbook uses. CamDX confirms only the CamDX-controlled values in §1, and authorizes use of the HA architecture at Checkpoint A. Member-owned infrastructure choices (§2, §5) remain the member's own responsibility as long as they satisfy the documented architectural requirement in each row's Notes/Requirement column. CamDX does not individually approve ordinary member-owned choices such as the load-balancer vendor, internal hostnames, or `firewalld` zone names, unless they represent a deviation from the documented architecture; see the "Approved architectural deviation(s)" row in §1 for that case specifically.

STOP and do not start the installation guide's Phase 1 until every CamDX-provided/CamDX-confirmed row is filled in and every required member-owned row has a value that satisfies the requirement in its Notes/Requirement column.

## 1. CamDX-provided / CamDX-confirmed information

These values come from CamDX as part of your onboarding, or require explicit CamDX confirmation before you proceed.

| Field | Your value | Notes |
|---|---|---|
| Environment | | Development or Production |
| Member Name | | |
| Member Class | | e.g. `GOV`, `COM` |
| Member Code | | |
| Security Server Code | | Provided by CamDX for this HA pair. Both nodes share this one code; the secondary is never given its own. |
| Configuration anchor URL | | Per environment, see [Initial Configuration](./initial-configuration.md) |
| Registration/onboarding status confirmed | | Confirm with CamDX that this member/environment is authorized to proceed with an HA deployment (Checkpoint A) |
| Operational Monitoring topology | | Local (default) unless CamDX has separately approved a remote/external topology for this deployment |
| Approved architectural deviation(s), if any | | Leave blank if none. Any deviation from the standard native HA procedure in the installation guides must be confirmed with CamDX before you build it. |

## 2. Member-owned infrastructure information

These are your own infrastructure decisions. CamDX does not supply these values; you choose them to satisfy the stated requirement, consistent with your organization's own network/security policy.

| Field | Your value | Requirement it must satisfy |
|---|---|---|
| Primary hostname/FQDN | | Resolvable by both nodes and by your administrators |
| Primary private IP | | Reachable by the secondary and by the load balancer |
| Secondary hostname/FQDN | | Resolvable by both nodes and by your administrators |
| Secondary private IP | | Reachable by the primary and by the load balancer |
| VIP/load-balancer FQDN | | The single, logical Security Server external address; used for the authentication-certificate CSR and registration, never either node's own private FQDN |
| VIP/public IP, if applicable | | Matches your organization's own network design |
| Administrator CIDR(s) (`<ADMIN_CIDR_1>`, `<ADMIN_CIDR_2>`, ...) | | Your own approved administration network(s); restricts TCP `4000`. Number them if there is more than one; the runbooks add one rich rule per CIDR, never a single combined range. |
| Secondary's replication/SSH source CIDR as seen by the primary (`<SECONDARY_SOURCE_CIDR>`) | | The address the primary actually observes from the secondary for both SSH (`22`) and `serverconf` replication (`5433`); confirm this is not altered by any NAT between the two nodes before using it in `pg_hba.conf` or a firewall rule. Do not assume this always equals the secondary's own configured private IP; record what the primary actually sees. Record it as a CIDR (for example a `/32` for a single host). |
| Load-balancer health-check source CIDR(s) (`<LB_HEALTHCHECK_CIDR_1>`, ...) | | The address(es) your load balancer uses to poll TCP `5588`; restrict health-check access to this range only. Number them if there is more than one. |
| Consumer information-system source network(s) | | Per your own integration; restricts the internal client-proxy port |
| Client-proxy port(s) in use | | Confirm from your own deployment configuration; see [Network Requirements](./network-requirements.md) |
| Outbound NAT/public source IP behavior | | Needed if a provider allowlist must be updated for this Security Server's observed source address |
| DNS resolver(s) | | Must resolve consistently on both nodes |
| NTP source | | Both nodes must stay in sync with each other and with real time |
| Load-balancer platform/product | | Must support Layer 4/TCP passthrough with no TLS termination |

## 3. Derived during installation

Do not fill these in before you start. Each installation guide phase tells you when to record the value here, and later phases refer back to it.

| Field | Your value | Recorded at |
|---|---|---|
| Resolved PostgreSQL major version (`<PG_MAJOR>`), confirmed identical on both nodes | | Ubuntu HA Phase 4 / RHEL HA Phase 4 |
| Actual PostgreSQL config/data paths | | Ubuntu HA Phase 6 / RHEL HA Phase 6 |
| Replication certificate node names | | Ubuntu HA Phase 5 / RHEL HA Phase 5 |
| Replication role name(s) | | Ubuntu HA Phase 6 / RHEL HA Phase 6 |
| `serverconf` database role password (store in your organization's secret storage, not here) | | Ubuntu HA Phase 6 / RHEL HA Phase 6; reused on the secondary's `db.properties` |
| Actual service/unit names, where package layout determines them | | As encountered during the procedure |

## 4. References

- [Ubuntu HA Installation](./ubuntu/high-availability-installation.md), [RHEL HA Installation](./rhel/high-availability-installation.md).
- [Network Requirements](./network-requirements.md), [Deployment Model Selector](./deployment-models.md).

## 5. RHEL-specific infrastructure fields

These apply only to a RHEL 9 HA deployment. The RHEL HA runbook's `firewalld` commands reference these fields directly; do not substitute an undefined placeholder for any of them.

| Field | Your value | Requirement it must satisfy |
|---|---|---|
| Primary `firewalld` zone (`<PRIMARY_ZONE>`) | | The zone the primary node's relevant interface is already assigned to |
| Secondary `firewalld` zone (`<SECONDARY_ZONE>`) | | The zone the secondary node's relevant interface is already assigned to |
| Secondary's replication/SSH source CIDR | | Same value as `<SECONDARY_SOURCE_CIDR>` in §2; the RHEL runbook's `firewalld` rules for TCP `22` and `5433` on the primary use this same recorded value, not the secondary's raw private IP |
| Primary backend data-plane source CIDR(s) for `5500`/`5577` and the client-proxy port (`<PRIMARY_BACKEND_DATA_PLANE_CIDR_1>`, `<PRIMARY_BACKEND_DATA_PLANE_CIDR_2>`, ...) | | The address(es) the primary actually observes after your load balancer's own source/NAT behavior; do not assume the load balancer preserves the original client address. Number them if there is more than one; the runbook adds one rich rule per CIDR rather than a single combined range. |
| Secondary backend data-plane source CIDR(s) for `5500`/`5577` and the client-proxy port (`<SECONDARY_BACKEND_DATA_PLANE_CIDR_1>`, `<SECONDARY_BACKEND_DATA_PLANE_CIDR_2>`, ...) | | The address(es) the secondary actually observes after your load balancer's own source/NAT behavior. May be identical to the primary's values if the load balancer presents the same source to both nodes, but record it as its own field; NAT/source behavior can differ by node and must not be assumed equal. Number them if there is more than one. |
| Trusted SSH host-key fingerprint for the primary (`SHA256:...`) | | Recorded independently of the HA installation itself (for example, when the primary host was provisioned), and used in the installation guide's SSH host-key verification step; never accepted from the connection attempt itself |

Do not create a generic provider-endpoint registry from this table; it records only the addressing facts this specific HA pair's own `firewalld` rules need.
