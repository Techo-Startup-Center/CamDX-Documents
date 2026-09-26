# CamDX Security Server — Common Initial Configuration

**Status: SAFE/EVIDENCED (workflow steps, sourced from legacy CamDX guides) / REQUIRES VERIFICATION (exact port defaults and a few settings, flagged individually below)**

This document contains the **deployment-independent** Security Server configuration steps — the parts of setup that are identical regardless of whether the underlying operating system is Ubuntu, RHEL, or the container Sidecar. OS-specific installation guides should link here instead of duplicating this workflow.

This content is consolidated from the CamDX legacy Ubuntu and RHEL standalone guides, which previously duplicated nearly this entire workflow independently in each document.

## 1. Security Server member information

Before starting configuration, CamDX Central Authority provides the member's identity information as part of the member registration process:

| Field | Example |
|---|---|
| Member Name | (provided by CamDX) |
| Member Class | e.g. `GOV`, `COM` |
| Member Code | (provided by CamDX) |
| Security Server Code | **Provided by CamDX** for the specific Security Server during onboarding — not independently chosen by the member/administrator. Distinct from the Member Code. No sample code is asserted here; use the exact value supplied by CamDX Central Authority. |

This information is required before the Security Server's initial configuration step (§4) can be completed.

## 2. Access to the Security Server Admin UI

- URL: `https://<SECURITY_SERVER_IP_OR_FQDN>:4000`
- Login: the system administrator account created during installation (see the OS-specific installation guide's post-install step)

The web browser may show a connection-refused error for a short period while the Admin UI is still starting up after service start — this is expected, not a fault.

## 3. Configuration anchor

The CamDX configuration anchor file is provided by the CamDX Central Authority and must be uploaded before initial configuration can proceed.

| Environment | Anchor URL |
|---|---|
| Development | `https://repository.camdx.gov.kh/repository/camdx-anchors/anchors/dev/CAMBODIA_configuration_anchor_dev.xml` |
| Production | `https://repository.camdx.gov.kh/repository/camdx-anchors/anchors/CAMBODIA_configuration_anchor.xml` |

When the anchor is uploaded, the Security Server verifies connectivity to the Central Server address specified within it — see [`network-requirements.md`](./network-requirements.md) for the required outbound connectivity this depends on.

**Admin UI:** Settings → System Parameters (or the initial first-run configuration screen) → import the configuration anchor file.

## 4. Initial configuration

With the member information from §1, complete the Security Server's initial configuration screen, supplying the Member Name, Member Class, Member Code, and Security Server Code exactly as provided by CamDX Central Authority.

## 5. Software token / PIN

Set (or enter, if already set) the software token PIN as part of initial configuration. This PIN protects the software token holding the Security Server's signing and authentication keys.

- Admin UI: the initial-configuration flow prompts for this directly, or it can be entered later via **Keys and Certificates → Token → Login**.

## 6. Timestamping service configuration

- Admin UI: **Settings → Timestamping Services → Add**
- Select the appropriate CamDX-provided timestamping service from the list and add it.

## 7. Signing and authentication keys

Two separate keys are required, both generated on the software token:

### 7.1 Authentication key

- Admin UI: **Keys and Certificates** → select the token → **Add Key**, label it (e.g. `AuthKey`)
- CSR details: Usage = **AUTHENTICATION**, Certification Service = the CamDX intermediate CA, CSR Format = **PEM**
- Generate the CSR, specifying the Security Server's DNS name (CN) and Organization Name (O)

### 7.2 Signing key

- Admin UI: **Keys and Certificates** → select the token → **Add Key**, label it (e.g. `SignKey`)
- CSR details: Usage = **SIGNING**, Client = the member's X-Road identifier, Certification Service = the CamDX intermediate CA, CSR Format = **PEM**
- Generate the CSR, specifying the Organization Name (O)

### 7.3 Submitting the CSRs

Send both CSR files (authentication and signing) to CamDX Central Authority. CamDX will issue the corresponding certificates.

## 8. Certificate import

Once CamDX issues the certificates:

- Admin UI: **Keys and Certificates → Import cert.**, browse to and open each issued certificate file.
- The authentication certificate is **disabled by default** after import — it must be explicitly selected and **activated** before it can be used.

## 9. Authentication certificate registration

- Admin UI: select the authentication certificate → **Register**, enter the Security Server's FQDN, and submit the registration request.
- The request status will show **"registration in progress"** until CamDX Central Authority approves it, after which it shows as approved/registered.

## 10. Member registration status / subsystem registration

Once the authentication certificate is approved:

- Add any required subsystem: **Clients → (member) → Add subsystem**, supplying the subsystem code.
- A newly added subsystem shows a pending state until approved by the Central Authority, after which its status turns to **REGISTERED**.
- For a subsystem intended to consume services over HTTP internally, its internal-server protocol may need to be switched from HTTPS to HTTP (or configured per the actual backend), via the subsystem's **Internal Servers** settings — confirm the correct setting for the specific integration rather than assuming HTTP is always correct.

## 11. Final registration/status checks

Before considering the Security Server ready for use, confirm:

- The authentication certificate shows **registered** (not merely imported/activated).
- The signing certificate shows **registered**, associated with the correct member.
- The software token shows **active** (not `inactive`/PIN-locked).
- The relevant subsystem(s) show **REGISTERED**.
- Global configuration is downloading successfully (no `anchor_file_not_found` or persistent download errors).

## 12. CamDX-specific settings (post-installation)

These are CamDX-specific overrides layered on top of the stock X-Road defaults, documented and classified from CamDX's own legacy configuration guidance. Apply them via `/etc/xroad/conf.d/local.ini` on a native install, or via the equivalent container/environment mechanism where applicable — see the OS-specific and container guides for exact application steps.

| Setting | Section | Legacy value | Classification | Notes |
|---|---|---|---|---|
| `message-body-logging` | `[message-log]` | `false` | **REQUIRED BY CAMDX** | Disables full message-body logging; consistently applied across every legacy CamDX guide reviewed. |
| `strict-identifier-checks` | `[proxy-ui-api]` | `false` | **REQUIRES VERIFICATION** | Upstream default is `true` for new installations from **X-Road 7.3 onward**; `false` may appear in a server's configuration as a carry-over from an in-place upgrade of an installation originally older than 7.3, rather than as a fresh-install setting. The legacy CamDX Ubuntu guide documents `false` (not found at all in the legacy RHEL guide) — this does **not** automatically make `false` the correct CamDX 7.8.2 fresh-install default; it should be retained only if CamDX has an explicit identifier-compatibility requirement driving it. That policy question is not decided by this document — confirm before treating `false` as a required or recommended default for new 7.8.2 deployments. |
| `client-http-port` | `[proxy]` | `80` (Ubuntu legacy) | **REQUIRES VERIFICATION** | Upstream X-Road default is `8080`. The legacy Ubuntu guide sets this to `80` in its configuration section, but its own "Consume API" example uses port `8080` in the request URL, and the RHEL guide describes changing `8080`/`8443` to `80`/`443` as an *optional* step rather than a default — `80`/`443` are deployment-specific overrides, not the upstream baseline. This is an internal inconsistency in the legacy documentation itself, not resolved by this task. The unresolved question is specifically **what CamDX 7.8.2 native fresh installations should standardize on** (the stock `8080` or the overridden `80`) — confirm before publishing either as a required step. |
| `client-https-port` | `[proxy]` | `443` (Ubuntu legacy) | **REQUIRES VERIFICATION** | Upstream X-Road default is `8443`. Same caveat as `client-http-port` above — the unresolved question is the CamDX 7.8.2 native standardization choice, not the upstream baseline. |
| `health-check-port` | `[proxy]` | `5588` | **REQUIRES VERIFICATION** (for native installs) | Upstream X-Road default is `0` (health-check endpoint **disabled**) — `5588` is an explicit deployment/configuration override, not the stock default. It was observed/validated specifically in the CamDX 7.8.2 Sidecar/container deployment. Whether native Jammy/Noble/RHEL 7.8.2 installations should also be configured to enable the health-check endpoint on `5588` remains unconfirmed — the evidence base for this row is container-specific, not native-install-specific. |
| `max-records-in-payload` | `[op-monitor]` | CamDX legacy documented `30000`; upstream default `10000` | **REQUIRES VERIFICATION** | The correct upstream X-Road Operational Monitoring parameter key is `max-records-in-payload` (the legacy CamDX guide's `max-records-in-playload` is a historical documentation typo, not a real alternate key — it is not preserved as if the correct key were uncertain). Upstream's own default for this key is `10000`. The historical CamDX documentation overrode this to `30000`, but whether CamDX 7.8.2 should continue overriding the upstream default to `30000` (vs. using the upstream default, vs. some other value) has not been confirmed — resolve before publishing a canonical 7.8.2 value. |
| `keep-records-for-days` | `[op-monitor]` | `365` | **RECOMMENDED** | Operational Monitoring data retention period; consistently documented in legacy CamDX guidance. |

### Operational Monitoring policy (final)

```text
Operational Monitoring capability: MANDATORY

Default topology:     Local Operational Monitoring
Alternative topology: Remote / external Operational Monitoring (supported)
```

CamDX requires every Security Server deployment to have Operational Monitoring capability — this is not optional at the capability level. What **is** a deployment choice is *where* that capability runs:

| Area | Classification | Notes |
|---|---|---|
| Operational Monitoring capability | **MANDATORY** | Every CamDX Security Server deployment must have Operational Monitoring capability, in one of the two topologies below. This is not a "local OPMON is universally mandatory" statement — see the next two rows. |
| Local Operational Monitoring (`xroad-addon-proxymonitor`, `xroad-addon-opmonitoring`, installed and running on the Security Server itself) | **DEFAULT DEPLOYMENT MODEL** | The default, documented in every legacy CamDX standalone guide, so that CamDX Central Operational Monitoring can collect transaction logs directly from the member's Security Server. Use this model unless the deployment is explicitly designed around remote/external Operational Monitoring instead. |
| Remote / external Operational Monitoring (dedicated Opmonitor node, shared by a cluster) | **SUPPORTED ALTERNATIVE** | A Security Server using an approved remote/external Operational Monitoring architecture does **not** need to also run the local Operational Monitoring add-ons — the two are alternatives, not additive. Currently documented for the High Availability topology (see the HA documents, status: requires verification for the HA procedure itself, independent of this OPMON policy). Do not install local Operational Monitoring merely to satisfy documentation on a deployment explicitly designed for the remote/external model. |
| PAM/group/admin sequencing (`xroad-add-admin-user`) | **REQUIRED BY CAMDX** (RHEL) / **implicit** (Ubuntu, via the package's interactive prompt) | The RHEL legacy guide documents an explicit `sudo xroad-add-admin-user <user>` step; the Ubuntu legacy guide relies on the package's interactive installation prompt to create the admin account. Both achieve the same outcome (an authorized Admin UI user), but the exact sequencing differs by OS — see the OS-specific installation guides. |
| Admin UI user creation | **REQUIRED BY CAMDX** | A dedicated system-administrator account (explicitly *not* named `xroad`, which is reserved for the X-Road system user) is created during installation on every legacy guide reviewed. |
| Proxy port changes (8080/8443 → 80/443) | **OPTIONAL**, per the RHEL legacy guide's own framing | See the `client-http-port`/`client-https-port` row above — classified as an optional step in the RHEL source, but presented as if default in the Ubuntu source. Reconcile before final publication. |
| PostgreSQL properties (`/etc/xroad.properties`, `/etc/xroad/db.properties`) | **REQUIRED BY CAMDX** (only if using a remote/external database) | Only applicable when opting into the remote-database installation path; not required for a default local-database installation. |

## 13. References

- Legacy source content: `standalone_security_server_installation_and_configuration.md`, `rhel_standalone_security_server_installation_and_configuration.md` (this repository, `main` branch, reviewed 2026-09-24).
- [`network-requirements.md`](./network-requirements.md) — connectivity this configuration workflow depends on.

## 14. Change history

| Date | Change |
|---|---|
| 2026-09-24 | Document created as part of the CamDX-Documents 7.8.2 documentation architecture modernization, consolidating configuration steps previously duplicated across the legacy Ubuntu and RHEL standalone guides. Several settings flagged REQUIRES VERIFICATION due to internal inconsistencies found in the legacy source documents themselves (see §12). |
| 2026-09-24 | Review pass: added the Security Server Code field to §1/§4 (distinct from Member Code, not explicitly transcribed as a field in the legacy source guides); no example value asserted, flagged REQUIRES VERIFICATION for any specific naming convention. |
| 2026-09-24 | Policy correction round (final operator decisions): Security Server Code corrected to **provided by CamDX**, not member-chosen (§1/§4); Operational Monitoring reclassified as a mandatory capability with local as the default topology and remote/external as a supported alternative, not "local is universally required" (§12); `health-check-port` softened from RECOMMENDED to REQUIRES VERIFICATION for native installs, since its evidence base is container/Sidecar-specific (§12). |
| 2026-09-24 | Evidence-driven cleanup: corrected the legacy `max-records-in-playload` typo to the real upstream key `max-records-in-payload` (upstream default `10000`; CamDX legacy override `30000` unconfirmed for 7.8.2, reclassified REQUIRES VERIFICATION); added upstream baseline facts to `strict-identifier-checks` (`true` default from X-Road 7.3 onward — `false` may be an upgrade carry-over, not a fresh-install default), `client-http-port`/`client-https-port` (upstream defaults `8080`/`8443`; `80`/`443` are overrides, not the baseline), and `health-check-port` (upstream default `0`/disabled; `5588` is an explicit override validated only in the container deployment). None of these rows' REQUIRES VERIFICATION classification was resolved — only the upstream-vs-CamDX-override distinction was clarified. |
