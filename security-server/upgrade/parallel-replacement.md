# CamDX 7.8.2 Security Server Member Migration — Parallel Replacement / Blue-Green

## Status: APPROVED — FINAL

```text
THIS IS THE APPROVED CAMDX 7.8.2 MEMBER SECURITY SERVER MIGRATION
PROCEDURE FOR THE PARALLEL REPLACEMENT / BLUE-GREEN IMPLEMENTATION
PATTERN.

THIS IS NOT AUTHORIZATION FOR UNCONTROLLED PRODUCTION ROLLOUT.

Migration implementation pattern (Parallel Replacement / Blue-Green):
APPROVED — decision 03-A2.

This procedure document: APPROVED — FINAL.

Member Migration & Release Readiness: NOT STARTED / GATED.

Production rollout of this procedure against any real member: NOT
AUTHORIZED by this document alone. Each migration wave requires its own
separate authorization.
```

This document operationalizes the approved Parallel Replacement / Blue-Green implementation pattern (decision `03-A2`) into a concrete operator procedure for migrating an existing CamDX Security Server member to CamDX/X-Road 7.8.2. It supersedes nothing in [`README.md`](./README.md) (the canonical Upgrade / Member Migration Status and Safety document) — that document's boundaries (HA, Central Server, X-Road 8, production-rollout gating) apply identically here and are not repeated in full, only cross-referenced.

**Evidence basis:** this pattern's core mechanics are supported by **operator-confirmed operational evidence** — existing CamDX DC/DRC multi-Security-Server deployments already operate under different Security Server Codes without mutual interference, and a CamDX 7.8.2 Security Server has been successfully registered under a new Security Server Code, coexisting with an existing Security Server, with member application traffic exercised through both and load-balancer-mediated traffic steering between them. **This is operator-confirmed operational evidence, not independently re-executed laboratory validation** — no synthetic test log, timestamp, or member identifier from a lab exercise is fabricated or implied anywhere in this document. See `decisions.md` decision `03-A2` (`~/TI-Director-Brain/initiatives/camdx-xroad-upgrade/`) for the full evidence statement.

## 1. Scope

**Target:** an existing CamDX member Security Server, against the verified baseline of existing OLD checkpoints — observed production Security Server generations 7.2.2 and 7.3.2, and the 7.4.2 new-member installation generation — → a clean CamDX 7.8.2 replacement Security Server.

**Migration principle — do not transform OLD in place. Deploy NEW beside OLD.**

- **OLD is not upgraded or transformed in place under this procedure.** During migration, OLD remains operational and unchanged at the X-Road software/configuration level, except for the explicitly controlled traffic-steering (Phase 4, Phase 7), monitoring (Phase 3), and later retirement (Phase 10, Phase 11) actions this procedure itself describes — this does not weaken the rule against in-place X-Road upgrade; it only acknowledges that OLD's traffic participation and eventual disposition intentionally change over the course of a migration wave.
- NEW is a clean CamDX 7.8.2 deployment, built via an already-approved fresh-install path ([`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md), [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md), or [`../container/deployment.md`](../container/deployment.md)).
- NEW receives a **new** Security Server Code — OLD's code and identity are never reused or cloned onto NEW.
- OLD stays operational until NEW is accepted (Phase 9) and only then drained (Phase 10) and eventually retired (Phase 11).

**Primary member-side traffic model:**

```text
Application
        |
     Nginx / member-controlled Layer-4 load balancer
      /    \
    OLD    NEW (7.8.2)

CamDX central monitoring / Operational Monitoring:
    observes OLD AND NEW concurrently
```

**Not every member uses this exact topology.** Where a member does not use a Layer-4 load balancer (e.g. a direct application-endpoint configuration, or a DNS-based arrangement), the phases below adapt accordingly (Phase 7 covers each cutover mechanism this procedure supports) — this document does not assume Nginx specifically, only that *some* member-controlled traffic-steering mechanism exists.

**Provider-side boundary (read before using this procedure for a provider member — the full detail is below in this section):** the operator-confirmed evidence above establishes the **member-controlled application/load-balancer migration model**. It does **not** by itself establish how remote CamDX Security Servers behave when they select among multiple **provider** Security Servers directly through X-Road global configuration, independent of any member-controlled load balancer. That specific behavior is classified `TARGETED VALIDATION REQUIRED IF APPLICABLE` — evaluate it only for members/topologies where direct provider-side peer selection is actually relevant, and do so before relying on this procedure's cutover/rollback phases (Phase 7, Phase 8) for that member's provider role specifically. **This does not block using this procedure for consumer-side or load-balancer-fronted migration**, which is fully supported by the operator-confirmed evidence.

## 2. Migration result model

A concise, operational (not numerical-score) model for tracking a given member's migration status through this procedure:

| State | Meaning |
|---|---|
| `READY` | Phase 0–3 complete: NEW is built, registered/configured, independently healthy at the pre-traffic readiness level (Phase 2), and monitoring is ready (Phase 3) — but NEW has **not yet** been placed into normal member traffic. |
| `GO` | Explicit operator/member decision to add NEW to controlled traffic/coexistence (Phase 4 onward). |
| `HOLD` | Something is incomplete, ambiguous, or a dependency is unresolved — do not proceed to the next phase. Applies at any phase; not a failure verdict, a pause. |
| `ROLLBACK` | Traffic has been (or is being) returned to OLD per Phase 8. NEW remains available for diagnosis unless isolation is separately required. |
| `ACCEPTED` | NEW has met the acceptance criteria in Phase 9 — the member's production traffic is intentionally and durably on NEW. |
| `RETIRED` | OLD has completed the drain (Phase 10) and retirement (Phase 11) sequence and is fully decommissioned. |

These states describe **where a given migration wave for a given member currently stands** — they are not a scoring system, and no numeric weighting is attached to them.

## 3. Source-generation handling

**The same Parallel Replacement implementation pattern is intended to apply across OLD generations 7.2.2, 7.3.2, and 7.4.2** — the verified baseline recorded in [`README.md`](./README.md) §1 (observed production Security Server generations 7.2.2 and 7.3.2; the 7.4.2 new-member installation generation) — because NEW is always a clean 7.8.2 deployment, **not** a multi-hop package-upgrade transformation of OLD (7.2.2→7.3.x→7.4.x→…→7.8.2). This procedure does not require, and does not describe, any such upgrade chain.

**The source generation is not irrelevant, however.** It still matters for:

- **Inventory** — knowing exactly what OLD is running before starting (Phase 0).
- **Configuration comparison** — confirming NEW's configuration is functionally equivalent to OLD's for this member's actual usage, which requires knowing OLD's real settings.
- **Legacy behavior** — OLD's own log/message formats, OPMON behavior, and operational quirks may differ by generation; this procedure does not assume they are identical, only that NEW's *own* behavior does not depend on OLD's generation.
- **Monitoring/log format** — dual-observability evidence (Phase 6) is collected per-server, and OLD's log/OPMON format is whatever its own generation produces — not normalized or assumed uniform across 7.2.2/7.3.2/7.4.2.
- **Retirement** — OLD's own deregistration/certificate-retirement mechanics (Phase 11) may vary by generation and must be confirmed for the actual OLD being retired, not assumed from another generation's experience.
- **Member-specific compatibility** — a given member's own configuration, integrations, or provider dependencies may behave differently depending on which generation OLD actually is.

## Phase 0 — Readiness / inventory

Before deploying NEW, capture OLD's current state:

- OLD Security Server version (exact generation — 7.2.2/7.3.2/7.4.2/other).
- OLD Security Server Code.
- Member/subsystem(s) configured on OLD.
- Relevant service/client configuration (service descriptions, access rights, client permissions).
- Current load-balancer backend configuration (or equivalent traffic-steering mechanism) — **do not assume Nginx specifically**; confirm which member-controlled Layer-4 load balancer, application-endpoint mechanism, or DNS arrangement this member actually uses.
- NAT/source-IP behavior as OLD is currently observed externally.
- AUTH/SIGN certificate and token state.
- OPMON state (local vs. remote/external topology, per [`../initial-configuration.md`](../initial-configuration.md) §12).
- Message-log health.
- Current API baseline (a known-good request/response sample, for later comparison).
- Rollback owner/contact — who on the member's side (and CamDX's side) can authorize and execute a rollback decision during this migration.

**Confirm the member's actual topology is compatible with Parallel Replacement before proceeding** — this procedure assumes some member-controlled traffic-steering mechanism exists (load balancer, application configuration, or DNS); if a member's architecture genuinely has none of these (a single hard-coded endpoint with no intermediary and no application-level flexibility), that member requires a separately-designed cutover approach before this procedure applies to them unmodified.

## Phase 1 — Build NEW 7.8.2

Use only an already-approved fresh-install path:

- [`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md)
- [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md)
- [`../container/deployment.md`](../container/deployment.md)

Do not improvise deployment steps beyond whichever canonical guide is used.

**NEW must have:**

- A **new** Security Server Code — never OLD's code.
- A new, independent identity.
- New AUTH/SIGN material generated according to normal CamDX registration policy.

**Do not clone OLD's identity. Do not copy OLD's private keys merely to duplicate identity.** NEW's credentials are generated fresh, on NEW's own token, exactly as any new Security Server's would be.

## Phase 2 — Register / configure NEW

**This is a pre-traffic readiness gate.** NEW is not yet placed into normal member traffic at the end of this phase. Phase 4 makes NEW reachable through the member's controlled traffic-steering mechanism specifically so that Phase 5 can perform its mandatory real API validation — this is controlled reachability for validation purposes, not yet ordinary production traffic. **Intentional production traffic cutover occurs only in Phase 7.**

Complete, per [`../initial-configuration.md`](../initial-configuration.md):

- Configuration anchor import.
- Software token initialization.
- AUTH key/CSR workflow.
- SIGN key/CSR workflow — **use the correct AUTH-vs-SIGN semantics** (AUTH usage for the authentication key, SIGNING usage tied to the member's X-Road identifier for the signing key; do not conflate the two CSR types).
- NEW Security Server registration (CamDX Central Authority approval required — this is not self-service).
- The same required member/subsystem configuration OLD already has.
- Relevant client/service configuration matching what this member's actual traffic needs.

**Before NEW joins member traffic, confirm at the pre-traffic readiness level:**

- Registration is healthy.
- Certificates/token state is healthy (see Phase 5 for the precise AUTH-vs-SIGN meaning of "healthy" for each).
- Global configuration is healthy.
- The required member/subsystem is configured.
- Relevant client/service configuration is present.
- Monitoring prerequisites are ready (feeds into Phase 3).

**A real API exchange MAY be performed in this phase only where the member has a safe, isolated/direct test path to NEW that does not depend on the member's normal traffic-steering mechanism.** This is not universally mandatory here — do not require a direct isolated test path for every member merely to satisfy this phase. **The mandatory real API validation belongs in Phase 5**, after NEW has been made reachable through the member's own controlled traffic mechanism (Phase 4).

## Phase 3 — Add NEW to monitoring

Ensure CamDX central monitoring / Operational Monitoring can observe **both**:

- OLD's Security Server Code
- NEW's Security Server Code

**Do not remove OLD's monitoring at this point.** Confirm message-log and OPMON evidence is distinguishable **by Security Server** — an operator reviewing evidence during coexistence must be able to tell which server produced which record, not see a merged, unattributed stream.

## Phase 4 — Add NEW to the member load balancer

**Purpose: controlled reachability for validation, not intentional cutover.** This phase makes NEW reachable through the member's own traffic-steering mechanism strictly so that Phase 5 can perform its mandatory real API validation against NEW. **Adding/making NEW reachable here must not unintentionally shift ordinary member traffic onto NEW before Phase 5's validation succeeds** — the specific member mechanism used to achieve this (controlled/limited routing, canary or test traffic, backend weighting or selection, or another method appropriate to that member's own architecture) is a member-specific decision; **no vendor-specific implementation is prescribed here.**

Where the member uses Nginx or another member-controlled Layer-4 load balancer:

- Add NEW as an additional backend, alongside OLD, in a way that does not unintentionally divert ordinary traffic to it before Phase 5 validation succeeds.
- **Preserve Layer-4/passthrough behavior where that is the member's established architecture** — do not introduce TLS termination at the load balancer, and do not otherwise change the load balancer's architecture, merely because a migration is occurring.
- **Do not remove OLD from the pool at this stage.**

**No vendor-specific Nginx (or other LB) commands are published in this canonical procedure unless they are supported by the member's actual configuration and separately reviewed for that member.** The exact member-specific configuration change made must be captured in that migration's own evidence record, not invented generically here.

Where the member's traffic-steering mechanism is a direct application endpoint change or a DNS-based arrangement rather than a load balancer, adapt this phase accordingly — add NEW as a second valid target the member's own mechanism can select between, following the same "controlled reachability, without removing OLD, without unintentionally shifting ordinary traffic" principle.

**Phase sequencing principle, stated explicitly:**

```text
Phase 4 = controlled reachability for validation.
Phase 5 = mandatory API validation.
Phase 6 = coexistence / observation.
Phase 7 = intentional cutover.
```

## Phase 5 — Validate NEW

**This phase carries the mandatory real API validation** — regardless of whether Phase 2 already performed an optional isolated test, NEW's readiness to serve actual member traffic through its normal traffic-steering path (Phase 4) is confirmed here.

Before any meaningful cutover, confirm and document actual evidence for:

- NEW's health is correct (per the platform-specific approved deployment guide's own health checklist).
- NEW's registration is healthy (registered, not merely imported/activated).
- **Certificate/token state is healthy — AUTH and SIGN have different semantics, not identical ones:**
  - **AUTH:** registration/approval with the CamDX Central Authority is completed, and the authentication certificate is active/healthy as required (imported, activated, and registered — not merely imported).
  - **SIGN:** the signing certificate is valid and active for the member/client identity, with healthy local token/certificate state — **SIGN does not go through the same separate Central Authority registration-request workflow as AUTH**; do not assert or imply that it does.
- Global configuration download is healthy on NEW.
- The required member/subsystem is present and correctly configured on NEW.
- A real API request through NEW succeeds.
- Message logging is present on NEW.
- OPMON is present on NEW.
- Source/NAT behavior for NEW is correct (matches what any provider allowlist or peer expects).
- Required provider allowlists have been updated to include NEW's observed source address, where applicable (see [`../provider-connectivity.md`](../provider-connectivity.md) §5 for the source-IP-registration model).

**Document the actual evidence collected — do not assert these criteria are met without a corresponding observation recorded for this specific migration.**

## Phase 6 — Coexistence / observation

Run OLD and NEW concurrently, both receiving traffic (or NEW receiving validation/canary traffic, per the member's own risk tolerance), and collect from **both**:

- API request success/failure
- Message logs
- OPMON data
- Errors
- Certificate/OCSP/TSA-related failures
- Traffic volume
- Last request timestamp

**Do not require an arbitrary fixed observation duration in this canonical procedure.** The specific migration wave's own runbook defines the duration appropriate to that member — a low-risk member with light traffic may need less observation time than a high-volume or high-criticality one; this document does not invent a universal number.

## Phase 7 — Traffic cutover

Move traffic toward NEW using the member's own established load-balancing (or equivalent) mechanism.

**Conceptual state progression:**

```text
Before:       LB → OLD
Coexistence:  LB → OLD + NEW
Cutover:      LB → NEW
```

**Do not publish vendor-specific Nginx (or other LB) commands in this canonical procedure** unless they are supported by the member's actual configuration and separately reviewed for that specific member — the exact member-specific change made must be captured in that migration's own evidence, not invented generically here.

**On provider-side peer selection (see §1's provider-side boundary note for full detail):** if this member is being migrated in a **provider** role and remote CamDX Security Servers select among provider peers directly via X-Road global configuration rather than through this member's own load balancer, confirm that specific behavior for this member's topology (`TARGETED VALIDATION REQUIRED IF APPLICABLE`) before treating this phase as complete for the provider role — the load-balancer-based cutover described above governs member-controlled/consumer-facing traffic and does not automatically govern that separate mechanism.

## Phase 8 — Rollback

If acceptance criteria (Phase 9) fail, or coexistence observation (Phase 6) surfaces a blocking problem:

**Return traffic to OLD using the member's validated traffic-steering mechanism — load balancer, application endpoint, or DNS, as applicable.** This procedure does not imply that DNS-based or application-endpoint rollback behaves identically to load-balancer rollback (they do not, e.g. in timing and cache behavior) — the actual mechanism used and its observed timing for this specific member must be captured in that migration's own evidence.

Verify after rollback:

- API request through OLD works.
- OLD's certificate/token state is healthy.
- OLD's OPMON is healthy.
- OLD's message logging is healthy.

**NEW remains available for diagnosis unless isolation is separately required** — rollback does not mean destroying or disabling NEW, only returning traffic to OLD.

**No package downgrade.** Rollback under this procedure is always traffic cutback to OLD, consistent with the approved implementation pattern (`03-A2`) and with decision `03-A1`'s own recovery-point/no-package-downgrade principle.

## Phase 9 — Acceptance

NEW can be accepted (`ACCEPTED` state, §2) when:

- Required API traffic through NEW succeeds.
- CamDX monitoring sees NEW (Security Server Code visible in central monitoring/OPMON).
- Message logging is healthy on NEW.
- No blocking PKI/OCSP/TSA errors are present.
- Network/source-IP behavior for NEW is correct.
- Rollback has remained available throughout the observation window (i.e. OLD was never disabled or made unable to receive traffic back during this process).
- **Member/operator acceptance is explicitly recorded** — this is not a purely technical checklist; the member's own sign-off (or the delegated operator's, per whatever authority model this migration wave uses) is part of acceptance.

## Phase 10 — Drain OLD

Once NEW is accepted:

- Remove OLD from active member traffic (load-balancer pool, or equivalent).
- **Do not immediately deregister or revoke OLD.**

Observe, for a period appropriate to this member (again, not a fixed universal duration):

- NEW continues serving the intended traffic correctly.
- OLD receives no unintended member traffic (confirming the drain actually took effect).
- Monitoring remains available for both servers during this observation.

## Phase 11 — Retire OLD

**Only after acceptance (Phase 9) and after the rollback/observation window has formally closed** (i.e. the decision has been made that rollback to OLD will not be needed).

Retirement may include, through its own **separately controlled checklist** — not invented wholesale here:

- Final OLD logs/OPMON capture.
- Removal of the obsolete load-balancer backend entry.
- Obsolete DNS/NAT/firewall/allowlist cleanup referencing OLD.
- Authentication-certificate retirement/removal for OLD's AUTH identity (Central Authority action, same registration mechanism as Phase 5's AUTH validation).
- Retirement/revocation/disablement of OLD's obsolete signing certificates/keys, as applicable — **this is not identical to AUTH Security Server certificate registration/removal above**; SIGN material's disposition follows the member/client-identity token model (Phase 5), not the AUTH Security Server registration workflow.
- Security Server deregistration/removal for OLD (Central Authority action).
- Other Central Authority cleanup as applicable.
- Archiving migration evidence for this wave.

**Do not invent destructive commands for this phase unless they have been independently validated for the specific platform/generation OLD is running.** This procedure records what retirement must eventually cover, consistent with the equivalent retirement gate already documented in [`README.md`](./README.md) §11 — it does not publish an executable deregistration/revocation command sequence here, since that remains a separately controlled, platform/generation-specific checklist.

## 4. What this procedure is not

- **Not an in-place package-upgrade procedure.** No `apt`/`dnf upgrade`, `rpm --force`, or repository-switching sequence is introduced by this document — see [`README.md`](./README.md) §7 for the full, unchanged refusal to publish such a sequence.
- **Not authorization for uncontrolled production rollout.** Each real migration wave requires its own separate authorization, consistent with decision `03-A1`'s gated architecture and decision `03-A2`'s pattern approval — neither authorizes any specific member's migration by itself.
- **Not an HA procedure.** HA remains `REQUIRES VERIFICATION` per [`README.md`](./README.md) §12; this procedure does not publish HA rolling-upgrade, failover, or active/passive-switching content.
- **Not a Central Server migration procedure.** See [`README.md`](./README.md) §13 — Central Server validation/migration is a wholly separate track.
- **Not a blanket claim about provider-side X-Road peer-routing behavior.** See §1's provider-side boundary note and Phase 7's cutover-specific caveat — this remains a targeted validation item, not assumed resolved for every topology.

## 5. Change history

| Date | Change |
|---|---|
| 2026-09-26 (round 1) | Created. Drafted the operator procedure for CamDX 7.8.2 member migration via Parallel Replacement / Blue-Green, derived from the implementation pattern approved in decision `03-A2` on operator-confirmed operational evidence (existing DC/DRC multi-Security-Server operation under different Security Server Codes; a separately registered and coexisting CamDX 7.8.2 Security Server exercised through a member load balancer). Structured as 12 phases, Phase 0 through Phase 11 (readiness/inventory → build NEW → register/configure NEW → add to monitoring → add to load balancer → validate NEW → coexistence/observation → traffic cutover → rollback → acceptance → drain OLD → retire OLD), a migration result model (`READY`/`GO`/`HOLD`/`ROLLBACK`/`ACCEPTED`/`RETIRED`), and explicit source-generation handling (intended to apply across 7.2.2/7.3.2/7.4.2 as OLD, since NEW is always a clean 7.8.2 deployment — not a multi-hop package-upgrade chain — while the source generation still matters for inventory, configuration comparison, legacy log/OPMON format, retirement, and member-specific compatibility). Explicitly scoped the provider-side boundary: member-controlled/load-balancer-based migration is supported by operator-confirmed operational evidence; direct X-Road provider-side peer-selection routing through global configuration is classified `TARGETED VALIDATION REQUIRED IF APPLICABLE`, evaluated only where relevant, and does not block consumer-side/LB-based migration procedure use. No vendor-specific load-balancer commands are published generically; no destructive retirement command sequence is invented. This document is a draft, pending final review — not yet final operational documentation, and not authorization for uncontrolled production rollout. |
| 2026-09-26 (round 2, this round) | Final procedure precision cleanup, following a HOLD gate on round 1's content. The architecture, migration pattern, and phase sequence are unchanged. (1) **Fixed section/phase cross-references throughout** — every internal reference to a migration phase now reads "Phase N" (previously several incorrectly read "§N", conflating numbered document sections with named phases); genuine references to this document's own §1/§2 and to other documents' own numbered sections (`README.md`, `initial-configuration.md`, `provider-connectivity.md`) were left as `§N`, since those are correct. (2) **Corrected 7.4.2 estate wording** — no longer describes 7.4.2 as an "observed" generation on the same footing as 7.2.2/7.3.2; the Scope's Target line and §3 now state the verified baseline precisely (observed production Security Server generations 7.2.2 and 7.3.2; the 7.4.2 new-member installation generation), and §3's opening sentence changed from "applies uniformly" to "the same implementation pattern is intended to apply across" these generations, preserving the existing caveat that the source generation still matters for inventory/configuration/behavior/monitoring/retirement. (3) **Corrected AUTH/SIGN status semantics** — Phase 5 no longer says "AUTH and SIGN both registered/active" as if identical; it now states AUTH's registration/approval-with-Central-Authority semantics separately from SIGN's valid-and-active-for-the-member-identity/healthy-local-token-state semantics, explicitly stating SIGN does not go through the same separate Central Authority registration-request workflow as AUTH. Phase 11's retirement list now separately covers AUTH certificate retirement/removal (Central Authority action) and SIGN certificate/key retirement/revocation/disablement (member/client-identity token model), explicitly not identical to each other. (4) **Fixed pre-traffic readiness vs. mandatory API validation** — Phase 2 is now explicitly a pre-traffic readiness gate (registration/certificate-token/global-configuration/member-subsystem/client-service/monitoring-prerequisite health), with a real API exchange permitted only optionally, only where a safe isolated/direct test path to NEW exists, never universally mandatory; the mandatory real API validation is now explicitly stated to belong to Phase 5, after NEW is reachable through the member's own controlled traffic mechanism. `READY`'s definition (§2) updated from "Phase 0–2 complete... independently validated" to "Phase 0–3 complete... independently healthy at the pre-traffic readiness level... not yet joined to member traffic," with `GO` redefined as the explicit decision to add NEW to controlled traffic/coexistence. (5) **Generalized rollback (Phase 8)** — no longer says only "Return load-balancer traffic to OLD"; now covers load balancer, application endpoint, or DNS, as applicable, with an explicit statement that DNS/application-endpoint rollback is not implied to behave identically to load-balancer rollback and that the actual mechanism/timing must be captured in that migration's own evidence. (6) **Softened "OLD never modified" wording (Scope)** — no longer states OLD is "never upgraded, modified, or transformed in place" in a way that contradicts the procedure's own later traffic-steering/monitoring/retirement actions against OLD; now states OLD is not upgraded or transformed in place at the X-Road software/configuration level, except for this procedure's own explicitly controlled traffic-steering, monitoring, and retirement actions — the rule against in-place X-Road upgrade itself is preserved, not weakened. (7) **Fixed the phase count** — corrected from "11 phases" to "12 phases, Phase 0 through Phase 11" in this change-history table (see the round 1 entry above, corrected in place). (8) **Preserved unchanged:** the provider-side boundary (member-controlled/LB migration supported by operator-confirmed evidence; direct provider-side peer selection remains `TARGETED VALIDATION REQUIRED IF APPLICABLE`); the approved implementation pattern; NEW's new-Security-Server-Code/new-credentials model; OLD as rollback target remaining operational through observation; mandatory dual monitoring; no package downgrade; no in-place upgrade sequence; the HA/Central-Server/X-Road-8 boundaries; the still-gated production-rollout status; the absence of vendor-specific load-balancer commands and destructive retirement commands. No migration was executed, no production system was modified, and no destructive command was published to produce this round's edits. |
| 2026-09-26 (round 3, this round) | Final sequencing correction, following a HOLD gate on round 2's content — no other section changed. Phase 2's cross-reference to Phase 4/5 was miswritten as Phase 4 being "gated on Phase 5's mandatory validation," which reverses the actual order (Phase 5 follows Phase 4). Corrected to state that Phase 4 makes NEW reachable through the member's controlled traffic-steering mechanism specifically so Phase 5 can perform its mandatory real API validation, and that intentional production traffic cutover occurs only in Phase 7. Phase 4 clarified so that making NEW reachable for validation must not unintentionally shift ordinary member traffic onto NEW before Phase 5's validation succeeds, generalized the member-specific mechanism (controlled/limited routing, canary/test traffic, backend weighting/selection, or another appropriate method) without prescribing a vendor-specific implementation, and restated the phase-sequencing principle explicitly (Phase 4 = controlled reachability for validation; Phase 5 = mandatory API validation; Phase 6 = coexistence/observation; Phase 7 = intentional cutover). No other section was changed. |
| 2026-09-26 (round 4, this round) | Status metadata update only — no procedural content changed. Final review completed; document status changed from `OPERATOR PROCEDURE DRAFT — PENDING FINAL REVIEW` to `APPROVED — FINAL`. The opening status block's "THIS IS A PROCEDURE DRAFT, NOT FINAL OPERATIONAL DOCUMENTATION" line was replaced with "THIS IS THE APPROVED CAMDX 7.8.2 MEMBER SECURITY SERVER MIGRATION PROCEDURE FOR THE PARALLEL REPLACEMENT / BLUE-GREEN IMPLEMENTATION PATTERN," and "This procedure document: DRAFT / PENDING FINAL REVIEW" was replaced with "This procedure document: APPROVED — FINAL." Preserved unchanged: "THIS IS NOT AUTHORIZATION FOR UNCONTROLLED PRODUCTION ROLLOUT," "Member Migration & Release Readiness: NOT STARTED / GATED," and the statement that production rollout of this procedure against any real member is not authorized by this document alone and each migration wave requires its own separate authorization. No migration phase, architecture, sequencing, provider-side boundary, or other operational content was modified. |
