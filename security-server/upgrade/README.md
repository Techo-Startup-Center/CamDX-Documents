# CamDX Security Server — Upgrade / Member Migration Status and Safety

## Status: STATUS/SAFETY DOCUMENT ONLY — NOT AN UPGRADE PROCEDURE

**This document is not an upgrade procedure and is not authorization to migrate any member.** It exists specifically so that the availability of validated CamDX 7.8.2 fresh-install documentation and packages/images is never mistaken for authorization to upgrade an existing, already-deployed CamDX Security Server in place. **Member Migration & Release Readiness remains `NOT STARTED` / `GATED`** — nothing in this document starts it, narrows it, or grants any part of it early.

If you are deploying a **brand-new** Security Server, use the appropriate fresh-install guide directly ([`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md), [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md), or [`../container/deployment.md`](../container/deployment.md)) and stop reading here — this page is not relevant to that path. If you operate an **existing** CamDX Security Server, read §15 before doing anything else.

## 1. Verified estate — do not assume uniformity

CamDX's deployed estate is **not** on one uniform version. The following is the verified operational baseline this document works from — it must not be flattened into "CamDX runs 7.x" or any other single-version simplification:

| Component | Verified version | Notes |
|---|---|---|
| Production Central Server | X-Road **7.3.2** | |
| Observed Security Server generation (one cohort) | X-Road **7.2.2** | Coexists with the 7.3.2 cohort below — not a uniform estate |
| Other observed Security Servers | X-Road **7.3.2** | |
| Current / new-member installation repository | CamDX **7.4.2** | The repository new members are currently onboarded against — itself already a different version from either production Security Server generation above |
| Target modernized Security Server release (this documentation set) | CamDX / X-Road **7.8.2** | Validated for fresh installation only — see §6 |

**The CamDX source `develop` branch contains a separate, pre-release X-Road 8 lineage and must not be treated as a migration source or a production target for this document.** See §11.

Because the estate already spans at least three distinct generations (7.2.2, 7.3.2, 7.4.2) before 7.8.2 is even introduced, any future migration work must account for multiple, materially different starting points — not a single upgrade path.

## 2. Approved 7.8.2 target artifacts

These are the CamDX 7.8.2 artifacts validated and approved for the **fresh-install** deployment paths documented elsewhere in this repository:

| Platform | Artifact |
|---|---|
| Ubuntu 22.04 (Jammy) | `7.8.2-1.ubuntu22.04` |
| Ubuntu 24.04 (Noble) | `7.8.2-1.ubuntu24.04` |
| RHEL 9 | `7.8.2-2.el9` |
| Container | `ghcr.io/techo-startup-center/camdx/security-server`, digest `sha256:95fa519adf660cf6e61a037ba9250dfdb1467ec06d6a292dbfccc09db7d71c0b` |

**The existence and validation of these artifacts does not itself authorize upgrading an existing member.** Fresh-install validation (E2 package validation, CLOSED/PASS/GO) covered exactly that — installing these artifacts onto a clean host. It did not exercise, and does not constitute evidence for, moving an already-running 7.2.2/7.3.2/7.4.2 Security Server to any of these artifacts in place. See [`../../release-notes/7.8.2.md`](../../release-notes/7.8.2.md) for the full validated scope of the package/container work.

## 3. The migration decision — locked, not re-litigated here

CamDX's approved migration architecture (decision `03-A1`, status: Approved) is preserved here verbatim as the standing direction — this document does not revisit, reinterpret, or retroactively modify it:

> CamDX shall migrate to X-Road 7.8.2 through a **gated, coexistence-capable** migration rather than a big-bang upgrade. A clean upstream-derived CamDX 7.8.2 engineering and packaging baseline shall first be established and the Cambodia PKI adaptation validated. The exact upgrade sequence from deployed 7.2.2, 7.3.2, and 7.4.2 systems shall be determined through representative migration rehearsal. The Central Server and CamDX-controlled infrastructure shall migrate before broad member rollout while maintaining compatibility with legacy Security Servers. Member migration shall proceed through representative pilots and risk-based waves. Cryptographic modernization, legacy-repository retirement, and other cleanup shall occur only after estate convergence. Rollback shall use consistent system/database recovery points rather than package downgrade. X-Road 8 shall remain a parallel non-production readiness track.

In plain terms, restated without adding anything beyond the decision above:

- **Gated:** each stage (engineering baseline → PKI validation → Central Server migration → member migration waves) requires its own separate authorization before proceeding to the next. Completing one stage is not authorization for the next.
- **Coexistence-capable:** the design must let 7.2.2/7.3.2/7.4.2 Security Servers keep operating correctly against CamDX infrastructure while other members are moved to 7.8.2 — migration is not an all-at-once cutover.
- **Staged, via representative pilots and risk-based waves:** member migration is planned as a sequence of controlled waves, not a single event. **No wave sizes, wave counts, or dates are defined by this document or by the decision above, and none are invented here.**
- **Rollback uses recovery points, not package downgrade:** an in-place `apt`/`dnf` downgrade is explicitly not the approved rollback mechanism (see §7).
- **X-Road 8 stays separate:** it is not part of this migration track at all (see §11).

**Decision `03-A1` itself does not name a specific implementation pattern** (e.g. parallel replacement vs. in-place transformation) for how a given Security Server moves from its source generation to 7.8.2 — it states the *architecture* the eventual pattern(s) must satisfy (gated, coexistence-capable, staged). **A separate, later decision — `03-A2` (Approved) — selects Parallel Replacement / Blue-Green as the approved implementation pattern that satisfies this architecture, on operator-confirmed operational grounds.** `03-A2` is not part of the `03-A1` text and is not claimed to be; §4 and §5 below describe that pattern in detail.

## 4. Approved member migration implementation pattern — Parallel Replacement / Blue-Green

```text
PARALLEL REPLACEMENT / BLUE-GREEN: APPROVED MEMBER MIGRATION
                                    IMPLEMENTATION PATTERN
                                    (decision 03-A2, decisions.md)

MIGRATION PROCEDURE (parallel-replacement.md): DRAFT / PENDING FINAL
                                                REVIEW

PRODUCTION ROLLOUT: GATED — MEMBER MIGRATION & RELEASE READINESS
                     REMAINS NOT STARTED / GATED
```

**Basis:** operator-confirmed operational experience from existing CamDX DC/DRC multi-Security-Server deployments (which already run under different Security Server Codes without mutual interference) plus a successfully registered, coexisting CamDX 7.8.2 Security Server under a new Security Server Code, with member application traffic exercised through both and load-balancer-mediated traffic steering between them. **This is recorded as operator-confirmed operational evidence, not independently re-executed laboratory validation** — see decision `03-A2` for the full evidence statement.

**Approving this implementation pattern is not the same as authorizing production rollout.** The detailed operator procedure derived from this pattern is [`parallel-replacement.md`](./parallel-replacement.md) — currently a **draft, pending final review**, not yet final operational documentation. Member Migration & Release Readiness (§8) remains `NOT STARTED` / `GATED` regardless of this pattern's approval. The pattern:

1. The existing (OLD) Security Server remains registered and operational throughout.
2. A fresh CamDX 7.8.2 Security Server (NEW) is deployed using an already-approved fresh-install path (§2, §6).
3. NEW is registered using a **new Security Server Code** — reusing or cloning the OLD Security Server Code is **not** required or recommended.
4. The required member/subsystem/service state is configured and registered on NEW according to the normal CamDX registration and initial-configuration process ([`../initial-configuration.md`](../initial-configuration.md)).
5. OLD and NEW coexist during a controlled validation and transition period.
6. NEW is validated before being made primary.
7. Traffic is transitioned using whichever mechanism fits the member's own architecture — potentially a member application endpoint change, a Layer-4 VIP/load-balancer switch, or a DNS change, among others. **No single mechanism is prescribed universally** — see §9.
8. During coexistence, transaction/message-log and Operational Monitoring evidence is collected and monitored from **both** OLD and NEW — see §10.
9. OLD remains operational as the primary rollback target throughout the observation window.
10. Once NEW is formally accepted and OLD is confirmed to no longer carry intended traffic, OLD undergoes **controlled retirement** — see §11's dedicated gate. **The exact deregistration/revocation/decommission command sequence is not published here** — that procedure still requires validation.

## 5. Two migration methods under consideration

**Method A's implementation pattern is approved (decision `03-A2`); its production execution is not.** Method B remains an unapproved alternative requiring its own, separate validation. Neither method is authorized for production use.

| | **Method A — Parallel Replacement / Blue-Green** | **Method B — In-place Upgrade** |
|---|---|---|
| Status | **APPROVED IMPLEMENTATION PATTERN** (decision `03-A2`) — production execution remains `GATED` | **ALTERNATIVE / REQUIRES SEPARATE VALIDATION** |
| Deployment | Clean new 7.8.2 deployment (§4, §6) | Existing host/state transformed to 7.8.2 in place |
| Security Server Code | New code issued to NEW; OLD's code is not reused | Existing code/identity is the transition subject |
| Source generation relevance | Relevant for coexistence, member inventory, operational compatibility, and OLD retirement (§8) — not for a mandatory multi-hop package-upgrade path | Directly determines the required package/config/database/schema transition path — matters directly |
| Coexistence | OLD and NEW coexist during validation/transition | Not applicable in the same sense — the single host transitions in place |
| Cutover | Traffic cutover to NEW, per the member's own architecture (§9) | No equivalent cutover step — the host itself changes |
| Rollback | Traffic cutback to the still-operational OLD (§7, §8 Gate M) | Validated system/database recovery points — not package downgrade (§3, §7) |
| Observability during transition | Dual OLD+NEW log/OPMON observation required (§10) | Not applicable in the same sense |
| Old-server disposition | OLD retired only after acceptance, via a controlled, separately-validated retirement gate (§8 Gate U) | Not applicable — no separate "old server" once transformed |
| Documented as an execution procedure today | **Yes — [`parallel-replacement.md`](./parallel-replacement.md), draft, pending final review** | **No** |

## 6. What is approved today

| Approved | Not approved |
|---|---|
| Ubuntu 7.8.2 fresh installation ([`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md)) | In-place upgrade from 7.2.2 |
| RHEL 9 7.8.2 fresh installation ([`../rhel/standalone-installation.md`](../rhel/standalone-installation.md)) | In-place upgrade from 7.3.2 |
| Container 7.8.2 deployment ([`../container/deployment.md`](../container/deployment.md)) | In-place upgrade from 7.4.2 |
| Canonical initial configuration ([`../initial-configuration.md`](../initial-configuration.md)) | Member production migration (any generation, any wave, any method) |
| Canonical network requirements ([`../network-requirements.md`](../network-requirements.md)) | Automated mass rollout |
| Provider connectivity registry ([`../provider-connectivity.md`](../provider-connectivity.md)) | HA migration |
| Connectivity troubleshooting ([`../troubleshooting/connectivity.md`](../troubleshooting/connectivity.md)) | Production-wide switch of the member estate |
| Frozen release packages/images, exactly as already validated (§2) | Central Server production migration |
| Parallel Replacement / Blue-Green **implementation pattern** (§4, §5 — decision `03-A2`) | Arbitrary/ad hoc downgrade or rollback procedure |
| | Parallel Replacement / Blue-Green **production execution/rollout** (§4, §5 — the pattern is approved; a production wave is not) |
| | In-place upgrade execution (§5, Method B) |

**The approved items above are validated release artifacts, fresh-deployment procedures, or canonical operational documentation. None constitutes validation or authorization of member migration.** Nothing in the left column implies any item in the right column.

## 7. Do not treat a package-manager command as a migration procedure

Even where a package manager can technically move a host between versions, that action alone is **not** a validated CamDX member migration, and this document does not publish it as one. Specifically, this documentation set does **not** provide, and operators must not construct on their own, sequences such as:

- `apt upgrade` / `apt dist-upgrade` against a repurposed repository pointer
- `dnf upgrade` / `dnf downgrade`
- `rpm --force` package replacement
- Scripted package-replacement loops across the `xroad-*` package set
- Direct database schema manipulation as an ad hoc migration step
- Repository-switching sequences (pointing an existing host's package manager at the 7.8.2 repository in place of its current one) presented as a migration action

Upstream X-Road release notes are not, by themselves, converted into an executable CamDX migration path here — CamDX-specific validation (Cambodia PKI adaptation behavior, CamDX branding/configuration carry-over, per-generation database and configuration compatibility) has not been performed for any of these transitions, and this document does not assume upstream's own upgrade notes cover CamDX's actual estate. This applies regardless of migration method (§5) — neither Parallel Replacement nor In-place Upgrade is executed via an ad hoc package-manager sequence under this document.

## 8. Member Migration & Release Readiness — future gates, not a procedure

The following is a **status checklist of what the future Member Migration & Release Readiness track must close** — it is not an execution procedure, and no item below may be marked PASS merely because fresh-install validation (§2, §6) already passed. Fresh-install evidence establishes that the 7.8.2 artifact itself works on a clean host; it establishes nothing about any of the following. Several gates are **migration-method-neutral** and differ materially between Method A (Parallel Replacement) and Method B (In-place Upgrade) — see the method-specific detail after the table.

| # | Gate | What it must establish |
|---|---|---|
| A | Source-version inventory | A complete, confirmed inventory of every actually-deployed version (7.2.2, 7.3.2, 7.4.2, and any other variant found) — not assumed complete from §1 alone |
| B | Migration-pattern validation | Separate validation of (i) the Parallel Replacement / Blue-Green path and (ii) the In-place Upgrade path, only if CamDX chooses to support the latter — see detail below |
| C | Configuration / PKI compatibility | Required member configuration and Cambodia PKI semantics are correctly preserved or re-established on the target Security Server according to the selected migration method — see detail below |
| D | Security Server registration semantics | Migration-method-neutral registration/identity validation — see detail below |
| E | Certificate / token semantics | Migration-method-neutral certificate/token validation — see detail below |
| F | OPMON behavior | Both local OPMON and any approved remote/external OPMON topologies continue to function correctly post-transition |
| G | Message-log behavior | Message-log integrity, retention, and auditability across the transition, including separate OLD and NEW histories where Parallel Replacement is used — see Gate T for dual observability during coexistence |
| H | Database / schema behavior | Migration-method-neutral database/schema validation — see detail below |
| I | Service/process behavior | Correct service/process behavior post-transition, per platform |
| J | Host OS compatibility | Confirmed compatibility of the target OS/platform with each source generation's actual host environment |
| K | Application/API exchange validation | Real API exchange continues to function correctly on the post-transition Security Server |
| L | Coexistence with existing older member versions | A migrated/migrating member continues to interoperate correctly with members still running 7.2.2/7.3.2/7.4.2, consistent with the coexistence-capable design (§3) |
| M | Rollback/recovery procedure | Migration-method-neutral rollback validation — see detail below |
| N | Backup/restore validation | A validated backup/restore procedure specific to the migration transition |
| O | Member communication and maintenance-window model | A defined approach for notifying and coordinating with members undergoing migration |
| P | First-wave go/no-go criteria | Explicit criteria for authorizing the first production migration wave |
| Q | Evidence retention and post-wave acceptance | A defined method for retaining migration evidence and accepting each wave's outcome before proceeding to the next |
| R | Traffic steering / cutover validation | See §9 |
| S | Provider-side coexistence validation | See §10 |
| T | Dual observability (OLD + NEW) requirement | See §10 |
| U | Controlled OLD Security Server retirement | See §11 |

**No wave sizes, dates, or schedules are defined here or implied by this checklist.** No item above is marked PASS by this document.

### Method-specific detail for Gates B, C, D, E, H, and M

**Gate B — Migration-pattern validation:**
- **Parallel Replacement / Blue-Green (Method A):** source versions (7.2.2/7.3.2/7.4.2) remain relevant for coexistence planning, member inventory, operational compatibility, and OLD-server retirement (Gate U) — but the source generation does **not** automatically require a separate multi-hop package-upgrade path merely because the OLD server happens to be 7.2.2, 7.3.2, or 7.4.2, since NEW is a clean 7.8.2 installation, not a transformation of OLD.
- **In-place Upgrade (Method B), only if CamDX chooses to support it:** source-version-specific validation remains necessary and mandatory — the exact package/configuration/database/schema transition path must be separately validated for each source generation.

**Gate C — Configuration / PKI compatibility:**
- **Parallel Replacement:** required member configuration and the Cambodia PKI adaptation are **re-established** on NEW through the normal registration/initial-configuration process ([`../initial-configuration.md`](../initial-configuration.md)), not necessarily copied byte-for-byte from OLD.
- **In-place Upgrade:** existing configuration and PKI state are **preserved or migrated in place** on the same host/identity.
- **Neither method requires byte-for-byte configuration copying** — what must be validated is that the *semantics* (correct member/subsystem identity, correct Cambodia PKI classes and certificate chain behavior, correct CamDX-specific settings) are correct on the target Security Server, however they got there.

**Gate D — Security Server registration semantics:**
- **Parallel Replacement:** validate that (i) OLD remains correctly registered throughout coexistence; (ii) NEW is registered independently, using a **new** Security Server Code (OLD's code is not required to be preserved or reused); (iii) the required member/subsystem associations are correctly established on NEW; (iv) OLD and NEW can coexist without a registration/identity conflict; (v) the exact activation/drain behavior between OLD and NEW is validated before production use.
- **In-place Upgrade:** preserving the existing identity/registration without re-registration may still be a separate, legitimate validation goal specific to this method.

**Gate E — Certificate / token semantics:**
- **Parallel Replacement:** validate that (i) NEW has valid, independently configured authentication/signing/token material per CamDX's normal registration policy; (ii) OLD remains valid and operational during the coexistence/rollback window; (iii) no credential or identity collision is introduced between OLD and NEW; (iv) retirement/revocation behavior for OLD's certificates/token material is defined and validated before decommission. **Copying OLD's private keys, certificates, or token state to NEW is not prescribed** and is not assumed — any such reuse would require separate evidence and approval, which does not currently exist.
- **In-place Upgrade:** continuity of the existing credentials through the transformation remains a separate validation case specific to this method.

**Gate H — Database / schema behavior:**
- **Parallel Replacement:** NEW starts from a clean, validated 7.8.2 installation. Exactly which configuration/business state (if any) must be recreated or transferred from OLD to NEW is a separate item to determine and validate — the old X-Road database is **not** assumed to require migration under this method; any required data/state transfer is validated on its own, not assumed necessary by default.
- **In-place Upgrade:** database/schema migration behavior remains a mandatory, source-version-specific validation item — this gate is not removed for that method, only decoupled from Parallel Replacement.

**Gate M — Rollback/recovery procedure:**
- **Parallel Replacement:** the primary rollback candidate is **traffic cutback to the still-operational OLD Security Server** — via whichever mechanism the member's deployment architecture actually uses (application endpoint, Layer-4 VIP/load balancer, or DNS — see §9). No exact traffic-switch command is prescribed yet.
- **In-place Upgrade:** rollback uses validated system/database recovery points, **not** package downgrade — unchanged from decision `03-A1` (§3), quoted verbatim there and not restated differently here.

## 9. Traffic steering / cutover — validation requirement, not a procedure

A dedicated future validation gate (Gate R, §8) covering how traffic actually moves from OLD to NEW (Method A) once both exist. Member architectures vary, and this document does not prescribe one mechanism universally. Where applicable, validation must cover:

- Consumer-side application-to-Security-Server switching (the member's own information system pointed at a different Security Server address).
- Layer-4 VIP/load-balancer cutover — where an L4 VIP is used, **Layer-4 passthrough behavior is preserved unless a different model is separately validated; TLS termination is not introduced at the load balancer merely as part of a migration.**
- DNS-based cutover — **TTL and caching implications must be validated before prescribing a DNS-based cutover as a mechanism; DNS is not assumed to control every X-Road traffic path** (peer Security-Server-to-Security-Server traffic, for instance, may be addressed independently of a DNS record a consumer application uses).
- Outbound NAT/source-IP behavior during and after cutover.
- Provider-side allowlists that may reference the OLD Security Server's address and require updating for NEW.
- Rollback/cutback behavior — reversing whichever cutover mechanism was used, back to OLD.

**No exact traffic-switch command or configuration is published here.** This is recorded as a validation requirement for the future Member Migration & Release Readiness track, not as guidance an operator can act on today.

## 10. Provider-side coexistence and dual observability — validation requirements

**Provider-side coexistence (Gate S, §8):** for a member that provides services to other CamDX members, the future migration track must determine and validate how production provider traffic actually behaves while the required member/subsystem/service is reachable through **both** OLD and NEW Security Servers during coexistence. **The exact X-Road routing/selection/drain behavior in this situation is not prescribed here** — it must be tested in the CamDX DEV environment before any such behavior is documented as validated. The eventual migration procedure must define how NEW becomes eligible for real traffic, how traffic through both servers is observed, and how OLD is drained safely — but none of that is invented in this status document.

**Dual observability (Gate T, §8):** during the coexistence/observation phase, evidence must be collected and reviewed from **both** Security Servers, at minimum:

- Transaction/message-log evidence
- Operational Monitoring data
- Errors/failures
- API exchange success
- Traffic volume/activity on OLD vs. NEW
- Certificate/OCSP/TSA-related failures where applicable

**"NEW works" is not sufficient justification, by itself, to retire OLD.** Retirement additionally requires establishing that the intended production traffic has actually transitioned to NEW and that OLD is no longer needed for the rollback/observation window — see §11.

## 11. Controlled OLD Security Server retirement — a first-class gate

**Gate U (§8).** Before an OLD Security Server is deregistered or decommissioned under the Parallel Replacement candidate (§4), the future Member Migration & Release Readiness track must establish:

- NEW has been formally accepted.
- The coexistence/observation period has been completed.
- Intended production traffic is confirmed to have transitioned to NEW (§10).
- Final OLD logs/Operational Monitoring evidence have been captured.
- The rollback window has been formally closed.
- Registration/certificate retirement steps for OLD are defined.
- Obsolete DNS/VIP/NAT/firewall/allowlist entries referencing OLD are identified.
- Evidence from the entire transition is retained.

**The exact destructive/deregistration/revocation command sequence is not published here.** That procedure belongs to the future, separately validated member migration procedure — not to this status/safety document.

## 12. High Availability boundary

**HA remains `REQUIRES VERIFICATION`.** The existing Ubuntu/RHEL High Availability documents in this repository are **not** approved 7.8.2 migration procedures. This document does not publish, and operators must not construct, any of the following until HA is separately validated for 7.8.2:

- HA rolling upgrade
- Load-balancer cutover
- Database failover
- Soft-token replication
- `node.ini` migration
- Active/passive switching

## 13. Central Server boundary

**Central Server validation and migration is a separate track from this Security Server upgrade-status page.** The current Central Server sequence (`CS-E1`) exists independently:

- **CS-E1-A:** delegated to Soda, awaiting validation evidence. Not started or completed by this documentation task.

**Nothing in this document authorizes:**

- Central Server production migration
- DNS cutover
- Central Server 7.8.2 production adoption
- Overall CamDX production-rollout closure

Security Server member migration and the Central Server upgrade sequence are not mixed together anywhere in this document — closing one does not imply progress on, or authorization for, the other. Per the locked migration decision (§3), Central Server and CamDX-controlled infrastructure migrate **before** broad member rollout, but that ordering is not itself an authorization for either step — each still requires its own separate gate.

## 14. X-Road 8 boundary

The CamDX source `develop` branch's X-Road 8 lineage (confirmed at `xroadVersion=8.0.0-beta2`, built from NIIS's own pre-release `develop` trunk, with no numbered X-Road release tag as an ancestor) is **separate, pre-release engineering work**. It is explicitly:

- **Not** the current production baseline (§1)
- **Not** the source or target of this 7.8.2 migration track, under either method (§5)
- **Not** the target of the future Member Migration & Release Readiness track described in §8

Per the locked migration decision (§3), X-Road 8 remains a parallel, non-production readiness and compatibility track. Any X-Road 8 assessment work is tracked separately from, and does not inform or accelerate, the 7.2.2/7.3.2/7.4.2 → 7.8.2 migration described in this document.

## 15. Operator action today

- **Deploying a NEW Security Server:** use the approved Ubuntu, RHEL, or container fresh-install guide directly. This is fully supported today.
- **Operating an EXISTING CamDX Security Server:** do **not** independently switch package repositories or attempt to upgrade to 7.8.2 on your own. Wait for an approved CamDX member-migration procedure and your assigned migration wave — neither exists yet.
- **An existing server that is broken/misbehaving today:** use [`../troubleshooting/connectivity.md`](../troubleshooting/connectivity.md) and CamDX's established recovery/escalation channels. Do **not** reinterpret a fresh-install command sequence from this repository as a repair or upgrade procedure for an existing deployment — the fresh-install guides assume a clean host with no prior CamDX state, which does not describe a broken existing server.
- **Migration-direction note:** CamDX has **approved** Parallel Replacement / Blue-Green — deploying a new 7.8.2 Security Server under a **new** Security Server Code, alongside the existing one — as the member migration **implementation pattern** (§4, §5; decision `03-A2`). The detailed operator procedure is [`parallel-replacement.md`](./parallel-replacement.md), currently a **draft, pending final review**. **Approval of the pattern is not authorization for any member to independently build, register, or cut over to a parallel Security Server today.** Wait for the procedure's final review and your assigned migration wave under the still-`NOT STARTED`/`GATED` Member Migration & Release Readiness track.

## 16. Status matrix

```text
Fresh Ubuntu install:                          APPROVED
Fresh RHEL install:                            APPROVED
Fresh container deployment:                    APPROVED
Connectivity troubleshooting:                  APPROVED

Member Migration & Release Readiness:          NOT STARTED / GATED

Member migration 7.2.2 → 7.8.2:                NOT STARTED / GATED
Member migration 7.3.2 → 7.8.2:                NOT STARTED / GATED
Member migration 7.4.2 → 7.8.2:                NOT STARTED / GATED

Parallel replacement / blue-green
member migration implementation pattern
(Method A, decision 03-A2):                     APPROVED

Parallel replacement / blue-green
migration procedure (parallel-replacement.md):  DRAFT / PENDING FINAL REVIEW

Parallel replacement / blue-green
production rollout:                             GATED / NOT AUTHORIZED

In-place member upgrade (Method B):             ALTERNATIVE — REQUIRES SEPARATE VALIDATION

HA migration:                                  REQUIRES VERIFICATION
Central Server production migration:           SEPARATE TRACK / NOT AUTHORIZED
X-Road 8:                                      SEPARATE NON-PRODUCTION TRACK
```

This is a status snapshot, not a schedule — no dates, wave counts, or durations are attached to any row above.

## 17. Cross-references

This document does not duplicate the content of the documents it links to:

- [`../ubuntu/standalone-installation.md`](../ubuntu/standalone-installation.md) — Ubuntu fresh-install procedure
- [`../rhel/standalone-installation.md`](../rhel/standalone-installation.md) — RHEL 9 fresh-install procedure
- [`../container/deployment.md`](../container/deployment.md) — container fresh-deployment procedure
- [`../initial-configuration.md`](../initial-configuration.md) — deployment-independent initial configuration workflow
- [`../network-requirements.md`](../network-requirements.md) — authoritative CamDX infrastructure connectivity matrix
- [`../provider-connectivity.md`](../provider-connectivity.md) — provider-specific endpoint connectivity registry
- [`../troubleshooting/connectivity.md`](../troubleshooting/connectivity.md) — connectivity diagnosis for an existing or newly-deployed Security Server
- [`../../release-notes/7.8.2.md`](../../release-notes/7.8.2.md) — full validated scope of the CamDX 7.8.2 package/container work, and the complete list of open tracks
- [`parallel-replacement.md`](./parallel-replacement.md) — the detailed Parallel Replacement / Blue-Green member migration procedure derived from the pattern approved in §4/§5 (decision `03-A2`); currently a draft, pending final review, not yet final operational documentation

## 18. Change history

| Date | Change |
|---|---|
| 2026-09-24 | Created as part of the CamDX-Documents 7.8.2 documentation architecture modernization, as an explicit status/safety placeholder — no upgrade sequence described or implied. |
| 2026-09-26 (round 1) | Full modernization into the authoritative CamDX 7.8.2 Upgrade / Member Migration Status and Safety document. Recorded the verified heterogeneous estate (Central Server 7.3.2; Security Servers observed at both 7.2.2 and 7.3.2; the 7.4.2 new-member repository; 7.8.2 as the fresh-install target only) without implying uniformity. Recorded the approved 7.8.2 target artifacts (Ubuntu 22.04/24.04, RHEL 9, container digest) and stated explicitly that their validation does not authorize upgrading an existing member. Preserved the locked, approved migration architecture decision (gated, coexistence-capable, staged via representative pilots and risk-based waves, rollback via recovery points not package downgrade, X-Road 8 kept separate) verbatim, without inventing wave sizes or dates. Published an approved-vs-not-approved matrix distinguishing fresh-install artifacts/guides from member migration, mass rollout, HA migration, and Central Server migration. Added an explicit refusal to publish any package-manager-based migration command sequence (`apt`/`dnf upgrade`/`downgrade`, `rpm --force`, repository-switching, schema manipulation) as a migration procedure. Added a 17-item (A–Q) Member Migration & Release Readiness status-gate checklist, explicit that none of it is satisfied by fresh-install validation alone. Added an explicit Central Server boundary (CS-E1-A delegated to Soda, awaiting evidence; this document authorizes no Central Server production migration, DNS cutover, or production-rollout closure) and an explicit HA boundary (HA remains REQUIRES VERIFICATION; no HA rolling-upgrade/failover/cutover procedure published) and an explicit X-Road 8 boundary (the `develop` branch's pre-release X-Road 8 lineage is not a migration source or target). Added a concise operator-facing action section (new deployment → use the fresh-install guides; existing server → wait for an approved migration wave, do not self-upgrade; broken existing server → troubleshoot and escalate, do not reinterpret fresh-install commands as repair). Added a compact status matrix, explicitly not a schedule. |
| 2026-09-26 (round 2, this round) | Targeted migration-model correction, following a HOLD gate on round 1's content. Decision `03-A1` (§3) preserved verbatim, unmodified — a new sentence was added directly after it clarifying that the decision itself does not name an implementation pattern, only the architecture a pattern must satisfy. Added §4, describing the current preferred member migration validation candidate — Parallel Replacement / Blue-Green — as a 10-step candidate model (OLD stays operational; NEW deployed fresh via an approved install path; NEW registered under a **new** Security Server Code, not a reused/cloned OLD code; required member/subsystem state configured on NEW normally; OLD/NEW coexist during validation; NEW validated before becoming primary; traffic transitioned via whichever mechanism fits the member's architecture, not prescribed universally; dual OLD+NEW log/OPMON observation during coexistence; OLD kept as the rollback target; OLD retired only after acceptance, exact retirement commands not published), explicitly labeled PREFERRED VALIDATION CANDIDATE / NOT YET AN APPROVED EXECUTION PROCEDURE / MEMBER MIGRATION REMAINS NOT STARTED / GATED. Added §5, a Method A (Parallel Replacement, preferred candidate) vs. Method B (In-place Upgrade, alternative requiring separate validation) comparison table, neither marked approved. Broadened former Gate B ("upgrade-path validation per source generation") to "migration-pattern validation," split by method, with an explicit statement that Parallel Replacement does not automatically require a multi-hop package-upgrade path merely because the source generation is 7.2.2/7.3.2/7.4.2. Made former Gate D (registration/subsystem persistence) migration-method-neutral: Parallel Replacement validates OLD's continued registration, NEW's independent registration under a new Security Server Code, and coexistence/activation/drain behavior, rather than assuming identity-preserving in-place transition. Made former Gate E (certificate/token behavior) migration-method-neutral: Parallel Replacement validates NEW's independently configured credentials and OLD's continued validity, explicitly without prescribing that OLD's private keys/certificates/token state be copied to NEW. Split former Gate H (database/schema behavior) by method: Parallel Replacement does not assume the old X-Road database must be migrated (NEW starts clean; any required data/state transfer is validated separately); In-place Upgrade retains database/schema migration as a mandatory source-version-specific gate. Split former Gate M (rollback) by method: Parallel Replacement's primary rollback is traffic cutback to OLD (mechanism not prescribed); In-place Upgrade's rollback remains recovery-point-based per the unchanged `03-A1` text. Added new Gate R (traffic steering/cutover validation, §9) covering consumer-application switching, L4 VIP/load-balancer cutover (passthrough preserved unless separately validated otherwise; no TLS termination introduced at the LB as part of migration), DNS-based cutover (TTL/cache implications must be validated first; DNS not assumed to control every X-Road traffic path), outbound NAT/source-IP behavior, provider allowlists, and cutback behavior — no exact command published. Added new Gate S (provider-side coexistence validation, §10) and Gate T (dual OLD+NEW observability requirement, §10) — explicit that "NEW works" alone does not justify retiring OLD, and that provider-side routing/selection/drain behavior during coexistence is not invented here and must be tested in the CamDX DEV environment first. Added new Gate U (controlled OLD Security Server retirement, §11) as a first-class gate with an explicit pre-retirement checklist, and an explicit refusal to publish the exact destructive/deregistration/revocation command sequence. Updated the operator-action section (§15) with an informational-only note that CamDX is evaluating Parallel Replacement with a new Security Server Code as the preferred candidate, explicitly not authorization for independent member action. Updated the status matrix (§16) to add Parallel Replacement (PREFERRED VALIDATION CANDIDATE — NOT YET APPROVED) and In-place Upgrade (ALTERNATIVE — REQUIRES SEPARATE VALIDATION) rows, with all previously-approved/gated rows unchanged and no dates added. Renumbered §4 onward to accommodate the new sections; no previously-approved content was removed or weakened. |
| 2026-09-26 (round 3, this round) | **APPROVED.** Five final non-blocking editorial corrections applied after ChatGPT/operator **APPROVAL** of round 2's content — no architecture reopened: (1) the introduction's cross-reference to the operator-action section corrected from the stale §12 to the current §15. (2) Gate C reworded from "existing member configuration carry forward correctly across the transition" (which implied identity-preserving in-place transition) to migration-method-neutral wording — required configuration/PKI *semantics* are correctly preserved or re-established on the target Security Server according to the selected method, with an explicit method-specific detail entry stating Parallel Replacement re-establishes configuration on NEW via normal registration while In-place Upgrade preserves/migrates it, and neither method requires byte-for-byte copying. (3) Gate G reworded so it no longer implies Parallel Replacement produces one continuous message-log database — now covers integrity/retention/auditability across the transition, including separate OLD and NEW histories under Parallel Replacement, cross-referenced to Gate T's dual observability. (4) The approved/not-approved matrix's closing sentence, which said every approved item "was validated for fresh installation," corrected to distinguish validated release artifacts and fresh-deployment procedures from canonical operational documentation (initial configuration, network requirements, provider connectivity, connectivity troubleshooting), none of which constitutes migration validation or authorization. (5) No stale review-bundle section-number references were found needing correction inside this document itself (that correction applied to the companion review bundle, not to this file). |
| 2026-09-26 (round 4, this round) | **Strategic pattern-approval update, following decision `03-A2` (Approved, `decisions.md`).** Parallel Replacement / Blue-Green changed from a "preferred validation candidate — not yet approved" status to **APPROVED member migration implementation pattern**, on operator-confirmed operational grounds (existing CamDX DC/DRC multi-Security-Server operation under different Security Server Codes without mutual interference, plus a separately registered and coexisting CamDX 7.8.2 Security Server under a new code, with member traffic exercised through both and load-balancer-mediated cutover) — explicitly recorded as operator-confirmed operational evidence, not independently re-executed laboratory validation. §4's status banner, §5's Method A row, §6's approved/not-approved matrix, §15's operator-action note, and §16's status matrix were all updated to distinguish three separate states precisely: the **implementation pattern** (now `APPROVED`), the **migration procedure** at [`parallel-replacement.md`](./parallel-replacement.md) (new document, `DRAFT / PENDING FINAL REVIEW`), and **production rollout** (still `GATED` / `NOT AUTHORIZED` — Member Migration & Release Readiness remains `NOT STARTED`/`GATED`, unchanged). Added a cross-reference to the new procedure document (§17). No previously-approved fresh-install content, no Method B alternative status, no HA/Central-Server/X-Road-8 boundary, and no production-rollout gate was weakened by this round. |
