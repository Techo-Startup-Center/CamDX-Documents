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

If the Admin UI already completed first-time setup previously (for example, you are returning to an already-initialized Security Server), log in directly: this skips only the first-run initialization wizard above. Continue with §5 (Timestamping service configuration) next, then §6 onward; do not skip past §5.

## 5. Timestamping service configuration

1. In the **Navigation tabs**, select **SETTINGS**.
2. Select the **SYSTEM PARAMETERS** tab.
3. In the **Timestamping Services** section, click **ADD**.
4. In the dialog that opens, select the CamDX-approved timestamping service for this deployment's environment from the list (not merely "the appropriate" one by your own judgment; confirm with CamDX which service is approved for Development vs. Production if you are unsure).
5. Click **ADD** in the dialog to confirm.

Expected result: the selected service now appears listed in the **Timestamping Services** table.

## 6. Signing and authentication keys

Two separate keys are required, both generated on the software token. In the **Navigation tabs**, select **KEYS AND CERTIFICATES**. The software token appears in the **SIGN AND AUTH KEYS** table.

**Log in to the token first, if it is not already logged in:** click **LOG IN** on the token's row and enter the PIN set in §4. Once the correct PIN is entered, the button changes to **LOG OUT**, confirming the token is now unlocked.

### 6.1 Signing key

1. Expand the token's row by clicking the caret next to the token name, then click **ADD KEY**.
2. In the wizard: optionally define a label for the key (for example `SignKey`), click **NEXT**.
3. On the next page: select **Usage** = `SIGNING`; select **Client** = the member/subsystem this key signs for; select **Certification Service** = the CamDX intermediate CA; select **CSR Format** = `PEM` (unless the CamDX CA's profile pre-selects and locks a different format, in which case use the pre-selected value). Click **CONTINUE**.
4. Review the certificate owner's information shown, filling in any empty required field, then click **GENERATE CSR**. This prompts your browser to save/download the generated CSR file to your administrator workstation.
5. Save the download using a deterministic, descriptive filename rather than your browser's default name, so you (or a colleague) can identify it later without opening it; for example `<member-code>-signing.csr`.
6. Click **DONE**.

Expected result: a "Request" record appears under the token's row, indicating the signing CSR now exists for this key, and the saved file `<member-code>-signing.csr` exists on your workstation. The exact save-dialog behavior is a function of your own browser and operating system, not this guide; whatever that behavior is, verify the file actually exists on disk before continuing (for example, check your downloads folder or the location you chose). No private key is ever part of this file or needs to be checked; the token keeps the private key, never exports it.

### 6.2 Authentication key

1. Expand the token's row (if not already expanded), click **ADD KEY**.
2. In the wizard: optionally define a label (for example `AuthKey`), click **NEXT**.
3. On the next page: select **Usage** = `AUTHENTICATION`; select **Certification Service** = the CamDX intermediate CA; select **CSR Format** = `PEM`. Click **CONTINUE**.
4. Review the certificate fields shown and fill in the empty ones based on what the CamDX intermediate CA's certificate profile presents for this request. The **CN** field must be the CamDX Security Server's FQDN: for a standalone deployment, your own Security Server's FQDN; for a native HA deployment, `<VIP_FQDN>` (see §9 below). Only populate a **SAN** field if the CA's own profile/UI presents or requires one for this manual authentication CSR; SAN is an ACME-specific domain-validation requirement upstream, not a universal requirement for this manual workflow, so do not add one yourself if the profile does not ask for it. Then click **GENERATE CSR**. This prompts your browser to save/download the generated CSR file to your administrator workstation.
5. Save the download using a deterministic, descriptive filename; for example `<security-server-code>-authentication.csr`.
6. Click **DONE**.

Expected result: a "Request" record appears under the token's row for the authentication key, the same way as the signing key, and the saved file `<security-server-code>-authentication.csr` exists on your workstation. Verify the file actually exists on disk before continuing, the same way as §6.1's signing CSR.

### 6.3 Submitting the CSRs

Before submitting, verify both CSR files exist on the administrator workstation: `<member-code>-signing.csr` (§6.1) and `<security-server-code>-authentication.csr` (§6.2). Neither file contains, nor should ever be used to display, any private key: the token generated and keeps the private key internally; only the CSR (a public request) was exported.

Send both files to CamDX through your approved onboarding channel. CamDX issues the corresponding certificates and returns them to you.

## 7. Certificate import

Once CamDX issues both certificates, import each one using the exact control for its own certificate type; the two types use different literal UI actions.

### 7.1 Importing the signing certificate

1. In the **Navigation tabs**, select **KEYS AND CERTIFICATES**.
2. Expand the token's row by clicking the caret next to the token name.
3. Locate the "Request" record under the **signing** key (the one you generated in §6.1).
4. Click **IMPORT CERT.**.
5. Locate the signing certificate file on the local file system and click **OK**.

Expected result: the "Request" record under the signing key's row is replaced with the imported certificate's information. By default, the signing certificate is imported in the **Registered** state; it does not need separate activation.

### 7.2 Importing the authentication certificate

1. In the **Navigation tabs**, select **KEYS AND CERTIFICATES**.
2. Expand the token's row by clicking the caret next to the token name.
3. Locate the "Request" record under the **authentication** key (the one you generated in §6.2).
4. Click **Import certificate**.
5. Locate the authentication certificate file on the local file system and click **OK**.

Expected result: the "Request" record under the authentication key's row is replaced with the imported certificate's information. By default, the authentication certificate is imported in the **Saved** (registration) and **Disabled** (validity) states; it requires explicit activation before use (§7.3).

### 7.3 Activate the authentication certificate

1. Click the authentication certificate's row to open its **Certificate** dialog.
2. Click **Activate**.

Expected result: the certificate's validity state changes from **Disabled**. (Use **DISABLE** in the same dialog if you ever need to reverse this.)

## 8. Authentication certificate registration

**Preflight: verify the prerequisites below in the Admin UI before clicking Register.** Registration depends on the server's own signature over the request and on the certificates involved being usable; confirm, in the **Navigation tabs**:

1. **KEYS AND CERTIFICATES**: the software token row shows **LOG OUT** (meaning logged in), not **LOG IN**.
2. **KEYS AND CERTIFICATES**: the signing certificate (§7.1) shows registration state **Registered** in the **Status** column.
3. **KEYS AND CERTIFICATES**: the signing certificate's **OCSP** column reads **Good**. This column is directly checkable here because validity states other than "Disabled" are only displayed in the UI for a certificate that is already in the **Registered** registration state, which the signing certificate already is; **STOP** if it reads anything other than **Good** (for example **Unknown**, **Suspended**, **Expired**, or **Revoked**), and resolve that before continuing, rather than proceeding on an assumption that it will become good later.
4. **KEYS AND CERTIFICATES**: the authentication certificate (§7.2) is imported (no longer shows as a "Request" record).
5. **KEYS AND CERTIFICATES**: the authentication certificate's registration state is exactly **Saved** (the Register action's own documented precondition; not **Registration in progress**, not any other state).
6. **KEYS AND CERTIFICATES**: the authentication certificate is activated, not **Disabled** (§7.3). **This is also your OCSP evidence for the authentication certificate specifically**, and it is not optional: unlike the signing certificate, the authentication certificate's own OCSP/validity state is not yet displayed in the **OCSP** column at this point, because that column only shows a real validity state once a certificate reaches the **Registered** registration state, which the authentication certificate has not yet reached. Upstream X-Road states explicitly that "Certificate can be activated only when OCSP responses are valid," so a successful **Activate** in §7.3 is itself the documented proof that OCSP was good at that time. **STOP** if §7.3's **Activate** action did not succeed (for example, it was rejected, or the certificate still shows **Disabled**); do not register an authentication certificate that never cleared this check, and do not treat the absence of a visible OCSP column value here as permission to skip the requirement.

**STOP** if any of 1-6 is not yet true; resolve it (log the token in, finish §7.1-§7.3, or escalate if OCSP does not clear) before registering. Submitting a registration request while a prerequisite is missing wastes a registration attempt and can leave the certificate in a harder-to-diagnose state.

Once all 6 are confirmed:

1. In the **Navigation tabs**, select **KEYS AND CERTIFICATES**.
2. Expand the token's row, locate the authentication certificate, and click **Register** at the end of its row.
3. In the dialog that opens, enter the Security Server's public DNS name or external address: for a standalone deployment, this is the Security Server's own address; for an HA deployment, use the HA logical/VIP address instead, per §9 below, never either node's own private address. Then click **ADD**.

Expected result: the message "Certificate registration request successful" is displayed, and the certificate's registration state changes to **Registration in process**. After CamDX (the X-Road governing authority) approves the request, the state changes to **Registered**.

**If CamDX rejects the request:** no automatic notification appears in the Admin UI; CamDX notifies you through your onboarding channel, and the certificate remains in **Registration in process** in the Admin UI until you act. Do not assume a new CSR/certificate is always required: follow CamDX's specific rejection/reissuance instruction for that rejection, which will tell you which of the following apply: unregister and/or delete the rejected authentication certificate's registration state as instructed; import the certificate CamDX instructs you to use (which may be the same certificate, reissued, or a newly generated one, depending on the rejection reason); then submit the registration request again (repeat this section). A new CSR is only needed if CamDX specifically tells you reissuance is required for that rejection.

## 9. HA-specific addressing (read this before §8 if you are configuring an HA pair)

This section applies only to a replicated native HA deployment ([Ubuntu HA](./ubuntu/high-availability-installation.md), [RHEL HA](./rhel/high-availability-installation.md)). It does not change anything in §1-§8/§10-§13 for a standalone deployment.

Two distinct addresses exist side by side in an HA deployment; do not let them blur together:

- `https://<PRIMARY_FQDN>:4000` is the **administration endpoint**: the Admin UI address you actually open in your browser throughout this document, always the primary's own address. The secondary has its own Admin UI at `https://<SECONDARY_FQDN>:4000`, used read-only, never for performing this document's steps.
- `<VIP_FQDN>` is the **logical external Security Server address**: the approved HA load-balancer/VIP FQDN recorded in the HA Deployment Profile. Use this value, not `<PRIMARY_FQDN>` and not `<SECONDARY_FQDN>`, wherever this document asks for the Security Server's DNS name/external address for the purpose of PKI or registration: the authentication-certificate CSR's CN (and SAN, only if the CA's certificate profile presents or requires one) in §6.2, and the address entered in §8's registration dialog. Confirm `<VIP_FQDN>` actually resolves to, and routes to, the load balancer/VIP (which then performs Layer-4 TCP passthrough to whichever backend node is healthy) before submitting the CSR or the registration request.

**§9 itself is addressing and role guidance only. It is not a pause point, and it does not shorten which sections of this document you must complete.** The sequence for a replicated native HA deployment is:

1. Complete the HA infrastructure/replication procedure first (the installation guide's Phases 0-17), including the secondary's `serverconf` database connection (Phase 10).
2. Open the **primary node's Admin UI only** (`https://<PRIMARY_FQDN>:4000`).
3. Execute the applicable Initial Configuration workflow **completely** on the primary: §1 through §8, then §10 through §13, in order, using `<VIP_FQDN>` (never `<PRIMARY_FQDN>` or `<SECONDARY_FQDN>`) wherever an external/DNS address is asked for (the authentication-certificate CSR's CN in §6.2, and the registration address in §8). Consult this §9 as needed along the way for the addressing rule above and for the role/initialization boundary in item 4 below; do not stop at §8, and do not stop at the end of this §9 itself.
4. Do not initialize the secondary as another Security Server at any point in steps 1-3: do not open its first-time setup sequence, import the configuration anchor there, create a token, generate keys, or attempt registration there.
5. **Only after §13 is complete on the primary** (subsystem registration, final registration/status checks, the CamDX-specific `local.ini` setting, and Operational Monitoring are all done), leave this document and return to the installation guide to perform its one-time bootstrap synchronization (Phase 19) once, manually; this carries the initial global configuration and signer/token state to the secondary. `serverconf` itself is already live on the secondary continuously, via PostgreSQL streaming replication, independent of this sync.
6. Verify the secondary reflects the same logical Security Server identity, not a separate one, and that its global configuration is valid and independently refreshing (Phase 21).
7. Log in/unlock the software token on the secondary using the approved mechanism (manual PIN entry by a retained security-officer role, via the secondary's own Admin UI **Keys and Certificates, Token, Login**); it does not unlock automatically when the token file is replicated.
8. Use the secondary's Admin UI as read-only, except for the token/PIN operations the retained `xroad-security-officer` role permits.

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

**If it already exists**, back it up, inspect it, and edit it directly rather than overwriting it. First, check whether a backup from an earlier attempt already exists at the target backup path; do not let `cp` silently overwrite it:

```bash
sudo test -e /etc/xroad/conf.d/local.ini.pre-initial-config && echo "backup already exists" || echo "no existing backup"
```

**If no existing backup** (`no existing backup` above): create it normally.

```bash
sudo cp -a /etc/xroad/conf.d/local.ini /etc/xroad/conf.d/local.ini.pre-initial-config
```

**If a backup already exists** (`backup already exists` above): **STOP**. Do not overwrite it; it may be the only record of this file's state from an earlier attempt. Preserve it, and create this attempt's backup under a clearly distinct, unique name instead, for example by appending the current date:

```bash
sudo cp -a /etc/xroad/conf.d/local.ini "/etc/xroad/conf.d/local.ini.pre-initial-config.$(date +%Y%m%d%H%M%S)"
```

Either way, inspect the current file and edit it directly:

```bash
sudo cat /etc/xroad/conf.d/local.ini
sudoedit /etc/xroad/conf.d/local.ini
```

This backup file is separate from, and must not be confused with, either HA runbook's own `local.ini.pre-ha` backup (created in a different phase, for a different purpose); the two never collide by name, and this overwrite check does not change that.

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
