# Boundary-Enforcement Evidence: `Account` is correctly excluded — 2026-06-09

## Purpose

This doc records evidence that the **scope boundary works as designed**: the Run-As user `copilotstudio@amnhealthcare.com.qa` cannot read the `Account` SObject through the SFDCRead MCP gateway. Account is intentionally **out of scope** for this endpoint — the consuming use cases (Copilot Studio, Power BI) do not require it.

This is **not** a request to widen access. It is GRC/audit-friendly proof that the wrapper does what it claims: limits Entra users to a curated, narrow read surface.

## Why this matters

The whole reason this gateway exists is to expose a constrained read surface, not to mirror the full Salesforce org. A test result that shows `Account` is queryable through this endpoint would be a security regression — not a feature. See [README "Design Intent — Limited Exposure is the Product"](../README.md#design-intent--limited-exposure-is-the-product).

## Environment

| | Value |
|---|---|
| AMN org | `amnhealthcare--qa` (sandbox) |
| SF base | `https://amnhealthcare--qa.sandbox.my.salesforce.com` |
| MCP server | `https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads` |
| Run-As user | `copilotstudio@amnhealthcare.com.qa` |
| Run-As perm set | `MCP_ReadOnly_Access` (does **not** include Account, by design) |
| OAuth grant | `client_credentials`, scopes `sfap_api mcp_api api` |

## Evidence: same token + session, different SObjects

### Call A — In-scope SObject (control): `soqlQuery` on `User` → succeeds

```json
Request:  { "name":"soqlQuery", "arguments":{ "q":"SELECT Id, Name, Username FROM User LIMIT 3" } }
Response: { "isError": false, "result": { ... 3 records ... } }
```

This confirms OAuth, the Run-As mapping, the MCP protocol layer, and Salesforce REST API access are all healthy. Data flows when the SObject is in scope.

### Call B — Out-of-scope SObject (boundary): `soqlQuery` on `Account` → blocked

```json
Request:  { "name":"soqlQuery", "arguments":{ "q":"SELECT Id, Name FROM Account LIMIT 3" } }
Response: {
  "isError": true,
  "result": {
    "content": [{
      "type": "text",
      "text": "[{\"message\":\"... sObject type 'Account' is not supported ...\",\"errorCode\":\"INVALID_TYPE\"}]"
    }]
  }
}
```

`INVALID_TYPE` is Salesforce's standard response when the calling identity has no access to an SObject. From this user's perspective, `Account` does not exist — which is exactly the desired posture.

### Call C — Same boundary through a different tool: `getObjectSchema(objects=Account)` → blocked

```json
Response: {
  "isError": true,
  "errorCode": "INTERNAL_ERROR",
  "message": "Failed to retrieve object schema from Salesforce API: ; nested exception is: common.exception.ApiQueryException: sObject type 'Account' is not supported."
}
```

The boundary is enforced consistently — schema discovery is blocked the same way as data access.

## Conclusion

Both `Account`-targeted calls (`soqlQuery` and `getObjectSchema`) are correctly blocked by the Run-As user's permission set. The wrapper's narrow-surface guarantee holds.

## Regression test

The smoke test (`test-harness/Invoke-ApimSmokeTest.ps1`) treats these calls as **boundary assertions**: they PASS when the expected `INVALID_TYPE` / `INTERNAL_ERROR` is returned, and FAIL if `Account` ever becomes accessible. Any future widening of `MCP_ReadOnly_Access` that exposes `Account` will be caught in CI.
