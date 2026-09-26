# CamDX-Documents

Documentation for the CamDX X-Road ecosystem, maintained by Techo Startup Center (TSC).

## Current baseline

```text
Current validated CamDX Security Server baseline: CamDX / X-Road 7.8.2
```

For Security Server installation, configuration, networking, and troubleshooting documentation, start at:

**[`security-server/README.md`](./security-server/README.md)**

That page is the authoritative landing point for all Security Server documentation, including a deployment/status matrix, and links to installation guides for Ubuntu, RHEL, and the containerized Sidecar deployment. Detailed installation and configuration procedures are not duplicated here.

## Legacy documentation notice

The following top-level documents remain temporarily available from earlier CamDX documentation revisions, while the new documentation architecture under `security-server/` is reviewed and adopted:

- `standalone_security_server_installation_and_configuration.md`
- `high_availability_security_server_installation_with_external_load_balancer.md`
- `rhel_standalone_security_server_installation_and_configuration.md`
- `rhel_high_availability_security_server_installation_with_external_load_balancer.md`

**These legacy documents reference older CamDX/X-Road baselines (as old as 7.2.2 in some sections) and should not be used for new deployments.** Prefer [`security-server/README.md`](./security-server/README.md) and its linked documents, which reflect the current validated CamDX 7.8.2 baseline. The legacy documents are expected to be converted into short redirect/compatibility pages once the new architecture has been reviewed and approved — that conversion has not yet happened.

## Other repository contents

- `ansible/` — historical Ansible playbook example for a High Availability Security Server topology. Contains outdated infrastructure assumptions (Ubuntu 18.04, private lab IP addressing) and should be treated as architectural illustration only, not current operational guidance — see [`security-server/ubuntu/high-availability-installation.md`](./security-server/ubuntu/high-availability-installation.md).
- `img/` — image assets referenced by the installation and configuration guides.
