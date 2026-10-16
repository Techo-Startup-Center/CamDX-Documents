# CamDX Security Server - Common Initial Configuration

This document covers the Security Server configuration steps that are the same regardless of whether the underlying operating system is Ubuntu, RHEL, or the container deployment. Each OS-specific installation guide hands off here after installation completes.

## 1. Security Server member information

Before starting configuration, CamDX provides your member identity information as part of member registration:

| Field | Notes |
|---|---|
| Member Name | Provided by CamDX |
| Member Class | e.g. `GOV`, `COM`, provided by CamDX |
| Member Code | Provided by CamDX |
| Security Server Code | Provided by CamDX for this specific Security Server during onboarding. Not chosen by you. Distinct from the Member Code. |
| Subsystem Code(s) | Provided or confirmed by CamDX |

This information is required before the initial configuration step (§4) can be completed.

## 2. Access to the Security Server Admin UI

- URL: `https://<SECURITY_SERVER_IP_OR_FQDN>:4000`
- Login: the system administrator account created during installation.

The browser may show a connection-refused error for a short period while the Admin UI is still starting up after service start. This is expected.

## 3. Configuration anchor

The CamDX configuration anchor file is provided by CamDX and must be uploaded before initial configuration can proceed.

| Environment | Anchor URL |
|---|---|
| Development | `https://repository.camdx.gov.kh/repository/camdx-anchors/anchors/dev/CAMBODIA_configuration_anchor_dev.xml` |
| Production | `https://repository.camdx.gov.kh/repository/camdx-anchors/anchors/CAMBODIA_configuration_anchor.xml` |

When the anchor is uploaded, the Security Server verifies connectivity to the Central Server address specified within it, see [`network-requirements.md`](./network-requirements.md) for the required outbound connectivity.

**Admin UI:** Settings, System Parameters (or the initial first-run configuration screen), import the configuration anchor file.

## 4. Initial configuration

With the member information from §1, complete the Security Server's initial configuration screen, supplying the Member Name, Member Class, Member Code, and Security Server Code exactly as provided by CamDX.

## 5. Software token / PIN

Set (or enter, if already set) the software token PIN as part of initial configuration. This PIN protects the software token holding the Security Server's signing and authentication keys.

- Admin UI: the initial-configuration flow prompts for this directly, or it can be entered later via **Keys and Certificates, Token, Login**.

## 6. Timestamping service configuration

- Admin UI: **Settings, Timestamping Services, Add**
- Select the appropriate CamDX-provided timestamping service from the list and add it.

## 7. Signing and authentication keys

Two separate keys are required, both generated on the software token.

### 7.1 Authentication key

- Admin UI: **Keys and Certificates**, select the token, **Add Key**, label it (e.g. `AuthKey`)
- CSR details: Usage = **AUTHENTICATION**, Certification Service = the CamDX intermediate CA, CSR Format = **PEM**
- Generate the CSR, specifying the Security Server's DNS name (CN) and Organization Name (O)

### 7.2 Signing key

- Admin UI: **Keys and Certificates**, select the token, **Add Key**, label it (e.g. `SignKey`)
- CSR details: Usage = **SIGNING**, Client = the member's X-Road identifier, Certification Service = the CamDX intermediate CA, CSR Format = **PEM**
- Generate the CSR, specifying the Organization Name (O)

### 7.3 Submitting the CSRs

Send both CSR files (authentication and signing) to CamDX. CamDX will issue the corresponding certificates.

## 8. Certificate import

Once CamDX issues the certificates:

- Admin UI: **Keys and Certificates, Import cert.**, browse to and open each issued certificate file.
- The authentication certificate is disabled by default after import. It must be explicitly selected and activated before it can be used.

## 9. Authentication certificate registration

- Admin UI: select the authentication certificate, **Register**, enter the Security Server's FQDN, and submit the registration request.
- The request status shows "registration in progress" until CamDX approves it, after which it shows as approved/registered.

## 10. Member registration status / subsystem registration

Once the authentication certificate is approved:

- Add any required subsystem: **Clients, (member), Add subsystem**, supplying the subsystem code.
- A newly added subsystem shows a pending state until approved, after which its status turns to **REGISTERED**.
- For a subsystem that consumes services over HTTP internally, its internal-server protocol may need to be switched from HTTPS to HTTP (or configured per your backend), via the subsystem's **Internal Servers** settings. Confirm the correct setting for your integration; do not assume HTTP is always correct.

## 11. Final registration/status checks

Before considering the Security Server ready for use, confirm:

- The authentication certificate shows **registered** (not merely imported/activated).
- The signing certificate shows **registered**, associated with the correct member.
- The software token shows **active** (not `inactive`/PIN-locked).
- The relevant subsystem(s) show **REGISTERED**.
- Global configuration is downloading successfully (no `anchor_file_not_found` or persistent download errors).

## 12. CamDX-specific settings

CamDX requires one setting beyond the X-Road defaults:

| Setting | Section | Value | Notes |
|---|---|---|---|
| `message-body-logging` | `[message-log]` | `false` | Disables full message-body logging. Required by CamDX. |

**Native (Ubuntu/RHEL):** create or edit `/etc/xroad/conf.d/local.ini` and add:

```ini
[message-log]
message-body-logging=false
```

Changing a value in `local.ini` requires restarting `xroad-proxy` for it to take effect:

```bash
sudo systemctl restart xroad-proxy
```

**Container:** CamDX has not yet published a supported container configuration mechanism for this setting. Contact CamDX for the applicable container configuration.

Contact CamDX to confirm any other setting for your deployment that is not covered by the defaults applied during installation.

## 13. Operational Monitoring

Operational Monitoring capability is required for every CamDX Security Server. Local Operational Monitoring, installed and running on the Security Server itself, is the standard standalone configuration and is set up automatically by the recommended installers.

Remote/external Operational Monitoring is a supported alternative: a dedicated Operational Monitoring node outside the Security Server, which may serve one or more Security Servers depending on the approved topology. This is not an HA-only mechanism. If your deployment requires this topology, contact CamDX before deployment.

## 14. High Availability

This section applies only to a replicated native HA deployment ([Ubuntu HA](./ubuntu/high-availability-installation.md), [RHEL HA](./rhel/high-availability-installation.md)). It does not change anything in §1-§13 above for a standalone deployment.

**Logical Security Server address:** for a replicated external-load-balancer HA deployment, the logical Security Server external address is the approved HA load-balancer/VIP FQDN or external address recorded in the HA Deployment Profile. Use that address for the authentication-certificate CSR and Security Server registration wherever this document asks for the Security Server's DNS name/FQDN or external address. Do not register either backend node's own private/node FQDN as the logical Security Server address. Confirm the HA FQDN actually resolves to, and routes to, the load balancer/VIP, which then performs Layer-4 TCP passthrough to the backend nodes, before submitting the CSR.

For a replicated native HA deployment:

1. Complete the HA infrastructure/replication procedure first (the installation guide's Phases 0-17), including the secondary's `serverconf` database connection (Phase 10).
2. Perform this entire Initial Configuration document on the **primary node only**, using the logical HA address above wherever an external/DNS address is asked for.
3. Do not initialize the secondary as another Security Server: do not import the configuration anchor, create a token, generate keys, or attempt registration there.
4. After Initial Configuration on the primary completes, perform the installation guide's one-time bootstrap synchronization (Phase 19) once, manually; this carries the initial global configuration and signer/token state to the secondary. `serverconf` itself is already live on the secondary continuously, via PostgreSQL streaming replication, independent of this sync.
5. Verify the secondary reflects the same logical Security Server identity, not a separate one, and that its global configuration is valid and independently refreshing (Phase 21).
6. Log in/unlock the software token on the secondary using the approved mechanism (manual PIN entry by a retained security-officer role); it does not unlock automatically when the token file is replicated.
7. Use the secondary's Admin UI as read-only, except for the token/PIN operations the retained `xroad-security-officer` role permits.

See the installation guide's own Phase 10 and Phase 18-21 for the exact commands and verification steps.

## 15. References

- [`network-requirements.md`](./network-requirements.md): connectivity this configuration workflow depends on.
- [Ubuntu HA Installation](./ubuntu/high-availability-installation.md), [RHEL HA Installation](./rhel/high-availability-installation.md): the HA-specific procedure §14 above refers to.
