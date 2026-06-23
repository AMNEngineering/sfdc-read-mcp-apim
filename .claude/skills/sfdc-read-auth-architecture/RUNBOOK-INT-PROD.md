# Runbook: SFDCRead Auth Cutover (Int/Prod)

Scope: operational steps for a single integration identity model while another bot continues core auth-model development.

## Preconditions
- Dedicated read-only Salesforce integration user exists.
- External Client App (or allowed app type) is configured.
- APIM named values can resolve Key Vault secrets in int/prod.
- Change windows approved for int then prod.

## Int (Sandbox) Steps

1. Confirm endpoint and app policy
- Token URL: https://amnhealthcare--qa.sandbox.my.salesforce.com/services/oauth2/token
- Verify which grant types are enabled for the app.

2. Validate token flow candidate
- Execute token request from TOKEN-REQUEST-TEMPLATES.md.
- Capture exact status and error payload.

3. Populate/rotate APIM secrets
- SFDC-MCP-Client-ID
- SFDC-MCP-Client-Secret
- SFDC-MCP-Refresh-Token (if using broker pattern)
- SFDC-MCP-Token-URL
- SFDC-MCP-Base-URL
- SFDC-MCP-Path

4. Apply APIM policy changes
- Use APIM-REFRESH-BROKER-SNIPPETS.xml fragments as needed.
- Keep current caller auth controls unchanged (Entra validation, quotas, rate limits).

5. Execute smoke validation
- Health endpoint check.
- Authenticated tools/list style request through int APIM.
- Confirm no mutation paths are exposed.

6. Record outcome truthfully
- Include exact command used.
- Include observed output/status.
- Mark pass/fail based on real end-to-end run.

## Prod Steps

1. Freeze int artifacts
- Copy tested policy and named-value map.
- Confirm no unresolved TODOs from int.

2. Confirm prod endpoint and policy
- Token URL: https://<prod-my-domain>.my.salesforce.com/services/oauth2/token
- Re-validate allowed grant types (do not assume int parity).

3. Deploy policy + secrets
- Apply same pattern verified in int.
- Ensure prod Key Vault references are correct.

4. Run post-deploy checks
- Health endpoint check.
- Authenticated MCP request through prod APIM.
- Verify expected read-only behavior.

5. Rollback trigger points
- Any 401/403 increase on valid traffic.
- Any token acquisition failures.
- Any evidence of over-privileged access.

## Operational Commands (template)

```bash
# Token test
curl -sS -X POST "$SF_TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=refresh_token" \
  --data-urlencode "client_id=$SF_CLIENT_ID" \
  --data-urlencode "client_secret=$SF_CLIENT_SECRET" \
  --data-urlencode "refresh_token=$SF_REFRESH_TOKEN"

# APIM health
curl -sS "https://api.int.amnhealthcare.io/sfdcread/int/health"
```

## Handoff Checklist for Parallel Bot
- Share exact grant-type test result per environment.
- Share final named value keys used.
- Share APIM policy fragment IDs changed.
- Share one successful end-to-end command/output per environment.
