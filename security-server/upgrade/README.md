# CamDX Security Server Upgrade and Member Migration

This document is not an upgrade procedure and does not authorize migrating any member's Security Server. It exists so that the availability of validated CamDX 7.8.2 fresh-install documentation and packages is never mistaken for authorization to upgrade an existing, already-deployed Security Server in place.

- **Deploying a brand-new Security Server?** Use the fresh-install guide directly: [Ubuntu](../ubuntu/standalone-installation.md), [RHEL](../rhel/standalone-installation.md), or [Container](../container/deployment.md). This page does not apply to that path.
- **Operating an existing CamDX Security Server?** Read on before taking any action.

## 1. Do not self-upgrade

Do not independently upgrade an existing Security Server using the fresh-install guides, and do not construct your own upgrade sequence, including:

- `apt upgrade` / `apt dist-upgrade` against a repointed repository
- `dnf upgrade` / `dnf downgrade`
- `rpm --force` package replacement
- Scripted package-replacement across the `xroad-*` package set
- Direct database schema manipulation
- Pointing an existing host's package manager at the 7.8.2 repository in place of its current one

An in-place package upgrade of an existing Security Server is not an approved member procedure. Upstream X-Road release notes are not, by themselves, a CamDX migration path: CamDX-specific validation (PKI adaptation behavior, configuration carry-over, per-version compatibility) has not been performed for ad hoc transitions like these.

If your existing Security Server is broken or misbehaving, use [Connectivity Troubleshooting](../troubleshooting/connectivity.md) and CamDX's support channels. Do not treat a fresh-install command sequence as a repair procedure for an existing deployment; the fresh-install guides assume a clean host with no prior CamDX state.

## 2. Current estate and target release

CamDX's deployed Security Server estate runs more than one version; migration proceeds through member-specific, risk-based waves rather than a single uniform cutover. The 7.8.2 fresh-install artifacts validated and approved for new deployments:

| Platform | Artifact |
|---|---|
| Ubuntu 22.04 (Jammy) | `7.8.2-1.ubuntu22.04` |
| Ubuntu 24.04 (Noble) | `7.8.2-1.ubuntu24.04` |
| RHEL 9 | `7.8.2-2.el9` |
| Container | `ghcr.io/techo-startup-center/camdx/security-server`, digest `sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b` |

Validation of these artifacts for fresh installation does not by itself authorize upgrading an existing member; see [Release Notes](../../release-notes/7.8.2.md) for the full validated scope.

## 3. CamDX's approved migration procedure

CamDX's approved member Security Server migration method is **Parallel Replacement / Blue-Green**:

**Parallel Replacement / Blue-Green procedure: APPROVED - FINAL.**

A new 7.8.2 Security Server (NEW) is deployed fresh, under its own new Security Server Code, alongside the existing Security Server (OLD), which keeps operating throughout. NEW is validated, traffic is transitioned to it in a controlled manner, and OLD is retired only after NEW is accepted and the rollback window has closed. The full operator procedure is documented in [Parallel Replacement](./parallel-replacement.md).

**Approval of this procedure is not authorization for any member to independently build, register, or cut over to a parallel Security Server.** Execution against a real member requires CamDX authorization and coordination for that specific migration, as part of an assigned migration wave.

An in-place transformation of an existing host (rather than a new, clean deployment under a new Security Server Code) is not CamDX's approved method and is not documented as an executable procedure by CamDX.

## 4. Migration readiness

Before any production migration wave, CamDX confirms readiness across: source-version inventory, configuration/PKI compatibility, Security Server registration and certificate/token continuity, Operational Monitoring and message-log behavior across the transition, host/platform compatibility, coexistence with members still on an older version, traffic steering and cutover, provider-side coexistence, dual observability of OLD and NEW during the transition, and controlled retirement of OLD. The operational detail a migrating member needs for traffic steering, dual observability, and retirement is in [Parallel Replacement](./parallel-replacement.md); CamDX tracks the items above, and they do not change that member-facing procedure.

CamDX notifies and coordinates maintenance windows with members as part of each migration wave; no wave sizes, counts, or dates are defined by this document.

## 5. High Availability boundary

HA migration is not covered by this document. Existing HA deployments remain supported, but HA upgrade or a topology change requires separate coordination with CamDX; see [Ubuntu HA](../ubuntu/high-availability-installation.md) and [RHEL HA](../rhel/high-availability-installation.md). Do not construct an HA rolling upgrade, load-balancer cutover, database failover, token replication, or active/passive switch on your own.

## 6. Central Server boundary

Central Server validation and migration is a separate CamDX-side track, unrelated to member action. Nothing in this document authorizes Central Server production migration, a DNS cutover for Central Server, or closure of overall CamDX production rollout.

## 7. X-Road 8 boundary

X-Road 8 is separate, pre-release engineering work. It is not the current production baseline, not the source or target of this 7.8.2 migration, and not part of the member migration path described above.

## 8. Status summary

```text
Fresh Ubuntu install:                          Supported
Fresh RHEL install:                            Supported
Fresh container deployment:                    Supported

Parallel Replacement / Blue-Green procedure:    APPROVED - FINAL
Production member rollout:                     NOT AUTHORIZED
Member migration execution:                    Requires CamDX authorization per wave

In-place member upgrade:                       Not an approved member procedure

HA migration:                                  Requires CamDX coordination; existing HA supported
Central Server production migration:           Separate track / not authorized by this document
X-Road 8:                                      Separate, non-production track
```

This is a status summary, not a schedule; no dates, wave counts, or durations are attached to any row above.

## 9. References

- [Ubuntu Standalone Installation](../ubuntu/standalone-installation.md), [RHEL Standalone Installation](../rhel/standalone-installation.md), [Container Deployment](../container/deployment.md).
- [Initial Configuration](../initial-configuration.md), [Network Requirements](../network-requirements.md), [Connectivity Troubleshooting](../troubleshooting/connectivity.md).
- [Release Notes 7.8.2](../../release-notes/7.8.2.md).
- [Parallel Replacement](./parallel-replacement.md): the detailed, approved member migration procedure.
