# Architecture

This document is a *reference* — it describes what the gateway is and how requests move through it. Operational setup is in [`.ado/SETUP.md`](../.ado/SETUP.md); ongoing deployment is in [DEPLOYMENT.md](DEPLOYMENT.md); the verified SF integration is in [SALESFORCE-MCP-INTEGRATION-REFERENCE.md](SALESFORCE-MCP-INTEGRATION-REFERENCE.md).

## Purpose

A read-only APIM gateway that brokers an Entra-authenticated identity into a Salesforce Hosted MCP server (`sobject-reads`). The gateway is a **boundary**, not a passthrough — it limits which SObjects, fields, and operations Entra-authenticated callers can see. See the [README "Design Intent"](../README.md#design-intent--limited-exposure-is-the-product) section.

## Deployment Architecture: Dual-Track (INT)

INT environment runs **two parallel MCP endpoints** for comparison and validation:

### Track 1: Generic API (Production)
- **Path**: `/sfdcread/int/mcp`
- **Type**: Generic HTTP API with manual MCP protocol handling
- **Operations**: POST `/mcp` (Streamable HTTP), GET `/health`
- **Policy**: 206-line manual routing with `set-backend-service` + `rewrite-uri`
- **Management**: APIs tab in APIM portal
- **Status**: ✅ Production, all consumers use this

### Track 2: Native MCP Server (Experimental)
- **Path**: `/sfdcread-mcp-native/mcp`
- **Type**: Azure APIM native MCP server resource
- **Operations**: Automatically managed by APIM
- **Policy**: ~150-line simplified (no manual routing)
- **Management**: MCP Servers tab in APIM portal
- **Status**: 🧪 Experimental validation

Both tracks:
- Use same Entra app registration (`42971939-bc78-4c23-963e-c3e0f87e3bd1`)
- Proxy to same Salesforce backend (`api.salesforce.com`)
- Apply same security controls (JWT validation, role check, SF token exchange)

**Why dual-track?** Evaluating whether Azure's native MCP features justify migration:
- Dedicated MCP management UI
- MCP-specific monitoring (operation context, session IDs)
- API Center integration
- Future MCP features (Resources, Prompts, A2A)

See [MCP Native Validation Plan](MCP-NATIVE-VALIDATION.md) for comparison methodology.

## Component map

| Layer | Resource | Source |
|-------|----------|--------|
| Edge (INT) | Azure Front Door route `api.int.amnhealthcare.io/sfdcread/*` | external — managed in `az-amn-tf-enterprise-infra` |
| Gateway | APIM instance `amn-wus2-hub-apim-{d02,i02,p02}` | shared services, not in this repo |
| API | `api-sfdc-read-{env}` at path `sfdcread/{env}` | [`infrastructure/modules/mcp-api/main.tf`](../infrastructure/modules/mcp-api/main.tf) |
| API operations | `GET /health`, `POST /mcp` (SSE/DELETE/legacy operations removed—see note below) | same |
| **MCP Server (native)** | `sfdcread-mcp-native-{env}` at path `sfdcread-mcp-native` | [`infrastructure/modules/mcp-server-native/main.tf`](../infrastructure/modules/mcp-server-native/main.tf) |
| API policy (INT/PROD) | JWT validate → role check → SF OAuth exchange → backend forward | [`policies/apim-policy-sfdc-read-mcp.xml`](../policies/apim-policy-sfdc-read-mcp.xml) |
| API policy (Dev) | JWT validate → role check → inline mock responses | [`policies/apim-policy-sfdc-read-mcp-dev-mock.xml`](../policies/apim-policy-sfdc-read-mcp-dev-mock.xml) |
| Health-check policy | No auth, returns `{status:"healthy", ...}` | [`policies/apim-policy-health-check.xml`](../policies/apim-policy-health-check.xml) |
| Named Values | App ID, SF token URL, MCP path, MCP base URL, SF client_id/secret | [`infrastructure/modules/named-values/`](../infrastructure/modules/named-values/) wired from [`main.tf:16-72`](../infrastructure/main.tf) |
| Backend | `backend-sfdc-read-{env}` pointing at SF (`https://api.salesforce.com`) or mock | [`infrastructure/modules/backend-pool/main.tf`](../infrastructure/modules/backend-pool/main.tf) |
| OAuth2 auth server | `sfdc-read-mcp-{env}-entra` — used for OpenAPI export only (Power Automate / Copilot Studio metadata) | [`infrastructure/modules/oauth2-auth-server/main.tf`](../infrastructure/modules/oauth2-auth-server/main.tf) |
| Identity | Entra app reg per env (e.g. INT = `SFDCRead INT MCP`, `42971939-bc78-4c23-963e-c3e0f87e3bd1`) | provisioned by [`temp/Setup-SingleAppReg-Mcp.ps1`](../temp/Setup-SingleAppReg-Mcp.ps1); identity surface documented in [`docs/onboarding/IDENTITY-BOOTSTRAP-INT.md`](onboarding/IDENTITY-BOOTSTRAP-INT.md) |
| Access group | `AZ_AMN_AAD_SfdcReadMcp_{Env}_User` — grants `MCP.Read` app role | AD-synced into Entra |
| Key Vault | `amn-wus2-sfdcread-kv-i01` (INT) — holds `sfdc-client-id`, `sfdc-client-secret` | provisioned out of band; KV refs are wired into Named Values per [`main.tf:50-58`](../infrastructure/main.tf) |
| Salesforce identity | External Client App in the SF org with `mcp_api` scope | provisioned in Salesforce; see [SALESFORCE-SETUP.md](SALESFORCE-SETUP.md) |

## Trust boundaries

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Caller trust boundary                                                   │
│  Power BI / Copilot Studio / Power Automate / smoke-test harness         │
│  → must hold a valid Entra JWT with MCP.Read role for the per-env app    │
└──────────────────────────────────────────────────────────────────────────┘
                                  │  Entra JWT
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  APIM trust boundary                                                     │
│  - validate-azure-ad-token (tenant + audience)                           │
│  - role check (MCP.Read)                                                 │
│  - method whitelist (initialize, tools/list, tools/call, notif/init)     │
│  - audit identity headers (x-apim-user-id, x-correlation-id)             │
│  - rate limit / quotas (via APIM product, not this repo)                 │
└──────────────────────────────────────────────────────────────────────────┘
                                  │  SF Bearer (client_credentials)
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Salesforce trust boundary                                               │
│  - Run-As user identity (External Client App principal)                  │
│  - Permission set MCP_ReadOnly_Access defines SObject surface            │
│  - FLS trims fields within visible SObjects                              │
│  - Sharing rules apply                                                   │
│  - sobject-reads server type = no mutation paths                         │
└──────────────────────────────────────────────────────────────────────────┘
```

The Entra caller identity does **not** propagate into Salesforce — every SF request runs as the External Client App's Run-As user. APIM forwards the caller's `oid` claim in `x-apim-user-id` purely as an audit trail; SF does not consume it.

## Request flow (INT/PROD)

1. **Client** acquires Entra JWT for `api://<env-app-id>/user_impersonation` (or `api://<env-app-id>/.default` for service-to-service). The JWT carries the `MCP.Read` role claim if the caller is in the env's access group.
2. **AFD** routes `/sfdcread/*` to the APIM instance.
3. **APIM inbound policy** ([`apim-policy-sfdc-read-mcp.xml`](../policies/apim-policy-sfdc-read-mcp.xml)) runs in order:
   - `validate-azure-ad-token` — tenant + audience (`api://<app-id>` OR bare `<app-id>`). Mismatch → 401.
   - Role check — `roles` claim must contain `MCP.Read`. Missing → 403.
   - `x-apim-user-id` set from `oid` claim; `x-correlation-id` generated if absent.
   - Method whitelist — only `initialize`, `tools/list`, `tools/call`, `notifications/initialized` are forwarded. Others → JSON-RPC `-32601` ("Method not found") in a 200 wrapper.
   - SF token lookup — `cache-lookup-value` keyed on `sfdc-mcp-token-<clientId>` (30 min TTL).
   - SF token exchange (on cache miss) — POST to `<sfdc_token_url>` with `grant_type=client_credentials&client_id=...&client_secret=...`. Failure → JSON-RPC `-32603` ("Internal error") in a 200 wrapper.
   - `set-backend-service` → `<sfdc_mcp_base_url><sfdc_mcp_path>` (e.g. `https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads`).
   - `rewrite-uri template="/"` — strips the operation's `url_template` segment so APIM does not append `/mcp` onto the SF base URL (SF returns 404 otherwise). Verified working calls in [SALESFORCE-MCP-INTEGRATION-REFERENCE.md](SALESFORCE-MCP-INTEGRATION-REFERENCE.md).
   - `Authorization` header is replaced with the SF Bearer token (caller's Entra JWT is dropped).
4. **Salesforce MCP server** processes the JSON-RPC request under the Run-As user identity and returns the response.
5. **APIM outbound** — `<base />`; no transformations.
6. **on-error** — any unhandled exception is wrapped as JSON-RPC `-32603` with the correlation ID in `data`, returned as 200 (matches MCP transport expectations).

## Dev environment difference

Dev does not exchange SF tokens and does not call out to any backend. The policy ([`apim-policy-sfdc-read-mcp-dev-mock.xml`](../policies/apim-policy-sfdc-read-mcp-dev-mock.xml)) still validates the JWT and the `MCP.Read` role, but returns inline mock responses for `initialize` / `tools/list` / `tools/call`. The dev app reg is `6ce6ccb1-32db-40f8-97b5-bfbe700d052e` (`SFDC Read MCP Reader Dev`) per [`dev.tfvars`](../infrastructure/environments/dev.tfvars).

Dev is useful for verifying the JWT/role wiring and protocol shape without standing up a Salesforce backend, but it cannot validate the OAuth exchange or the SF routing — those only run end-to-end against INT.

## Generic API Simplification (2026-07)

Removed obsolete operations from the generic API (commented out in Terraform for easy rollback):

| Operation | Why Removed | Rollback |
|-----------|-------------|----------|
| GET `/mcp` | SSE transport deprecated as of MCP `2024-11-05` | Uncomment in `mcp-api/main.tf` |
| DELETE `/mcp` | Session cleanup rarely used by clients | Uncomment in `mcp-api/main.tf` |
| POST `/` | Legacy endpoint with no known consumers | Uncomment in `mcp-api/main.tf` |

**Kept**:
- POST `/mcp` - The only operation used by consumers (Streamable HTTP)
- GET `/health` - AFD liveness probe

All MCP traffic (initialize, tools/list, tools/call, notifications/initialized) flows through the single POST `/mcp` endpoint. The JSON-RPC `method` field in the request body determines routing.

## Method whitelist

The APIM policy explicitly allows only four MCP methods. The whitelist is in the policy, not in Terraform — additions require a policy change and redeploy.

| Method | Behavior |
|--------|----------|
| `initialize` | Forwarded to SF |
| `tools/list` | Forwarded to SF |
| `tools/call` | Forwarded to SF |
| `notifications/initialized` | APIM returns 202 directly (no SF round-trip) |
| anything else | APIM returns 200 + JSON-RPC `-32601` ("Method not found") |

This is a defense-in-depth control: the Salesforce `sobject-reads` server type already prevents mutation, but the gateway will not even forward an unknown method.

## Audit trail

Every request carries two headers post-policy:

- `x-apim-user-id` — the Entra caller's `oid` claim (their object ID in the tenant)
- `x-correlation-id` — passed through if the client sent one, otherwise generated

Both are echoed in error envelopes. APIM diagnostic logs (configured at the APIM service level, not in this repo) capture these for cross-system tracing.

## What this repo does not own

- The APIM instances themselves (`amn-wus2-hub-apim-{d02,i02,p02}`) — shared services
- AFD routes — `az-amn-tf-enterprise-infra`
- Key Vault provisioning — out of band; this repo only reads via APIM Named Value KV references
- The Salesforce External Client App and the `MCP_ReadOnly_Access` permission set — Salesforce-side; see [SALESFORCE-SETUP.md](SALESFORCE-SETUP.md)
- The Entra app registrations and access groups — provisioned by [`temp/Setup-SingleAppReg-Mcp.ps1`](../temp/Setup-SingleAppReg-Mcp.ps1) (script lives outside VCS; identity surface documented in [`docs/onboarding/IDENTITY-BOOTSTRAP-INT.md`](onboarding/IDENTITY-BOOTSTRAP-INT.md))

## Per-environment matrix

| | Dev | Int | Prod |
|---|-----|-----|------|
| APIM | `amn-wus2-hub-apim-d02` | `amn-wus2-hub-apim-i02` | `amn-wus2-hub-apim-p02` (TBD) |
| Backend | `http://localhost:8080` (mock) | `https://api.salesforce.com` | `https://api.salesforce.com` |
| MCP path | `/platform/mcp/v1/platform/sobject-reads` | `/platform/mcp/v1/sandbox/platform/sobject-reads` | `/platform/mcp/v1/platform/sobject-reads` |
| SF org | mock | `amnhealthcare--qa.sandbox.my.salesforce.com` | `amnhealthcare.my.salesforce.com` (TBD) |
| Policy | mock variant | full variant | full variant |
| Key Vault | none (inline mock creds) | `amn-wus2-sfdcread-kv-i01` | `amn-wus2-sfdcread-kv-p01` (TBD) |
| Entra app | `6ce6ccb1-...` (`SFDC Read MCP Reader Dev`) | `42971939-...` (`SFDCRead INT MCP`) | TBD (`SFDCRead PROD MCP`) |
| Access group | `AZ_AMN_AAD_SfdcReadMcp_Dev_User` | `AZ_AMN_AAD_SfdcReadMcp_Int_User` | `AZ_AMN_AAD_SfdcReadMcp_Prod_User` |

Source of truth for these constants is [`infrastructure/environments/{dev,int,prod}.tfvars`](../infrastructure/environments/) — this table is a summary, not authoritative.
