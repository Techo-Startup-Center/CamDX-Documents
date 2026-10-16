# CamDX Security Server

Current release: **CamDX / X-Road 7.8.2**

This documentation is for organizations connecting to CamDX using an X-Road Security Server, whether you are deploying a new Security Server or operating an existing one.

## Choose your deployment

| Platform | Guidance |
|---|---|
| Ubuntu 22.04 / 24.04 | [Ubuntu installation](./ubuntu/standalone-installation.md) |
| RHEL 9 | [RHEL installation](./rhel/standalone-installation.md) |
| Container | [Container installation](./container/deployment.md) |

Ubuntu is the recommended starting point if you have no other platform requirement. RHEL 9 is fully supported where your organization's own policy requires it. Container deployment is supported for teams with mature container operations; review the persistence requirements in the container guide before production use.

## Installation flow

1. Check prerequisites and connectivity, see [Network requirements](./network-requirements.md).
2. Install the Security Server using the guide for your platform above.
3. Verify the installation (each guide ends with a verification step).
4. Complete [Initial Configuration](./initial-configuration.md): member identity, software token, certificates, subsystem(s).
5. Test CamDX connectivity and required service access.

## Network requirements

CamDX infrastructure connectivity (Central Server, Management Security Server, timestamping, OCSP, monitoring) is documented in [`network-requirements.md`](./network-requirements.md). Confirm this before you install, and again if something is not connecting after installation.

## Troubleshooting

Something not working? Start here: **[Troubleshooting index](./troubleshooting/README.md)**.

## High Availability

A native HA deployment requires a completed [HA Deployment Profile](./high-availability-deployment-profile.md) with Checkpoint A confirmed before you start. Once you have that:

| Platform | Guidance |
|---|---|
| Ubuntu 22.04 / 24.04 | [Ubuntu HA installation](./ubuntu/high-availability-installation.md) |
| RHEL 9 | [RHEL HA installation](./rhel/high-availability-installation.md) |
| Container | Not currently a standard CamDX deployment option |

See [Deployment Model Selector](./deployment-models.md) for how HA compares to other deployment models.

## Upgrade / migration

Do not self-upgrade an existing CamDX Security Server. Contact CamDX for a coordinated migration.
