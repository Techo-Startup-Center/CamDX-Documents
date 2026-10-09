# Error Reference

## Status / scope

**This is not yet a complete X-Road error encyclopedia.** This reference covers commonly encountered CamDX/X-Road Security Server errors. If your exact error is not listed, preserve the exact message, collect the diagnostic information from [the Troubleshooting page](./README.md), and contact CamDX.

Before you start troubleshooting:

- **Preserve the exact error text/code.** Paraphrasing a message ("something about a certificate") loses information you'll need later, including when escalating to CamDX.
- **Note which X-Road component produced the error** (`xroad-proxy`, `xroad-signer`, `xroad-confclient`, `xroad-proxy-ui-api`, etc.) — the same symptom can mean different things from different components.
- **Some errors are symptoms, not root causes.** A connectivity failure, for example, can be caused by DNS, routing, a firewall, or the remote service itself — see [Connectivity](./connectivity.md) for how to narrow it down before assuming the first explanation.
- **Never delete certificates, signer state, `serverconf`, or key material merely because an error appears.** Destructive recovery is not a troubleshooting step — if you are ever tempted to do this, stop and contact CamDX first.

## Entry format

Every entry below follows this structure:

```text
## <ERROR CODE / MESSAGE>

**Component**
**What it means**
**Common causes**
**Check**
**What to do**
**Do not**
**Escalate to CamDX when**
**Related documentation**
```

## `USER_PIN_INCORRECT`

**Component:** `xroad-signer` (software token)

**What it means:** The PIN presented to unlock the software token does not match the token's actual PIN.

**Common causes:** For the container deployment specifically, this is directly evidenced as a mismatch between the `XROAD_TOKEN_PIN` environment variable and the PIN the token was actually initialized with. For native (Ubuntu/RHEL) deployments, the same underlying condition applies whenever the PIN entered at the Admin UI or via `xroad-autologin`'s configured PIN source does not match the token.

**Check:** `docker logs <container>` (container) or the relevant signer log (native) for repeated `USER_PIN_INCORRECT` entries; confirm what PIN value the deployment is actually configured to present.

**What to do:** Confirm the correct PIN with whoever holds it for this Security Server, and correct the configured PIN source (the `XROAD_TOKEN_PIN` environment variable for the container path; the Admin UI/PIN-entry mechanism for native installs). Do not repeatedly guess the PIN. If X-Road reports remaining attempts or that the PIN is locked, stop and escalate.

**Do not:** Do not reinitialize or delete the software token as a troubleshooting shortcut. Doing so can destroy the existing private-key material and invalidate the current certificate/key setup.

**Escalate to CamDX when:** The correct PIN is confirmed but the token still reports `USER_PIN_INCORRECT`, or the token has become locked.

**Related documentation:** [`../container/deployment.md`](../container/deployment.md) §15 (secrets handling), §17B (post-configuration runtime check).

## Token unavailable / inactive

**Component:** `xroad-signer`

**What it means:** The software token is not in the healthy, usable state. A healthy token reports status fields `OK`, `writable`, `available`, and `active` — anything else indicates a problem. The exact status-line format can differ slightly by platform; look for these four fields rather than matching an exact string.

**Common causes:** The token has not yet been initialized (expected on a fresh, not-yet-configured Security Server — this is not an error at that stage); the token is locked after repeated incorrect PIN attempts; the signer process is not running.

**Check:**
- Native: `sudo -u xroad -i signer-console list-tokens`
- CamDX container: `docker exec camdx-security-server signer-console list-tokens`

**If `signer-console` itself cannot connect** (a connection error rather than a token-status result), check `xroad-signer`/the signer process first (`systemctl status xroad-signer` natively, or `supervisorctl status` in the container) — that is a different problem from a token reporting unavailable/inactive. **If `signer-console` connects and returns a token status other than `OK, writable, available, active`**, investigate the token/PIN/configuration state directly.

**What to do:** If the Security Server has not yet completed [Initial Configuration](../initial-configuration.md), an uninitialized token is expected — continue that procedure. If the token was previously active and has since gone unavailable, confirm `xroad-signer` is running first before assuming a token problem.

**Do not:** Do not re-initialize the token to force it into an "available" state — this discards existing key material.

**Escalate to CamDX when:** `xroad-signer` is confirmed running, Initial Configuration is already complete, and the token still does not report `OK, writable, available, active`.

**Related documentation:** [`../container/deployment.md`](../container/deployment.md) §17B; [`../initial-configuration.md`](../initial-configuration.md).

## Global configuration expired or not updating

**Component:** `xroad-confclient`

**What it means:** The Security Server's local copy of X-Road global configuration (anchor-derived trust/configuration data shared across the ecosystem) is stale or has stopped refreshing. This directly affects message processing — the application-aware health check used elsewhere in this documentation set treats "global configuration valid and not expired" as one of its core health conditions.

**Common causes:** The confclient process cannot reach its configured source (a connectivity problem — see [Connectivity](./connectivity.md)); the configuration anchor itself is missing, invalid, or points at an unreachable source.

**Check:** Confirm `xroad-confclient` is running; review its log for repeated fetch failures; confirm outbound connectivity from this host to the configured global-configuration source per [`../network-requirements.md`](../network-requirements.md).

**What to do:** If connectivity is failing, restore connectivity first. If connectivity is healthy and configuration still does not refresh, verify the configured anchor/source and escalate as appropriate.

**Do not:** Do not manually edit or delete global-configuration cache files as a first response.

**Escalate to CamDX when:** Connectivity to the global-configuration source is confirmed healthy and the anchor is confirmed correct, but configuration still does not refresh.

**Related documentation:** [`../network-requirements.md`](../network-requirements.md); [Connectivity](./connectivity.md).

## OCSP status/check failure

**Component:** `xroad-signer`

**What it means:** The exact meaning depends on the exact X-Road message and certificate context — this entry does not cover every OCSP-related error as a single condition. In the evidenced Security Server health-check context specifically, a required certificate's OCSP status must be `good`; a health-check failure on this point means that condition is not currently met.

**Common causes:** The Security Server cannot reach the configured OCSP responder (a connectivity problem on the ports documented in [`../network-requirements.md`](../network-requirements.md)).

**Check:** First check reachability to the configured OCSP responder.

**What to do:** If reachability to the OCSP responder is not healthy, resolve that first. If reachability is healthy and the OCSP status/error persists, preserve the exact OCSP error/status and escalate rather than guessing the certificate condition.

**Do not:** Do not disable OCSP checking as a workaround.

**Escalate to CamDX when:** Reachability to the OCSP responder is confirmed healthy but the OCSP status/error persists.

**Related documentation:** [`../network-requirements.md`](../network-requirements.md); [Connectivity](./connectivity.md).

## `serverconf` / database connectivity failure

**Component:** `xroad-proxy` / the Security Server's PostgreSQL database (local or external, depending on your deployment)

**What it means:** The Security Server cannot reach or query its `serverconf` database — this is one of the four conditions the application-aware health check directly verifies, and is also checked explicitly during container/native startup via database connection/migration log messages.

**Common causes:** The database service is not running or not yet healthy; network connectivity between the Security Server and an external database is broken; a credential mismatch (for the container deployment, specifically a stale `.env` value after a credential rotation that wasn't applied consistently to both sides).

**Check:** For the container path, use the canonical PostgreSQL health check in [`../container/deployment.md`](../container/deployment.md) §17A, which already covers the correct compose file and `--env-file` handling. For native deployments, check the relevant PostgreSQL service status and the Security Server/database logs. Preserve the exact database or migration error (for example, a `Liquibase` error is not necessarily the same condition as a connectivity error — note which one you actually have).

**What to do:** Confirm the database is reachable and healthy before investigating anything else. If a credential was recently rotated, confirm it was updated consistently everywhere it's configured.

**Do not:** Do not attempt a destructive database repair or reinitialize the database as a first response.

**Escalate to CamDX when:** The database is confirmed healthy and reachable, credentials are confirmed consistent, and the Security Server still cannot connect.

**Related documentation:** [`../container/deployment.md`](../container/deployment.md) §11 (database model, credential rotation); platform-specific installation guides' own database sections.

## Everything else

If your exact error is not listed here, preserve the exact message, identify the component that produced it, collect the diagnostic information from the [Troubleshooting page](./README.md), and contact CamDX.
