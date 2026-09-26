# CamDX API Provider Connectivity Registry (Interim)

**Status: DRAFT — structure established; 4 connectivity profiles populated with operator-confirmed endpoint data (e-KYC Production, e-KYB Development, e-KYB Production, OCR Production). Provider (Service/Data Provider) identity confirmed only for e-KYC (MoI); pending for e-KYB and OCR.**

```text
Applies to: CamDX consumer members needing an API provider's Security Server endpoint
Scope: Provider-specific, externally reachable connectivity profiles
Authority: Interim registry — superseded by the CamDX API Catalog once available
Last reviewed: 2026-09-24
```

## 1. Purpose

This is an **interim, consumer-facing registry** of API Provider Security Server connectivity information, intended to be used until the CamDX API Catalog becomes the authoritative source for this data. It exists because, at the time this document was created, no existing authoritative provider endpoint registry for CamDX APIs (including e-KYC and e-KYB) was found in this repository.

This document does **not** own CamDX infrastructure connectivity (Central Server, Management Security Server, TSA, OCSP, Central Monitoring, generic Security-Server-to-Security-Server rules, or administrative/firewall/DNS guidance) — that is owned by [`network-requirements.md`](./network-requirements.md). This document owns only **provider-specific**, externally reachable endpoint information.

## 2. Data model

### 2.1 Provider connectivity profile

One connectivity profile describes **one provider's externally reachable Security Server endpoint** (which may be a direct Security Server address, or a VIP/load-balancer address in front of a Security Server or Security Server cluster, depending on the provider's own architecture). Each profile is intended to be referenced by **one or more APIs**, rather than duplicating the same endpoint information per API:

```
ONE PROVIDER CONNECTIVITY PROFILE → MANY APIs
```

| Field | Description |
|---|---|
| `profile_id` | A stable, unique identifier for this connectivity profile (e.g. `moi-ekyc-prod-01`), used so APIs can reference it without repeating endpoint data |
| `service_data_provider` | The authoritative data/service provider — see §2.2/§3 for the ownership rule. This is the only field that may be shown to consumers as "the Provider" |
| `technical_operator` | The organization operating the technical service implementation, if different from `service_data_provider` — optional, only populated when evidenced |
| `integration_operator` | The organization operating CamDX-side integration/orchestration components, if applicable — optional, only populated when evidenced |
| `camdx_member` | The X-Road member identity under which the service is registered |
| `subsystem` | The specific X-Road subsystem exposing the service |
| `hosting_infrastructure_operator` | The organization hosting the underlying infrastructure, if different from the above — optional, only populated when evidenced |
| `environment` | Development / Production |
| `endpoint_type` | Security Server / VIP / Load Balancer / Approved public FQDN — whichever the provider has designated as its consumer-facing entry point |
| `fqdn` | The endpoint's FQDN, if one is used and confirmed — never invented |
| `public_ips[]` | All currently authorized public IP address(es) for this endpoint — a single union list, consistent with the address-list model in [`network-requirements.md`](./network-requirements.md) §1 (no "current vs. transition" classification; every listed address is simply authorized until a specific removal notice is issued) |
| `protocol` | Typically the standard X-Road Security-Server-to-Security-Server protocol over TCP |
| `ports[]` | Typically `5500`, `5577` per [`network-requirements.md`](./network-requirements.md) §4/§6, unless the provider's architecture differs |
| `source_ip_registration_required` | Yes / No — see §5 |
| `effective_from` | Date this profile became operationally valid, if known |
| `retirement` | Retirement/deprecation date or notice reference for this specific profile, if any has been issued — never invented (no retirement may be asserted without an explicit CamDX/provider notice) |
| `status` | e.g. Active / Pending / Deprecated |
| `last_verified` | Date this specific profile was last operationally confirmed |
| `verified_by` | Who/what performed the last verification (role or team, not a personal credential) |
| `notes` | Free-text clarification, e.g. architecture caveats or pending-confirmation detail |
| `apis[]` | List of API names/service identifiers that use this connectivity profile |

This schema intentionally separates `service_data_provider` from `technical_operator`/`integration_operator`/`hosting_infrastructure_operator` — see §2.2 for why, and §3 for the concrete e-KYC example. Any field without confirmed evidence is recorded as `Pending authoritative confirmation` rather than left implicitly blank or guessed.

### 2.2 Role separation

Provider identity must reflect the **authoritative data/service provider**, not necessarily whichever organization operates supporting CamDX integration, gateway, orchestration, or infrastructure components around a given service. Where these roles differ, they should be recorded as **separate, distinct fields** rather than collapsed into a single "Provider" value:

| Role | Meaning |
|---|---|
| Service/Data Provider | The organization that owns/is authoritative for the underlying data or service (e.g. a government ministry) |
| Technical Operator | The organization operating the technical service implementation, if different from the Service/Data Provider |
| Integration Operator | The organization operating CamDX-side integration/orchestration components, if applicable |
| CamDX Member | The X-Road member identity under which the service is registered |
| Subsystem | The specific X-Road subsystem exposing the service |
| Hosting/Infrastructure Operator | The organization hosting the underlying infrastructure, if different from the above |

**Example — e-KYC:** the Service/Data Provider is the **Ministry of Interior (MoI)**. CamDX/TSC may operate supporting integration, processing, infrastructure, or coordination components around the service, but that does **not** make TSC the Provider for this field — TSC's role, if any, belongs in a separate Technical Operator / Integration Operator field, not in place of the Provider field.

## 3. Provider ownership rule

Provider identity must reflect the authoritative data/service provider, not the organization operating CamDX infrastructure, integration components, gateways, orchestration, or supporting technical services.

For e-KYC specifically:

```
Provider = Ministry of Interior (MoI)
```

**Do not** assign `Provider = TSC` for e-KYC merely because TSC/CamDX may operate supporting integration, processing, infrastructure, or coordination components around the service.

## 4. Registered connectivity profiles

Operational connectivity for four API/environment profiles has now been confirmed by the operator and is populated below. Every field not explicitly confirmed remains `Pending authoritative confirmation` — no role, endpoint type, FQDN, or shared-profile relationship is inferred from the confirmed IPs/ports alone.

| `profile_id` | `service_data_provider` | `environment` | `endpoint_type` / `fqdn` | `public_ips[]` | `protocol` | `ports[]` | `source_ip_registration_required` | `status` | `last_verified` | `verified_by` | `apis[]` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ekyc-prod-01` | Ministry of Interior (MoI) | Production | *Pending authoritative confirmation* | `103.118.45.170`, `110.74.196.74` | TCP | `5500`, `5577` | *Pending authoritative confirmation* | Active | 2026-09-24 | CamDX operator | e-KYC |
| `ekyb-dev-01` | *Pending authoritative confirmation* | Development | *Pending authoritative confirmation* | `103.118.47.129` | TCP | `5500`, `5577` | *Pending authoritative confirmation* | Active | 2026-09-24 | CamDX operator | e-KYB |
| `ekyb-prod-01` | *Pending authoritative confirmation* | Production | *Pending authoritative confirmation* | `103.118.45.171`, `110.74.196.67` | TCP | `5500`, `5577` | *Pending authoritative confirmation* | Active | 2026-09-24 | CamDX operator | e-KYB |
| `ocr-prod-01` | *Pending authoritative confirmation* | Production | *Pending authoritative confirmation* | `103.118.45.171`, `110.74.196.67` | TCP | `5500`, `5577` | *Pending authoritative confirmation* | Active | 2026-09-24 | CamDX operator | OCR |

**What is confirmed vs. still pending, per row:**

- **`ekyc-prod-01`:** `service_data_provider` (Ministry of Interior (MoI)), `environment`, `public_ips[]`, `protocol`, and `ports[]` are confirmed. `technical_operator`, `integration_operator`, `camdx_member`, `subsystem`, `hosting_infrastructure_operator`, and `source_ip_registration_required` remain unconfirmed and are **not** inferred from the Service/Data Provider or from the endpoint IPs.
- **`ekyb-dev-01`, `ekyb-prod-01`, `ocr-prod-01`:** `environment`, `public_ips[]`, `protocol`, and `ports[]` are confirmed. **`service_data_provider` is explicitly `Pending authoritative confirmation` for all three** — the supplied evidence identifies the endpoint but not the authoritative data/service-provider organization behind e-KYB or OCR. Do **not** assume OCR or e-KYB share e-KYC's provider (MoI), or any other provider, without separate confirmation. `technical_operator`, `integration_operator`, `camdx_member`, `subsystem`, and `hosting_infrastructure_operator` remain unconfirmed for all three.
- No `endpoint_type` (Security Server / VIP / Load Balancer / FQDN) has been confirmed for any of the four rows — the supplied evidence gives IP addresses only, not the endpoint's architectural type. Left `Pending authoritative confirmation` rather than assumed.
- No Development-environment evidence exists yet for e-KYC or OCR — **not invented**. Only the four rows above are populated; any other API/environment combination remains entirely unlisted.

**Shared-endpoint caution (`ekyb-prod-01` and `ocr-prod-01`):** these two profiles currently share the identical confirmed Production public IPs and ports (`103.118.45.171`, `110.74.196.67`, TCP `5500`/`5577`). This coincidence is recorded as observed fact, but is **not** treated as evidence that OCR and e-KYB share a `service_data_provider`, `technical_operator`, CamDX member, subsystem, backend application, or data authority — both attributes remain independently `Pending authoritative confirmation` for each. Per the one-profile-to-many-APIs model (§2.1), these are kept as **two separate profile rows** rather than consolidated into one shared profile referencing both APIs, because no evidence confirms the endpoint is *intentionally* one shared provider-facing Security Server/VIP rather than two independently-provisioned endpoints that currently happen to resolve to the same addresses. Consolidate only if/when evidence confirms the shared-profile intent.

**Dual-role IP caution (`ekyc-prod-01`):** the addresses `103.118.45.170` and `110.74.196.74` also appear in [`network-requirements.md`](./network-requirements.md)'s CamDX Central Server infrastructure connectivity table (Production Central Server / Timestamping / OCSP). This is a legitimate, separate meaning — the same physical CamDX production IPs can host multiple distinct logical services. In **this** document, `103.118.45.170`/`110.74.196.74` specifically mean the **e-KYC API provider-facing Security Server endpoint, TCP `5500`/`5577`** — a different role, port set, and purpose than their CamDX-infrastructure entries in `network-requirements.md`. The two documents' entries for these addresses are not merged and should not be read as duplicating or contradicting each other; `network-requirements.md` itself was **not** modified as part of adding this provider-connectivity data.

**e-KYC, e-KYB, and OCR Development-environment profiles beyond `ekyb-dev-01` are intentionally NOT listed** — no evidence was supplied for an e-KYC Development or OCR Development endpoint, and none is invented here.

## 5. Provider-side source-IP whitelisting

Some providers require the consumer's Security Server public egress IP to be registered/whitelisted before access is granted. This is tracked per connectivity profile via the **Source-IP registration required: Yes / No** field (§2.1).

- If **Yes**, the consumer must supply their Security Server's public egress IP through the relevant provider/API onboarding process — this document does not itself perform or replace that onboarding workflow.
- Consumer source IPs must **not** be publicly enumerated in this document. The onboarding workflow should associate a specific consumer's source-IP requirement with the relevant provider connectivity profile and API access request internally, not as a public table here.

## 6. Security constraints

Only **consumer-reachable, public, operational endpoints** may be recorded in this document. The following must **never** appear here:

- Private Security Server node IPs
- Internal backend application IPs
- Database IPs
- Private Operational Monitoring addresses
- Replication addresses
- Internal HA cluster node addresses
- Credentials, tokens, or secrets of any kind
- Consumer-specific source IPs, unless explicitly approved for public publication

The recorded public endpoint may be a Security Server, a VIP, a load balancer, or an approved public FQDN, depending on the provider's own architecture — whichever the provider has designated as its consumer-facing entry point.

## 7. Relationship to the CamDX API Catalog

This document is explicitly **interim**. Once the CamDX API Catalog is available and populated as the authoritative source for provider/API connectivity, this document should be updated to point to it (and reduced to a pointer/summary, or retired, depending on the Catalog's final shape) rather than being maintained as a parallel permanent source of truth.

## 8. Change history

| Date | Change |
|---|---|
| 2026-09-24 | Document created as part of the CamDX-Documents 7.8.2 documentation architecture modernization. Structure established; no provider endpoint values populated, since no authoritative source was found for any provider (including e-KYC/e-KYB). Provider = Ministry of Interior (MoI) recorded for e-KYC per explicit operator instruction; no endpoint address recorded pending confirmation. |
| 2026-09-24 | Review pass: profile schema expanded to the full field set (`profile_id`, `service_data_provider`, `technical_operator`, `integration_operator`, `camdx_member`, `subsystem`, `hosting_infrastructure_operator`, `environment`, `endpoint_type`, `fqdn`, `current_public_ips[]`, `transition_public_ips[]`, `protocol`, `ports[]`, `source_ip_registration_required`, `effective_from`, `retirement`, `status`, `last_verified`, `verified_by`, `notes`, `apis[]`), aligning terminology with `network-requirements.md`'s then-current/transition IP model. No new endpoint values were populated; e-KYC remains the only recorded row, still fully pending confirmation beyond `service_data_provider`. |
| 2026-09-24 | Policy correction round (final operator decisions): merged `current_public_ips[]`/`transition_public_ips[]` into a single `public_ips[]` field, consistent with `network-requirements.md`'s adoption of the union-IP model (no current/transition classification anywhere in this document either). Removed the assumed `Production` `environment` value and the assumed default `5500`/`5577` `ports[]` values from the e-KYC row — those were plausible-looking but unconfirmed guesses for this specific endpoint, not authoritative data; both now correctly read "Pending authoritative confirmation" like every other unconfirmed field in that row. |
| 2026-09-24 | Evidence-driven cleanup: reworded the §4 note on omitted `technical_operator`/`integration_operator`/`hosting_infrastructure_operator` fields — the previous phrasing ("no evidence distinguishes any such role from the Service/Data Provider") could be weakly read as implying MoI performs those roles; corrected to state plainly that those roles are simply not yet authoritatively confirmed for this profile, with no inference of any kind about who performs them. |
| 2026-09-24 | Populated 4 connectivity profiles with newly supplied operator-confirmed endpoint data: `ekyc-prod-01` (completes the e-KYC/MoI row with `public_ips[]`, `protocol`, `ports[]`), `ekyb-dev-01`, `ekyb-prod-01` (first-ever e-KYB entries in this document — no prior e-KYB evidence existed here before this round), and `ocr-prod-01` (first OCR entry). `service_data_provider` left `Pending authoritative confirmation` for all three e-KYB/OCR rows — no provider ownership was supplied or inferred for either API. Documented, without merging, that `ekyb-prod-01` and `ocr-prod-01` currently share identical confirmed endpoint values (observed coincidence only, not inferred shared ownership) and that `ekyc-prod-01`'s IPs also appear with a distinct meaning in `network-requirements.md`'s CamDX infrastructure table (not modified). No Development-environment profile was invented for e-KYC or OCR — none was supplied. |
