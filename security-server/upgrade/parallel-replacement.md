# CamDX 7.8.2 Security Server Member Migration - Parallel Replacement / Blue-Green

```text
CamDX's approved member Security Server migration procedure: APPROVED - FINAL.

THIS IS NOT AUTHORIZATION FOR UNCONTROLLED PRODUCTION ROLLOUT.

Production rollout of this procedure against any real member is NOT
AUTHORIZED by this document alone. Execution against a real member requires
explicit CamDX coordination and authorization for that specific migration,
as part of an assigned migration wave.
```

CamDX's approved member Security Server migration method is Parallel Replacement / Blue-Green. This document is the operator procedure for it. It does not repeat the broader boundaries (HA, Central Server, X-Road 8, production-rollout authorization boundaries) already stated in [Upgrade and Migration](./README.md); those apply identically here.

Execution against a real member requires CamDX authorization and coordination for that specific migration, as part of an assigned migration wave.

## 1. Scope

**Target:** an existing CamDX member Security Server, migrated to a clean CamDX 7.8.2 replacement Security Server.

**Migration principle: do not transform OLD in place. Deploy NEW beside OLD.**

- OLD is not upgraded or transformed in place at the X-Road software/configuration level, except for the controlled traffic-steering (Phase 4, Phase 7), monitoring (Phase 3), and later retirement (Phase 10, Phase 11) actions this procedure itself describes.
- NEW is a clean CamDX 7.8.2 deployment, built via an approved fresh-install path: [Ubuntu](../ubuntu/standalone-installation.md), [RHEL](../rhel/standalone-installation.md), or [Container](../container/deployment.md).
- NEW receives a **new** Security Server Code; OLD's code and identity are never reused or cloned onto NEW.
- OLD stays operational until NEW is accepted (Phase 9), then drained (Phase 10) and eventually retired (Phase 11).

**Primary member-side traffic model:**

```text
Application
        |
     Member-controlled Layer-4 load balancer
      /    \
    OLD    NEW (7.8.2)

CamDX central monitoring / Operational Monitoring:
    observes OLD AND NEW concurrently
```

Not every member uses a load balancer. Where a member uses a direct application-endpoint configuration or a DNS-based arrangement instead, the phases below adapt accordingly (Phase 7 covers each cutover mechanism); this procedure assumes some member-controlled traffic-steering mechanism exists, not a specific vendor.

**Provider-side boundary:** this procedure's cutover/rollback phases (Phase 7, Phase 8) are supported for member-controlled, load-balancer-fronted, or consumer-side migration. How remote CamDX Security Servers behave when they select among multiple **provider** Security Servers directly through X-Road global configuration, independent of any member-controlled load balancer, requires targeted confirmation with CamDX where direct provider-side peer selection is relevant to that member. This does not block using this procedure for consumer-side or load-balancer-fronted migration.

## 2. Migration state model

| State | Meaning |
|---|---|
| `READY` | Phase 0-3 complete: NEW is built, registered/configured, independently healthy at the pre-traffic readiness level, and monitoring is ready, but NEW has not yet been placed into normal member traffic. |
| `GO` | Explicit operator/member decision to add NEW to controlled traffic/coexistence (Phase 4 onward). |
| `HOLD` | Something is incomplete, ambiguous, or a dependency is unresolved; do not proceed to the next phase. A pause, not a failure verdict. |
| `ROLLBACK` | Traffic has been, or is being, returned to OLD per Phase 8. NEW remains available for diagnosis unless isolation is separately required. |
| `ACCEPTED` | NEW has met the acceptance criteria in Phase 9; the member's production traffic is intentionally and durably on NEW. |
| `RETIRED` | OLD has completed the drain (Phase 10) and retirement (Phase 11) sequence and is fully decommissioned. |

## 3. Source-generation handling

The same Parallel Replacement pattern applies regardless of which CamDX/X-Road generation OLD is running, because NEW is always a clean 7.8.2 deployment, not a multi-hop package-upgrade transformation of OLD. This procedure does not require, and does not describe, such an upgrade chain.

The source generation still matters for:

- **Inventory:** knowing exactly what OLD is running before starting (Phase 0).
- **Configuration comparison:** confirming NEW's configuration is functionally equivalent to OLD's for this member's actual usage.
- **Legacy behavior:** OLD's own log/message formats and Operational Monitoring behavior may differ by generation; NEW's own behavior does not depend on OLD's generation.
- **Monitoring/log format:** dual-observability evidence (Phase 6) is collected per server, in whatever format OLD's own generation produces.
- **Retirement:** OLD's own deregistration/certificate-retirement mechanics (Phase 11) may vary by generation and must be confirmed for the actual OLD being retired.
- **Member-specific compatibility:** a member's own configuration, integrations, or provider dependencies may behave differently depending on OLD's generation.

## Phase 0 - Readiness / inventory

Before deploying NEW, capture OLD's current state:

- OLD Security Server version and Security Server Code.
- Member/subsystem(s) configured on OLD.
- Relevant service/client configuration (service descriptions, access rights, client permissions).
- Current load-balancer backend configuration, or equivalent traffic-steering mechanism; confirm which one this member actually uses.
- NAT/source-IP behavior as OLD is currently observed externally.
- AUTH/SIGN certificate and token state.
- Operational Monitoring state (local vs. remote/external topology, per [Initial Configuration](../initial-configuration.md)).
- Message-log health.
- A known-good API request/response baseline, for later comparison.
- Rollback owner/contact: who on the member's side, and CamDX's side, can authorize and execute a rollback decision during this migration.

Confirm the member's topology is compatible with Parallel Replacement before proceeding: this procedure assumes some member-controlled traffic-steering mechanism exists. A member with a single hard-coded endpoint and no application-level flexibility requires a separately designed cutover approach; contact CamDX.

## Phase 1 - Build NEW 7.8.2

Use only an approved fresh-install path: [Ubuntu](../ubuntu/standalone-installation.md), [RHEL](../rhel/standalone-installation.md), or [Container](../container/deployment.md). Do not improvise deployment steps beyond the canonical guide used.

NEW must have a new Security Server Code, a new independent identity, and new AUTH/SIGN material generated according to normal CamDX registration policy. Do not clone OLD's identity or copy OLD's private keys to duplicate identity; NEW's credentials are generated fresh, on NEW's own token, exactly as any new Security Server's would be.

## Phase 2 - Register / configure NEW

This is a pre-traffic readiness checkpoint. NEW is not yet placed into normal member traffic at the end of this phase; intentional production traffic cutover occurs only in Phase 7.

Complete, per [Initial Configuration](../initial-configuration.md):

- Configuration anchor import.
- Software token initialization.
- AUTH key/CSR workflow.
- SIGN key/CSR workflow; use the correct AUTH-vs-SIGN semantics (AUTH usage for the authentication key, SIGNING usage tied to the member's X-Road identifier for the signing key).
- NEW Security Server registration (CamDX Central Authority approval required; not self-service).
- The same required member/subsystem configuration OLD already has.
- Relevant client/service configuration matching this member's actual traffic needs.

Before NEW joins member traffic, confirm at the pre-traffic readiness level: registration is healthy; certificate/token state is healthy (see Phase 5 for the precise AUTH-vs-SIGN meaning of "healthy"); global configuration is healthy; the required member/subsystem is configured; relevant client/service configuration is present; monitoring prerequisites are ready (Phase 3).

A real API exchange may be performed in this phase only where the member has a safe, isolated test path to NEW that does not depend on the member's normal traffic-steering mechanism. The mandatory real API validation belongs in Phase 5, after NEW is reachable through the member's own controlled traffic mechanism (Phase 4).

## Phase 3 - Add NEW to monitoring

Ensure CamDX central monitoring / Operational Monitoring can observe both OLD's and NEW's Security Server Codes. Do not remove OLD's monitoring at this point. Confirm message-log and Operational Monitoring evidence is distinguishable by Security Server, so an operator reviewing evidence during coexistence can tell which server produced which record.

## Phase 4 - Add NEW to the member load balancer

Purpose: controlled reachability for validation, not intentional cutover. This phase makes NEW reachable through the member's own traffic-steering mechanism strictly so Phase 5 can perform its mandatory real API validation. Adding NEW here must not unintentionally shift ordinary member traffic onto it before Phase 5's validation succeeds; the specific mechanism (controlled/limited routing, canary or test traffic, backend weighting or selection, or another method appropriate to that member's own architecture) is a member-specific decision.

Where the member uses a Layer-4 load balancer: add NEW as an additional backend alongside OLD without unintentionally diverting ordinary traffic to it before Phase 5 succeeds; preserve Layer-4/passthrough behavior where that is the member's established architecture, and do not introduce TLS termination at the load balancer; do not remove OLD from the pool at this stage.

Where the member's traffic-steering mechanism is a direct application-endpoint change or a DNS-based arrangement, adapt this phase accordingly, following the same principle: controlled reachability, without removing OLD, without unintentionally shifting ordinary traffic.

```text
Phase 4 = controlled reachability for validation.
Phase 5 = mandatory API validation.
Phase 6 = coexistence / observation.
Phase 7 = intentional cutover.
```

## Phase 5 - Validate NEW

This phase carries the mandatory real API validation: NEW's readiness to serve actual member traffic through its normal traffic-steering path (Phase 4) is confirmed here. Before any meaningful cutover, confirm and document actual evidence for:

- NEW's health is correct, per the platform-specific deployment guide's own verification steps.
- NEW's registration is healthy (registered, not merely imported/activated).
- Certificate/token state is healthy: AUTH and SIGN have different semantics. AUTH requires registration/approval with the CamDX Central Authority, and the authentication certificate is active/healthy (imported, activated, and registered). SIGN's certificate is valid and active for the member/client identity, with healthy local token/certificate state; SIGN does not go through the same Central Authority registration-request workflow as AUTH.
- Global configuration download is healthy on NEW.
- The required member/subsystem is present and correctly configured on NEW.
- A real API request through NEW succeeds.
- Message logging is present on NEW.
- Operational Monitoring is present on NEW.
- Source/NAT behavior for NEW is correct, matching what any provider allowlist or peer expects.
- Required provider allowlists have been updated to include NEW's observed source address, where applicable; coordinate with CamDX for the source-IP-registration process.

Document the actual evidence collected for this specific migration.

## Phase 6 - Coexistence / observation

Run OLD and NEW concurrently, both receiving traffic (or NEW receiving validation/canary traffic, per the member's own risk tolerance), and collect from both: API request success/failure, message logs, Operational Monitoring data, errors, certificate/OCSP/TSA-related failures, traffic volume, and last-request timestamp.

The duration appropriate for this observation depends on the member's own risk profile and traffic volume; it is set per migration wave, in coordination with CamDX.

## Phase 7 - Traffic cutover

Move traffic toward NEW using the member's own established load-balancing (or equivalent) mechanism.

```text
Before:       LB -> OLD
Coexistence:  LB -> OLD + NEW
Cutover:      LB -> NEW
```

The exact member-specific configuration change made must be captured in that migration's own evidence record.

If this member is being migrated in a provider role, and remote CamDX Security Servers select among provider peers directly via X-Road global configuration rather than through this member's own load balancer, confirm that specific behavior with CamDX before treating this phase as complete for the provider role; the load-balancer-based cutover described above governs member-controlled/consumer-facing traffic and does not automatically govern that separate mechanism.

## Phase 8 - Rollback

If acceptance criteria (Phase 9) fail, or coexistence observation (Phase 6) surfaces a blocking problem, return traffic to OLD using the member's validated traffic-steering mechanism (load balancer, application endpoint, or DNS, as applicable). DNS-based or application-endpoint rollback does not behave identically to load-balancer rollback (timing and cache behavior differ); the actual mechanism used and its observed timing for this specific member must be captured in that migration's own evidence.

Verify after rollback: API request through OLD works; OLD's certificate/token state is healthy; OLD's Operational Monitoring is healthy; OLD's message logging is healthy.

NEW remains available for diagnosis unless isolation is separately required; rollback does not mean destroying or disabling NEW, only returning traffic to OLD.

No package downgrade. Rollback under this procedure is always traffic cutback to OLD.

## Phase 9 - Acceptance

NEW can be accepted (`ACCEPTED` state, §2) when:

- Required API traffic through NEW succeeds.
- CamDX monitoring sees NEW (Security Server Code visible in central monitoring/Operational Monitoring).
- Message logging is healthy on NEW.
- No blocking PKI/OCSP/TSA errors are present.
- Network/source-IP behavior for NEW is correct.
- Rollback has remained available throughout the observation window (OLD was never disabled or made unable to receive traffic back during this process).
- Member/operator acceptance is explicitly recorded; this is not a purely technical checklist.

## Phase 10 - Drain OLD

Once NEW is accepted: remove OLD from active member traffic (load-balancer pool, or equivalent). Do not immediately deregister or revoke OLD.

Observe, for a period appropriate to this member: NEW continues serving the intended traffic correctly; OLD receives no unintended member traffic (confirming the drain took effect); monitoring remains available for both servers during this observation.

## Phase 11 - Retire OLD

Only after acceptance (Phase 9) and after the rollback/observation window has formally closed (the decision has been made that rollback to OLD will not be needed).

Retirement, through its own separately controlled checklist, may include: final OLD logs/Operational Monitoring capture; removal of the obsolete load-balancer backend entry; obsolete DNS/NAT/firewall/allowlist cleanup referencing OLD; authentication-certificate retirement/removal for OLD's AUTH identity (Central Authority action, the same registration mechanism as Phase 5's AUTH validation); retirement/revocation/disablement of OLD's obsolete signing certificates/keys as applicable (this follows the member/client-identity token model, Phase 5, not the AUTH Security Server registration workflow); Security Server deregistration/removal for OLD (Central Authority action); other Central Authority cleanup as applicable; archiving migration evidence for this wave.

Do not perform a destructive retirement command that has not been confirmed for the specific platform/generation OLD is running; coordinate with CamDX before executing retirement actions.

## 4. What this procedure is not

- **Not an in-place package-upgrade procedure.** No `apt`/`dnf upgrade`, `rpm --force`, or repository-switching sequence is part of this procedure; see [Upgrade and Migration](./README.md).
- **Not authorization for uncontrolled production rollout.** Each real migration wave requires its own separate CamDX authorization.
- **Not an HA procedure.** This procedure does not cover HA migration. Existing HA deployments remain supported, but HA upgrade or topology changes require separate coordination with CamDX; see [Ubuntu HA](../ubuntu/high-availability-installation.md) and [RHEL HA](../rhel/high-availability-installation.md).
- **Not a Central Server migration procedure.** Central Server validation/migration is a wholly separate track; see [Upgrade and Migration](./README.md).
- **Not a blanket claim about provider-side X-Road peer-routing behavior.** See §1's provider-side boundary and Phase 7's cutover-specific note; confirm with CamDX where relevant.

## 5. References

- [Upgrade and Migration](./README.md).
- [Ubuntu Standalone Installation](../ubuntu/standalone-installation.md), [RHEL Standalone Installation](../rhel/standalone-installation.md), [Container Deployment](../container/deployment.md).
- [Initial Configuration](../initial-configuration.md).
