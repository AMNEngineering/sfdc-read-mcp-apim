# Native MCP Server Validation Plan

**Goal**: Assess whether Azure APIM's native MCP server feature provides sufficient value over the generic API approach to warrant migration.

**Status**: Experimental—both endpoints run in parallel, no production migration.

## Endpoints

| Track | URL | Identity | Policy |
|-------|-----|----------|--------|
| **Generic API** (existing) | `https://api.int.amnhealthcare.io/sfdcread/int/mcp` | Same Entra app | [apim-policy-sfdc-read-mcp.xml](../policies/apim-policy-sfdc-read-mcp.xml) |
| **Native MCP** (experiment) | `https://amn-wus2-hub-apim-i02.azure-api.net/sfdcread-mcp-native/mcp` | Same Entra app | [apim-policy-sfdc-read-mcp-native.xml](../policies/apim-policy-sfdc-read-mcp-native.xml) |

Both use the same backend: `https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads`

## Test Matrix

### Functional Parity

Run smoke tests against both endpoints and verify identical behavior:

```powershell
# Existing generic API
.\test-harness\Invoke-ApimSmokeTest.ps1 -Environment int

# Native MCP server
.\test-harness\Invoke-ApimSmokeTest.ps1 -Environment int-native
```

**Acceptance**: Both pass with identical results (or document any differences).

### Management UI Experience

| Task | Generic API | Native MCP Server | Winner |
|------|-------------|-------------------|--------|
| Find in portal | APIs tab, alphabetically under "S" | **MCP Servers tab** ✅ | Native |
| View exposed tools | Must infer from operations | **Tools blade** shows MCP tools ✅ | Native |
| Configure which tools are exposed | Edit operations + policy | **Select tools in UI** ✅ | Native |
| Policy scope | API-level | **MCP server-level** (cleaner separation) ✅ | Native |

### Monitoring & Observability

Compare Application Insights logs for the same request through both paths:

**Test**: Call `getUserInfo` tool through both endpoints with correlation ID.

**Generic API logs** should show:
- HTTP POST request
- `customDimensions`: generic HTTP fields
- Manual parsing needed to extract MCP method

**Native MCP logs** should show:
- HTTP POST request
- `customDimensions.mcpOperation`: `tools/call`
- `customDimensions.mcpSessionId`: session tracking
- `customDimensions.mcpMethod`: `getUserInfo`

**Acceptance**: Native provides MCP-specific telemetry fields; generic does not.

### Policy Complexity

| Metric | Generic API | Native MCP |
|--------|-------------|------------|
| Policy lines | 206 | ~150 |
| Manual routing | `set-backend-service` + `rewrite-uri` | Not needed ✅ |
| Method whitelist | Manual JSON-RPC filtering | APIM handles natively ✅ |
| Token exchange | Same (both need SF client_credentials) | Same |
| Error handling | Manual JSON-RPC envelope | Manual JSON-RPC envelope |

**Assessment**: Native is simpler but not dramatically so. Main win is APIM handling routing.

### API Center Registration

1. Check Azure API Center MCP server list
2. **Generic API**: Should NOT appear in MCP server registry
3. **Native MCP**: Should appear in registry (if APIM → API Center sync is configured)

**Acceptance**: Native MCP shows up; generic does not.

### Future-Proofing

Native MCP will receive:
- MCP Resources support (when Azure adds it)
- MCP Prompts support (when Azure adds it)
- Content safety controls (announced for 2026)
- Agent-to-Agent (A2A) capabilities

**Generic API will not receive these without manual implementation.**

## Decision Criteria

Migrate to native MCP if:
- ✅ Functional parity confirmed
- ✅ MCP-specific monitoring is valuable for troubleshooting
- ✅ Tools blade simplifies management
- ✅ API Center discovery is required
- ✅ Future MCP features (Resources, Prompts, A2A) are roadmap items

Stay with generic API if:
- ❌ Native MCP has protocol bugs or limitations
- ❌ Policy differences break existing behavior
- ❌ Migration effort outweighs management/monitoring gains
- ❌ Generic API "just works" and native adds no practical value

## Open Questions

1. **Does native MCP handle Salesforce's MCP quirks correctly?**
   - Salesforce requires `notifications/initialized` to flow through (not short-circuited)
   - Salesforce returns 202 for notifications, not 200
   - Test these edge cases explicitly

2. **Can we apply the same Key Vault-backed named values to native MCP policies?**
   - `{{SFDC-MCP-Client-ID}}`, `{{SFDC-MCP-Client-Secret}}` should work
   - Verify in policy editor

3. **Does native MCP support dual-audience JWT validation?**
   - We accept both `api://<app-id>` and bare `<app-id>`
   - Verify `validate-azure-ad-token` works the same in MCP server policy scope

4. **What happens to rate limiting?**
   - Generic API: Applied at operation level or via products
   - Native MCP: Applied at MCP server level—does this work the same?

5. **Can Power Automate / Copilot Studio point at the new URL with zero connector changes?**
   - Just swap the URL in the connector definition
   - Or does native MCP require different swagger annotations?

## Rollback Plan

If native MCP doesn't work or adds no value:
1. Delete the native MCP server resource in APIM (portal or Terraform)
2. Remove `int-native` config from smoke test
3. Delete `policies/apim-policy-sfdc-read-mcp-native.xml`
4. Continue with generic API—no production impact

## Timeline

- **Week 1**: Deploy native MCP server in INT via portal
- **Week 2**: Run functional parity tests, document monitoring differences
- **Week 3**: Test Consumer integration (PA connector pointing at new URL)
- **Week 4**: Decision meeting—migrate or stay with generic API
