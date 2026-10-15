# CamDX Security Server - Deployment Model Selector

This document helps a member choose among the CamDX Security Server deployment models. It does not duplicate installation steps; each model links to the guide that owns its procedure. It does not authorize moving an existing member from one model to another; see [Upgrade and Migration](./upgrade/README.md) for the approved migration path.

## 1. State persistence applies to every model

Containerization reduces deployment and environment variability. It does not make the Security Server stateless. Whichever model you run, the Security Server carries the same categories of state, with different backup requirements:

- **Durable, must be backed up:** member/subsystem identity and Security Server Code, AUTH/SIGN key material and certificates, `serverconf`, and `messagelog`/Operational Monitoring data.
- **Rebuildable, not a backup candidate:** the OCSP response cache and the global-configuration cache both regenerate on their own and are not restored from backup.
- **Separately managed:** message-log archive files and other cache/archive classes have their own retention model; see [Container Production Hardening Checklist](./container/production-hardening-checklist.md).

Choosing a deployment model changes how this state is packaged and operated. It does not remove the requirement to plan backup, retention, and recovery for the durable state above.

## 2. Quick comparison

| Model | Intended use | Status | Member must coordinate with CamDX? |
|---|---|---|---|
| A. Ubuntu native standalone | General-purpose new deployment | Supported | No, for standalone deployment |
| B. RHEL native standalone | Institutional/security-policy-driven new deployment | Supported | No, for standalone deployment |
| C. Container standalone | Greenfield deployment with mature container operations | Supported for teams with mature container operations | No, for standalone deployment |
| D. Independent Security Servers (simple redundancy) | Redundancy without shared-state replication | Not a standard approved CamDX deployment offering today | Yes, contact CamDX before implementation |
| E. Replicated external-load-balancer HA cluster | Existing members' established HA architecture | Existing deployments remain supported | Yes, for a new deployment, an upgrade of an existing HA deployment, or a topology change |
| F. Container/Kubernetes HA | Cloud-native HA for container-mature members | Not currently a standard CamDX deployment option | Yes, contact CamDX before implementation |

Models D, E, and F are not interchangeable. They have different failure characteristics and operational complexity; see §6-§8.

## 3. Model A - Ubuntu native standalone

- **Intended use:** a general-purpose choice for a new member with no specific RHEL requirement.
- **Deployment form:** native `apt`-managed packages on Ubuntu 22.04 (Jammy) or 24.04 (Noble); local or remote PostgreSQL.
- **Operational complexity:** standard systemd service management; host OS patching is the member's own responsibility.
- **HA/redundancy:** none built in; see §6-§8 for redundancy options.
- **Status:** Supported.
- **Procedure:** [Ubuntu Standalone Installation](./ubuntu/standalone-installation.md).

## 4. Model B - RHEL native standalone

- **Intended use:** members whose institutional infrastructure or security policy requires RHEL.
- **Deployment form:** native `dnf`-managed packages on RHEL 9, with SELinux Enforcing as the supported baseline (not disabled); EPEL required for one dependency.
- **Operational complexity:** `firewalld`/SELinux-specific operational knowledge required.
- **HA/redundancy:** none built in; see §6-§8.
- **Status:** Supported.
- **Procedure:** [RHEL Standalone Installation](./rhel/standalone-installation.md).

## 5. Model C - Container standalone

- **Intended use:** a greenfield deployment where the member's own operations are already container-native and mature. Not a universal replacement for native installation, and not a recommended migration target for an existing stable native Security Server.
- **Deployment form:** a single digest-pinned container image on a Docker host (`linux/amd64`), with Operational Monitoring and the messagelog archiver already running by default.
- **State/persistence model:** `/etc/xroad` (identity, keys, configuration) and the database each have their own named Docker volume. Message-log archive files, and `docker logs`/supervisor output, are not durable across container recreation unless separately collected; see the [Container Deployment](./container/deployment.md) guide and the [Production Hardening Checklist](./container/production-hardening-checklist.md).
- **Operational complexity:** requires a team already comfortable with container lifecycle management (image pinning, volume/persistence discipline, log retention, Docker-host hardening). Several production-hardening items (backup/restore rehearsal, HSM/PKCS#11 in this context, container HA) require coordination with CamDX; see the checklist.
- **HA/redundancy:** not covered by this model; see Model F.
- **Status:** Supported for teams with mature container operations.
- **Procedure:** [Container Deployment](./container/deployment.md).

## 6. Model D - Independent Security Servers (simple redundancy)

- **Intended use:** redundancy without the replication/failover complexity of the clustered HA architecture (Model E): two or more Security Servers, each with its own distinct Security Server Code and independent state, each carrying live traffic, with traffic steering handled by the member's own load balancer or DNS.
- **Deployment form:** each Security Server deployed and registered independently (any combination of Models A/B/C).
- **Operational complexity:** no shared-state replication to secure or operate, but each Security Server is independently configured, patched, registered, and monitored; consumers/providers may see two distinct Security Server Codes rather than one.
- **HA/redundancy:** reduces failure-mode surface area compared to Model E by avoiding shared-state replication, at the cost of a single logical identity.
- **Status:** Not currently a standard approved CamDX deployment offering. Contact CamDX before implementation.
- **Provider-side boundary:** if this model is used by a service provider, direct X-Road peer-selection behavior across the provider's multiple Security Server Codes must be confirmed with CamDX. Member-side load-balancer or DNS steering must not be assumed to also govern provider-side peer selection.
- **CamDX does not recommend this when:** the member specifically requires a single logical Security Server Code across the pair (Model E instead).

## 7. Model E - Replicated external-load-balancer HA cluster

- **Intended use:** a single logical Security Server identity replicated across primary and secondary nodes, behind an external load balancer. This is CamDX's established, in-use HA architecture.
- **Deployment form:** primary/secondary pair; a dedicated `serverconf` PostgreSQL instance with streaming replication; scheduled synchronization of the remaining shared state; an external Layer-4/TLS-passthrough load balancer. See [Ubuntu HA](./ubuntu/high-availability-installation.md) and [RHEL HA](./rhel/high-availability-installation.md).
- **Operational complexity:** materially more complex than Model D: requires PostgreSQL replication expertise and careful state-replication scope. Failover/primary promotion is a manual operation, not automatic; this architecture prioritizes load balancing, not full fault tolerance.
- **HA/redundancy:** a single logical Security Server Code for consumers and providers.
- **Status:** Existing CamDX deployments using this architecture remain supported, and it is not deprecated. For a new HA deployment, an upgrade of an existing HA deployment, or a topology change, coordinate with CamDX before implementation.
- **CamDX does not recommend this when:** the member would be satisfied with Model D's simpler redundancy and does not need a single logical Security Server Code.

## 8. Model F - Container/Kubernetes HA

- **Intended use:** members who are both container-native (Model C) and want an orchestrated, cloud-native HA topology.
- **Deployment form:** a Kubernetes cluster running a primary/secondary pod architecture, with an external PostgreSQL instance shared across pods, not a per-pod local volume. Primary-to-secondary configuration synchronization still exists in this shape; Kubernetes automates pod lifecycle, readiness, scaling, and load-balancer membership, but does not eliminate the synchronization mechanism itself.
- **Operational complexity:** mature Kubernetes operational practice is required. A simple multi-container Docker Compose deployment on one host is not this HA model and must not be described as equivalent to it.
- **HA/redundancy:** not yet a standard CamDX deployment option. Kubernetes Secrets is an architectural characteristic of this upstream HA shape's credential handling, not a CamDX-approved deployment mechanism.
- **Status:** Not currently a standard CamDX deployment option. Contact CamDX before implementation. This does not replace Model E; CamDX's existing native replicated-HA architecture remains supported for members who already use it.
- **CamDX does not recommend this when:** the member is not already Kubernetes-operations-mature, or is looking for the least-complex HA option (Model D) or CamDX's established HA option (Model E).

## 9. What this document does not do

- It does not authorize moving an existing member from one model to another; see [Upgrade and Migration](./upgrade/README.md).
- It does not mark Model D, E, or F as a standard approved CamDX deployment for a new member; see each model's status above.
- It does not treat upstream X-Road support for a capability (PKCS#11/HSM, Kubernetes clustering) as equivalent to that capability being a standard CamDX deployment offering.

## 10. References

- [Ubuntu Standalone Installation](./ubuntu/standalone-installation.md), [RHEL Standalone Installation](./rhel/standalone-installation.md), [Container Deployment](./container/deployment.md), [Container Production Hardening Checklist](./container/production-hardening-checklist.md).
- [Ubuntu HA](./ubuntu/high-availability-installation.md), [RHEL HA](./rhel/high-availability-installation.md).
- [Upgrade and Migration](./upgrade/README.md), [Parallel Replacement](./upgrade/parallel-replacement.md).
