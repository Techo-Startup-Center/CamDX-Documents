# CamDX Security Server Documentation

**This is the authoritative Security Server documentation landing page for CamDX.**

```text
Current validated CamDX Security Server baseline: CamDX / X-Road 7.8.2
```

## Deployment / status matrix

| Deployment | Platform | Package/Baseline | Status |
|---|---|---|---|
| Standalone | Ubuntu 22.04 Jammy | `7.8.2-1.ubuntu22.04` | Validated |
| Standalone | Ubuntu 24.04 Noble | `7.8.2-1.ubuntu24.04` | Validated |
| Standalone | RHEL 9 | `7.8.2-2.el9` | Validated |
| HA | Ubuntu | 7.8.2 target | Requires verification |
| HA | RHEL | 7.8.2 target | Requires verification |
| Container | Noble-based 7.8.2 image, `linux/amd64` | `ghcr.io/techo-startup-center/camdx/security-server:7.8.2` / `:noble-7.8.2` | Validated / Published |
| Upgrade/Migration | Existing deployed SS | separate track | Not started / gated |

Full detail and evidence basis for these statuses: [`../release-notes/7.8.2.md`](../release-notes/7.8.2.md).

## Where to start

| I want to... | Go to |
|---|---|
| Install a new Security Server on Ubuntu | [`ubuntu/standalone-installation.md`](./ubuntu/standalone-installation.md) |
| Install a new Security Server on RHEL 9 | [`rhel/standalone-installation.md`](./rhel/standalone-installation.md) |
| Deploy the containerized Security Server Sidecar | [`container/deployment.md`](./container/deployment.md) |
| Understand CamDX network/firewall requirements | [`network-requirements.md`](./network-requirements.md) |
| Find an API provider's connectivity endpoint | [`provider-connectivity.md`](./provider-connectivity.md) |
| Complete post-install member/anchor/key/certificate configuration | [`initial-configuration.md`](./initial-configuration.md) |
| Set up a High Availability pair | [`ubuntu/high-availability-installation.md`](./ubuntu/high-availability-installation.md) / [`rhel/high-availability-installation.md`](./rhel/high-availability-installation.md) *(status: requires verification)* |
| Diagnose a connectivity problem | [`troubleshooting/connectivity.md`](./troubleshooting/connectivity.md) |
| Upgrade an existing Security Server | [`upgrade/README.md`](./upgrade/README.md) *(status/safety document — no upgrade procedure exists yet)* |

## Important notices

- **Fresh installation only.** Every installation guide above describes installing a *new* Security Server. None of them are an in-place upgrade procedure for an existing deployment — see [`upgrade/README.md`](./upgrade/README.md).
- **Container image is published.** `ghcr.io/techo-startup-center/camdx/security-server:7.8.2` and `:noble-7.8.2` are public and independently verified pullable, both resolving to immutable digest `sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b`. No `latest` tag is published — always pin to `7.8.2`/`noble-7.8.2` or the digest. See [`container/deployment.md`](./container/deployment.md) for the deployment pattern.
- **HA documents are status records, not approved procedures**, until 7.8.2-specific validation evidence supports them.
- **Operational Monitoring is mandatory, but the topology is a choice.** CamDX requires every Security Server deployment to have Operational Monitoring capability. The **default** deployment model is **local** Operational Monitoring, running on the Security Server itself. **Remote/external** Operational Monitoring is a **supported alternative** architecture — not an HA-only special case — and a Security Server using an approved remote/external model does not also need to run local Operational Monitoring. The relevant deployment guide for a given Security Server specifies which of the two models applies. See [`initial-configuration.md`](./initial-configuration.md) §12 for the full policy.
- **Legacy documentation remains temporarily available** at the repository root (`standalone_security_server_installation_and_configuration.md` and its RHEL/HA counterparts) while this new architecture is reviewed. Prefer the documents linked above.
- **Central Server validation is a separate, currently open track**, not addressed by this matrix — nothing in this matrix implies Central Server 7.8.2 validation, production Central Server migration, or the overall CamDX 7.8.2 production rollout is complete.

Do not treat any status in the matrix above as more validated than stated — in particular, "Validated" applies specifically to the package build/installation (and, for the container, publication) evidence in [`../release-notes/7.8.2.md`](../release-notes/7.8.2.md), not to HA or migration readiness, each of which is tracked separately.
