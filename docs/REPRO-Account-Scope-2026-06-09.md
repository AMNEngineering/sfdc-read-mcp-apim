# Repro: `Account` not accessible via MCP `soqlQuery` — 2026-06-09

## For

Salesforce admin team / sobject-reads MCP server owners.

## Summary

Through the AMN APIM gateway (`https://api.int.amnhealthcare.io/sfdcread/int`) into the hosted `sobject-reads` MCP server at `https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads`:

- `soqlQuery` against **`User`** returns data correctly (control).
- `soqlQuery` against **`Account`** returns `INVALID_TYPE: sObject type 'Account' is not supported`.

Both calls use the **same** OAuth token, **same** Mcp-Session-Id, and **same** Run-As user (`copilotstudio@amnhealthcare.com.qa`). Only the SObject differs.

This isolates the failure: OAuth, wiring, MCP protocol, and routing are all healthy. The error originates from Salesforce after the MCP server forwards the query — consistent with `Account` not being granted on the `MCP_ReadOnly_Access` permission set assigned to the Run-As user.

## Environment

| | Value |
|---|---|
| AMN org | `amnhealthcare--qa` (sandbox) |
| SF base | `https://amnhealthcare--qa.sandbox.my.salesforce.com` |
| MCP server | `https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads` |
| Run-As user | `copilotstudio@amnhealthcare.com.qa` |
| Run-As perm set | `MCP_ReadOnly_Access` |
| OAuth grant | `client_credentials`, scopes `sfap_api mcp_api api` |

## Call 1 — Control (works): `soqlQuery` on `User`

**Request body**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "soqlQuery",
    "arguments": { "q": "SELECT Id, Name, Username FROM User LIMIT 3" }
  }
}
```

**Response (PII redacted)**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [{
      "type": "text",
      "text": "{\"totalSize\":3.0,\"done\":true,\"records\":[{\"attributes\":{\"type\":\"User\",\"url\":\"/services/data/v64.0/sobjects/User/<ID-REDACTED>\"},\"Id\":\"<ID-REDACTED>\",\"Name\":\"<NAME-REDACTED>\",\"Username\":\"<USERNAME-REDACTED>\"}, ... (3 records total)]}"
    }],
    "isError": false,
    "_meta": {
      "salesforce/org_base_url": "https://amnhealthcare--qa.sandbox.my.salesforce.com",
      "salesforce/toolTags": ["query", "soql"]
    }
  }
}
```

`isError: false`, three records returned. Confirms OAuth + Run-As + MCP + REST API are all working.

## Call 2 — Failing case: `soqlQuery` on `Account`

**Request body**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "soqlQuery",
    "arguments": { "q": "SELECT Id, Name FROM Account LIMIT 3" }
  }
}
```

**Response**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [{
      "type": "text",
      "text": "[{\"message\":\"\\nSELECT Id, Name FROM Account LIMIT 3\\n                     ^\\nERROR at Row:1:Column:22\\nsObject type 'Account' is not supported. If you are attempting to use a custom object, be sure to append the '__c' after the entity name. Please reference your WSDL or the describe call for the appropriate names.\",\"errorCode\":\"INVALID_TYPE\"}]"
    }],
    "isError": true,
    "_meta": { "salesforce/toolTags": ["query", "soql"] }
  }
}
```

`isError: true`, `INVALID_TYPE` from the Salesforce REST API. Same diagnostic also reproduces via `getObjectSchema` with `objects=Account`:

```json
{
  "errorCode": "INTERNAL_ERROR",
  "message": "Failed to retrieve object schema from Salesforce API: ; nested exception is: common.exception.ApiQueryException: sObject type 'Account' is not supported."
}
```

## Hypothesis

`Account` is not in the `MCP_ReadOnly_Access` permission set assigned to the Run-As user `copilotstudio@amnhealthcare.com.qa`. Salesforce reports the SObject as "not supported" because, from this user's effective access surface, it isn't visible.

This is independent of the MCP server, of APIM, and of OAuth: the same query would fail in any Salesforce REST client running as this user, because the user has no access to the `Account` SObject.

## Ask

1. **Confirm** whether `Account` is intended to be in scope for the Copilot Studio / Power BI consumers of this gateway.
2. If yes: **add `Account`** (and any other in-scope SObjects — TBD with our data owner) **to `MCP_ReadOnly_Access`** with the field-level masking (FLS) appropriate for those consumers.
3. We'll re-run the smoke test and confirm the WARN clears.

## How to reproduce on your side

Any Salesforce REST tooling logged in as `copilotstudio@amnhealthcare.com.qa` should reproduce the `Account` failure with:

```
GET /services/data/v64.0/query?q=SELECT+Id+FROM+Account+LIMIT+1
```

Expected (current): `INVALID_TYPE`.
Expected (after perm-set update): record(s) returned.

If you'd like the failure reproduced from our side again to capture additional traces (correlation IDs, timestamps), reply and we'll re-run the harness.
