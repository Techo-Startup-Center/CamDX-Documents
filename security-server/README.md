# CamDX Security Server

Current release: **CamDX / X-Road 7.8.2**

This documentation is for organizations connecting to CamDX using an X-Road Security Server — whether you are deploying a new Security Server or operating an existing one.

## Choose your deployment

| Deployment | Status | Guidance |
|---|---|---|
| Ubuntu 24.04 / 22.04 | Supported | [Ubuntu installation](./ubuntu/standalone-installation.md) |
| RHEL 9 | Supported | [RHEL installation](./rhel/standalone-installation.md) |
| Container | Supported | [Container installation](./container/deployment.md) |
| Independent redundant Security Servers | Contact CamDX | Coordinate with CamDX before deployment |
| Replicated HA cluster | Contact CamDX | Coordinate with CamDX before deployment |
| Kubernetes HA | Not yet supported | Do not deploy this for CamDX yet |

A few things worth knowing up front:

- **Ubuntu** is the recommended starting point if you have no other platform requirement.
- **RHEL 9** is fully supported where your organization's own policy requires it.
- **Container** deployment is supported and is a good fit for a new (greenfield) deployment if your team already runs containerized infrastructure day to day — it is not yet the default recommendation for every member.
- CamDX does not yet have an approved, publishable procedure for standing up a **new** high-availability deployment. If your organization needs HA, **contact CamDX first** — see [High Availability](#high-availability) below.

## Installation flow

1. **Check prerequisites and connectivity** — see [Connectivity](#connectivity) below.
2. **Install the Security Server** — pick your platform above.
3. **Verify installation** — each installation guide ends with a verification checklist.
4. **Complete Initial Configuration** — member identity, software token, certificates, subsystem(s).
5. **Test CamDX connectivity and required service access.**

## Installation

- [Ubuntu standalone installation](./ubuntu/standalone-installation.md)
- [RHEL 9 standalone installation](./rhel/standalone-installation.md)
- [Container standalone deployment](./container/deployment.md)

Each guide covers prerequisites, the install itself, and how to verify it worked before moving on to Initial Configuration.

## Initial Configuration

Installing the Security Server gives you a working software environment — it does not yet know who you are. **Initial Configuration** connects the installed Security Server to the member identity using the Member Class, Member Code, Security Server Code, and subsystem information provided or confirmed by CamDX, and configures the software token and certificates.

Every platform above hands off to the same procedure: [`initial-configuration.md`](./initial-configuration.md).

## Connectivity

CamDX infrastructure addresses (Central Server, Management Security Server, timestamping, OCSP, monitoring) and API provider endpoints are maintained centrally rather than repeated in every installation guide:

- [`network-requirements.md`](./network-requirements.md) — CamDX infrastructure connectivity.
- [`provider-connectivity.md`](./provider-connectivity.md) — API provider endpoints (e-KYC, e-KYB, OCR, etc.).

Confirm these before you install, and again if something isn't connecting after installation.

## Troubleshooting

Something not working? Start here: **[Troubleshooting index](./troubleshooting/README.md)**.

Common categories:

- Connectivity
- Signer and token
- Certificates and OCSP
- Registration
- Global configuration
- Database
- Operational Monitoring
- Unknown X-Road errors — see the [error reference](./troubleshooting/error-reference.md)

## High Availability

Keeping this short on purpose:

- **Existing CamDX HA deployments remain fully supported.** If you already run one, nothing here changes that.
- **If you are planning a new HA deployment, contact CamDX before you implement anything.** CamDX will provide the applicable HA guidance during coordination.

## Upgrade / migration

**Existing Security Server deployments must not be self-upgraded.** Any production migration to 7.8.2 must be coordinated with CamDX. See [`upgrade/README.md`](./upgrade/README.md) and the [Parallel Replacement](./upgrade/parallel-replacement.md) procedure.

## Legacy documentation

A handful of older top-level guides still exist in this repository from before this documentation was reorganized. Prefer the pages linked above — they reflect the current 7.8.2 baseline.
