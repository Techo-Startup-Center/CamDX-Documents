# CamDX Security Server - Common Initial Configuration

This document covers the Security Server configuration steps that are the same regardless of whether the underlying operating system is Ubuntu, RHEL, or the container deployment. Each OS-specific installation guide hands off here after installation completes. UI labels below are the exact X-Road 7.8.2 Admin UI terms from the upstream Security Server User Guide; where this document says to click a specific button, that is the literal button text, not a paraphrase.

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

Download the anchor file for your environment to the machine you are using to reach the Admin UI (your workstation, not the Security Server itself):

```bash
curl -fL '<ANCHOR_URL>' -o "$HOME/CAMBODIA_configuration_anchor.xml"
ls -l "$HOME/CAMBODIA_configuration_anchor.xml"
```

Expected result: `ls -l` shows the file with a nonzero size. Substitute the Development or Production URL from the table above for `<ANCHOR_URL>`; do not invent or guess a different URL.

**Verifying the anchor before importing it.** When the system asks you to upload the anchor in §4 below, it shows you the hash of the file you selected and asks you to compare it against the hash of the currently valid anchor published by the X-Road governing authority (CamDX) before you confirm the upload. If CamDX separately publishes a reference hash for the anchor through your onboarding channel, compare the displayed hash against that published value before clicking **CONFIRM**. If no separately published reference hash is available to you, do not treat computing a local hash of the file you just downloaded as independent verification of its authenticity; a hash calculated from the same file you are about to upload only confirms the file was not corrupted in transfer, not that it is the genuine CamDX anchor. In that case, obtain the anchor only from the CamDX URL above over HTTPS, and raise the lack of a published reference hash with CamDX if your organization's policy requires one before proceeding.

## 4. Initial configuration (first Admin UI login)

Open `https://<SECURITY_SERVER_IP_OR_FQDN>:4000` and log in with the system administrator account created during installation (§2). On first login, the Admin UI runs you through a first-time setup wizard before showing the normal navigation tabs. The exact sequence of screens and controls is:

1. **Upload the configuration anchor.** The wizard's first screen asks for the anchor file. Browse to the file you downloaded in §3 and select it.
2. Click **UPLOAD**. The wizard shows the hash of the file you selected.
3. Compare the displayed hash against the reference value as described in §3, then click **CONFIRM** to accept the anchor.
4. **Enter Member Class.** In the field labeled **Member Class**, enter the value from §1 exactly as provided by CamDX (for example `GOV` or `COM`).
5. **Enter Member Code.** In the field labeled **Member Code**, enter the value from §1 exactly as provided by CamDX.
6. Click **CONTINUE**.
7. **Confirm the owner name returned by X-Road.** Once Member Class and Member Code are both accepted, the wizard automatically displays the Security Server owner's name as registered in the X-Road center. Confirm this is your organization's correct registered name before continuing; if it is wrong or blank, **STOP** and re-check the Member Class/Member Code values with CamDX rather than continuing.
8. **Enter the CamDX-provided Security Server Code.** In the field labeled **Security Server Code**, enter the value from §1 exactly as provided by CamDX. This value must be unique across every Security Server belonging to your organization; do not choose it yourself.
9. Click **CONTINUE**.
10. **Set the software-token PIN.** The wizard presents two fields, **PIN** and **Repeat PIN**. Choose a PIN and enter the identical value in both fields. This PIN protects the software token holding the Security Server's signing and authentication keys. **Store the PIN in your organization's approved secret storage immediately; it cannot be recovered if lost, and losing it means the keys it protects can no longer be used.** Never record the PIN in the HA Deployment Profile or any other plain-text file.
11. Click **SUBMIT**.
12. **Verify first-run completion.** The Admin UI now shows its normal navigation tabs (**CLIENTS**, **KEYS AND CERTIFICATES**, **SETTINGS**, and others). Reaching this view confirms the first-time setup wizard completed successfully.

If the Admin UI already completed first-time setup previously (for example, you are returning to an already-initialized Security Server), log in directly and skip to §6.

## 5. Timestamping service configuration

1. In the **Navigation tabs**, select **SETTINGS**.
2. Select the **SYSTEM PARAMETERS** tab.
3. In the **Timestamping Services** section, click **ADD**.
4. Select the appropriate CamDX-provided timestamping service from the list and add it.

Expected result: the timestamping service now appears listed in the **Timestamping Services** section.

## 6. Signing and authentication keys

Two separate keys are required, both generated on the software token. In the **Navigation tabs**, select **KEYS AND CERTIFICATES**. The software token appears in the **SIGN AND AUTH KEYS** table.

**Log in to the token first, if it is not already logged in:** click **LOG IN** on the token's row and enter the PIN set in §4. Once the correct PIN is entered, the button changes to **LOG OUT**, confirming the token is now unlocked.

### 6.1 Signing key

1. Expand the token's row by clicking the caret next to the token name, then click **ADD KEY**.
2. In the wizard: optionally define a label for the key (for example `SignKey`), click **NEXT**.
3. On the next page: select **Usage** = `SIGNING`; select **Client** = the member/subsystem this key signs for; select **Certification Service** = the CamDX intermediate CA; select **CSR Format** = `PEM` (unless the CamDX CA's profile pre-selects and locks a different format, in which case use the pre-selected value). Click **CONTINUE**.
4. Review the certificate owner's information shown, filling in any empty required field, then click **GENERATE CSR**.
5. Click **DONE**.

Expected result: a "Request" record appears under the token's row, indicating the signing CSR now exists for this key. Keep (or re-download) the generated CSR file; you submit it in §6.3.

### 6.2 Authentication key

1. Expand the token's row (if not already expanded), click **ADD KEY**.
2. In the wizard: optionally define a label (for example `AuthKey`), click **NEXT**.
3. On the next page: select **Usage** = `AUTHENTICATION`; select **Certification Service** = the CamDX intermediate CA; select **CSR Format** = `PEM`. Click **CONTINUE**.
4. Review and fill in the certificate fields shown (including the Security Server's DNS name as the CN/SAN, per §9 below), then click **GENERATE CSR**.
5. Click **DONE**.

Expected result: a "Request" record appears under the token's row for the authentication key, the same way as the signing key.

### 6.3 Submitting the CSRs

Send both generated CSR files (signing and authentication) to CamDX through your approved onboarding channel. CamDX issues the corresponding certificates and returns them to you.

## 7. Certificate import

Once CamDX issues both certificates:

1. In the **Navigation tabs**, select **KEYS AND CERTIFICATES**.
2. Expand the token's row, locate the "Request" record for the certificate you are importing, and click **IMPORT CERT.**.
3. Locate the certificate file on the local file system and open it.

Expected result: the "Request" record is replaced with the imported certificate's information. By default, an imported authentication certificate is in the **Saved** (registration) and **Disabled** (validity) states; a signing certificate does not need separate activation.

**Activate the authentication certificate before it can be used:**

1. Click the authentication certificate's row to open its **Certificate** dialog.
2. Click **Activate**.

Expected result: the certificate's validity state changes from **Disabled**. (Use **DISABLE** in the same dialog if you ever need to reverse this.)

## 8. Authentication certificate registration

1. In the **Navigation tabs**, select **KEYS AND CERTIFICATES**.
2. Expand the token's row, locate the activated authentication certificate (it must be in **Saved** registration state), and click **Register** at the end of its row.
3. In the dialog that opens, enter the Security Server's public DNS name or external address: for a standalone deployment, this is the Security Server's own address; for an HA deployment, use the HA logical/VIP address instead, per §9 below, never either node's own private address. Then click **ADD**.

Expected result: the message "Certificate registration request successful" is displayed, and the certificate's registration state changes to **Registration in process**. After CamDX (the X-Road governing authority) approves the request, the state changes to **Registered**. If CamDX rejects the request, no automatic notification appears in the Admin UI; CamDX notifies you through your onboarding channel, and the certificate remains in **Registration in process** until you unregister/delete it and submit a new authentication certificate from scratch.

## 9. HA-specific addressing (read this before §8 if you are configuring an HA pair)

This section applies only to a replicated native HA deployment ([Ubuntu HA](./ubuntu/high-availability-installation.md), [RHEL HA](./rhel/high-availability-installation.md)). It does not change anything in §1-§8/§10-§13 for a standalone deployment.

Two distinct addresses exist side by side in an HA deployment; do not let them blur together:

- `https://<PRIMARY_FQDN>:4000` is the **administration endpoint**: the Admin UI address you actually open in your browser throughout this document, always the primary's own address. The secondary has its own Admin UI at `https://<SECONDARY_FQDN>:4000`, used read-only, never for performing this document's steps.
- `<VIP_FQDN>` is the **logical external Security Server address**: the approved HA load-balancer/VIP FQDN recorded in the HA Deployment Profile. Use this value, not `<PRIMARY_FQDN>` and not `<SECONDARY_FQDN>`, wherever this document asks for the Security Server's DNS name/external address for the purpose of PKI or registration: the authentication-certificate CSR's CN/SAN in §6.2, and the address entered in §8's registration dialog. Confirm `<VIP_FQDN>` actually resolves to, and routes to, the load balancer/VIP (which then performs Layer-4 TCP passthrough to whichever backend node is healthy) before submitting the CSR or the registration request.

For a replicated native HA deployment, perform this entire document (§1-§8, §10-§13) on the **primary node's Admin UI only**, using `<VIP_FQDN>` wherever an external/DNS address is asked for:

1. Complete the HA infrastructure/replication procedure first (the installation guide's Phases 0-17), including the secondary's `serverconf` database connection (Phase 10).
2. Perform §1-§8 and §10-§13 of this document on the **primary node's Admin UI only** (`https://<PRIMARY_FQDN>:4000`).
3. Do not initialize the secondary as another Security Server: do not open its first-time setup sequence, import the configuration anchor there, create a token, generate keys, or attempt registration there.
4. After §8 completes on the primary, perform the installation guide's one-time bootstrap synchronization (Phase 19) once, manually; this carries the initial global configuration and signer/token state to the secondary. `serverconf` itself is already live on the secondary continuously, via PostgreSQL streaming replication, independent of this sync.
5. Verify the secondary reflects the same logical Security Server identity, not a separate one, and that its global configuration is valid and independently refreshing (Phase 21).
6. Log in/unlock the software token on the secondary using the approved mechanism (manual PIN entry by a retained security-officer role, via the secondary's own Admin UI **Keys and Certificates, Token, Login**); it does not unlock automatically when the token file is replicated.
7. Use the secondary's Admin UI as read-only, except for the token/PIN operations the retained `xroad-security-officer` role permits.

See the installation guide's own Phase 10 and Phase 18-21 for the exact commands and verification steps.

## 10. Member registration status / subsystem registration

Once the authentication certificate is **Registered** (§8):

1. In the **Navigation tabs**, select **CLIENTS**.
2. Locate the member in the client list and click **Add Subsystem** at the end of its row.
3. In the wizard: select an existing subsystem from the global list via **SELECT SUBSYSTEM**, or enter the **Subsystem Code** manually (per §1, as provided or confirmed by CamDX).
4. If you want to register the subsystem immediately, check **Register subsystem**, then click **ADD SUBSYSTEM**. If the checkbox was checked, a confirmation popup appears; click **YES**.

Expected result: the subsystem appears in the client list in the **Saved** state (if registration was not requested immediately) or progresses to **Registration in progress** and then **Registered** (if it was).

For a subsystem that consumes services over HTTP internally: in the **Navigation tabs**, select **CLIENTS**, select the subsystem, open its **INTERNAL SERVERS** tab, and use the **Connection type** drop-down to select `HTTP`, `HTTPS NOAUTH`, or `HTTPS` (the default for new clients) according to your integration. The change is saved immediately on selection; a "Connection type updated" message confirms it. Confirm the correct setting for your integration; do not assume `HTTP` is always correct, and note that `HTTPS` requires the client information system's own TLS certificate to be trusted by the Security Server first (see the User Guide's Information System TLS certificate management).

## 11. Final registration/status checks

Before considering the Security Server ready for use, confirm, in the **Navigation tabs**:

- **KEYS AND CERTIFICATES**: the authentication certificate shows **Registered** (not merely **Saved**/imported, and not **Registration in process**).
- **KEYS AND CERTIFICATES**: the signing certificate shows **Registered**, associated with the correct member.
- **KEYS AND CERTIFICATES**: the software token row shows logged in (its **LOG IN** button reads **LOG OUT**), not PIN-locked.
- **CLIENTS**: the relevant subsystem(s) show **Registered**.
- Global configuration is downloading successfully: no `anchor_file_not_found` error and no persistent download error shown in the Admin UI.

## 12. CamDX-specific settings

CamDX requires one setting beyond the X-Road defaults:

| Setting | Section | Value | Notes |
|---|---|---|---|
| `message-body-logging` | `[message-log]` | `false` | Disables full message-body logging. Required by CamDX. |

**Native (Ubuntu/RHEL):** check whether `/etc/xroad/conf.d/local.ini` already exists before editing it; this file is merge-sensitive and other settings (such as the HA-specific `[proxy]` section) may already live in it.

```bash
sudo test -f /etc/xroad/conf.d/local.ini && echo "exists" || echo "does not exist yet"
```

**If it does not exist yet**, create it directly:

```bash
sudo tee /etc/xroad/conf.d/local.ini >/dev/null <<'EOF'
[message-log]
message-body-logging=false
EOF
sudo chown xroad:xroad /etc/xroad/conf.d/local.ini
sudo chmod 640 /etc/xroad/conf.d/local.ini
```

**If it already exists**, back it up, inspect it, and edit it directly rather than overwriting it:

```bash
sudo cp -a /etc/xroad/conf.d/local.ini /etc/xroad/conf.d/local.ini.pre-standalone-settings
sudo cat /etc/xroad/conf.d/local.ini
sudoedit /etc/xroad/conf.d/local.ini
```

Ensure the file contains exactly one `[message-log]` section with `message-body-logging=false` inside it (add the line to the existing section if `[message-log]` is already present; do not create a second `[message-log]` section). Verify there is no duplicate:

```bash
grep -n '^\[' /etc/xroad/conf.d/local.ini
```

Expected result: `[message-log]` appears exactly once.

Changing a value in `local.ini` requires restarting `xroad-proxy` for it to take effect:

```bash
sudo systemctl restart xroad-proxy
```

**Container:** CamDX has not yet published a supported container configuration mechanism for this setting. Contact CamDX for the applicable container configuration.

Contact CamDX to confirm any other setting for your deployment that is not covered by the defaults applied during installation.

## 13. Operational Monitoring

Operational Monitoring capability is required for every CamDX Security Server. Local Operational Monitoring, installed and running on the Security Server itself, is the standard standalone configuration and is set up automatically by the recommended installers.

Remote/external Operational Monitoring is a supported alternative: a dedicated Operational Monitoring node outside the Security Server, which may serve one or more Security Servers depending on the approved topology. This is not an HA-only mechanism. If your deployment requires this topology, contact CamDX before deployment.

## 14. References

- [`network-requirements.md`](./network-requirements.md): connectivity this configuration workflow depends on.
- [`high-availability-deployment-profile.md`](./high-availability-deployment-profile.md): source of every `<PRIMARY_FQDN>`/`<SECONDARY_FQDN>`/`<VIP_FQDN>` value referenced in §9.
- [Ubuntu HA Installation](./ubuntu/high-availability-installation.md), [RHEL HA Installation](./rhel/high-availability-installation.md): the HA-specific procedure §9 above refers to.
- Upstream X-Road Security Server User Guide and Security Server Installation Guide (`nordic-institute/X-Road`, version 7.8.2): source of the UI terminology used throughout this document.
