# Salesforce MCP Integration: Working Calls Reference

**Last verified:** 2026-06-09
**Org:** `amnhealthcare--qa.sandbox.my.salesforce.com` (QA sandbox)
**Status:** Token + MCP both confirmed working end-to-end via `client_credentials`.

This is the canonical record of the request/response shapes that work against Salesforce's hosted MCP server through APIM. Cited from `policies/apim-policy-sfdc-read-mcp.xml` as the source of the `rewrite-uri template="/"` rule.

---

## 1. Token exchange (client_credentials)

```
POST https://amnhealthcare--qa.sandbox.my.salesforce.com/services/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<SFDC-MCP-Client-ID from Key Vault>
&client_secret=<SFDC-MCP-Client-Secret from Key Vault>
```

**Response (200):**

```json
{
  "access_token": "00DVC00000A0rRZ!...",
  "scope": "sfap_api mcp_api api",
  "instance_url": "https://amnhealthcare--qa.sandbox.my.salesforce.com",
  "api_instance_url": "https://api.salesforce.com",
  "token_type": "Bearer"
}
```

Note the **new fields**:
- `scope` now includes `mcp_api` (was just `sfap_api api` on 2026-06-08).
- `api_instance_url=https://api.salesforce.com` — this is the MCP backend, distinct from the org's `instance_url`.

---

## 2. MCP `initialize`

```
POST https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads
Authorization: Bearer <access_token from step 1>
Accept: application/json, text/event-stream
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-03-26",
    "capabilities": {},
    "clientInfo": { "name": "smoke-test", "version": "1.0" }
  }
}
```

Returns **200** with the standard MCP initialize result. The path includes `/sandbox/` because this is the QA sandbox org; prod uses `/platform/mcp/v1/platform/sobject-reads`.

---

## 3. MCP `tools/list`

Same URL/headers as step 2. Returns 6 tools:

| Tool | Purpose |
|------|---------|
| `getRelatedRecords` | Fetch records related to a parent SObject |
| `listRecentSobjectRecords` | Recently viewed records for an SObject |
| `soqlQuery` | Execute a SOQL query |
| `find` | Cross-object search |
| `getUserInfo` | Identity of the Run-As user |
| `getObjectSchema` | Describe SObject metadata |

---

## 4. MCP `tools/call` examples

### `getUserInfo` — confirms Run-As identity

Returns the username, user ID, and org ID of the Run-As user (`copilotstudio@amnhealthcare.com.qa`). No params required. Useful as a liveness probe.

### `soqlQuery` — reaches Salesforce

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "soqlQuery",
    "arguments": { "query": "SELECT Id, Name FROM Account LIMIT 5" }
  }
}
```

Currently returns `INVALID_TYPE: sObject type 'Account' is not supported` — this is **not a wiring issue**; the Run-As user's permission set (`MCP_ReadOnly_Access`) doesn't grant Account read. See "Open Items" below.

---

## 5. Routing through APIM

End-to-end flow (verified working as of 2026-06-09):

```
Client (Copilot Studio / Power BI / pwsh test harness)
  → Entra-issued JWT (audience api://<SFDC-Read-MCP-App-ID>)
  → AFD: api.int.amnhealthcare.io/sfdcread/int
  → APIM: amn-wus2-hub-apim-i02
      • validates Entra JWT
      • exchanges KV-backed client_id/secret for SF token (step 1)
      • routes to api.salesforce.com + SFDC-MCP-Path (steps 2–4)
      • replaces inbound Entra JWT with SF Bearer token
  → Salesforce MCP (api.salesforce.com)
```

Smoke test: `pwsh test-harness/Invoke-ApimSmokeTest.ps1 -Environment int`.

---

## Open Items (SF-side)

1. **Permission set tuning** — `MCP_ReadOnly_Access` does not currently grant `Account` (and likely other in-scope SObjects). SF admin needs to add the required SObjects to the perm set for `soqlQuery` / `find` / `getObjectSchema` to return data. Until then, those tools return `INVALID_TYPE`.

2. **MCP key vault cleanup** — the cert `sfdc-jwt-signing` on `amn-wus2-sfdcread-kv-i01` (uploaded for the abandoned JWT Bearer pivot) is now unused and can be decommissioned.

---

## Key references

- [BOUNDARY-EVIDENCE-ACCOUNT-EXCLUDED.md](BOUNDARY-EVIDENCE-ACCOUNT-EXCLUDED.md) — evidence that the Account-excluded boundary holds; complements this doc's "Open Items" #1
- `policies/apim-policy-sfdc-read-mcp.xml` — the APIM policy that cites this file
- Salesforce hosted MCP docs: https://developer.salesforce.com/docs/platform/hosted-mcp-servers/guide/
