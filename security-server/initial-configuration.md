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

Changing a value in `local.ini` requires restarting the server for it to take effect:

```bash
sudo systemctl restart xroad-proxy
```

**Container:** this setting is not yet supported by an evidenced container configuration mechanism. Contact CamDX for the applicable container configuration.

Contact CamDX to confirm any other setting for your deployment that is not covered by the defaults applied during installation.

## 13. Operational Monitoring

Operational Monitoring capability is required for every CamDX Security Server. Local Operational Monitoring, installed and running on the Security Server itself, is the standard standalone configuration and is set up automatically by the recommended installers.

Remote/external Operational Monitoring is a supported alternative: a dedicated Operational Monitoring node outside the Security Server, which may serve one or more Security Servers depending on the approved topology. This is not an HA-only mechanism. If your deployment requires this topology, contact CamDX before deployment.

## 14. References

- [`network-requirements.md`](./network-requirements.md): connectivity this configuration workflow depends on.
