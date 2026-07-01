# Power Automate Custom Connector — SFDCRead INT MCP

Onboards a Power Automate Custom Connector that calls the SFDCRead INT MCP gateway over OAuth 2.0. Follow this for a first-time install, a per-tenant rollout, or a DR rebuild after the identity surface has been re-provisioned.

For Copilot Studio, see `COPILOT-STUDIO-MCP-SERVER-INT.md` in this folder. Same identity surface, different UI — do not transcribe field-by-field across runbooks.

## Prerequisite

The identity surface (Entra app registration, scope, role, client secret in Key Vault, access group, APIM auth server) is provisioned per `IDENTITY-BOOTSTRAP-INT.md`. The verification reads in Step 0 below confirm the prerequisites are in place; if any fail, return to the bootstrap doc, finish the missing step, then resume here.

## Constants — INT

These values come from the bootstrap doc. Pull current values before each onboarding so a rotated secret or a new app ID does not silently break the install.

| Constant | Value |
|---|---|
| Tenant ID | `6232c2ec-fa42-4f27-92cd-787913fba489` |
| App (client) ID | from `az ad app list --display-name "SFDCRead INT MCP" --query "[0].appId" -o tsv` |
| Scope | `api://<app-id>/user_impersonation` |
| Authorization URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize` |
| Token URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| Refresh URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| MCP endpoint host | `api.int.amnhealthcare.io` |
| MCP endpoint base path | `/sfdcread/int` |
| MCP endpoint full URL | `https://api.int.amnhealthcare.io/sfdcread/int/mcp` |
| Access group | `AZ_AMN_AAD_SfdcReadMcp_Int_User` |
| Key Vault | `amn-wus2-sfdcread-kv-i01` |
| Client secret name | `copilot-studio-client-secret-int` |

## Account hygiene

1. Use the daily-driver account (`<your-name>@amnhealthcare.com`) to run the verification reads below and to sign in to the OAuth consent flow.
2. Any change to the app registration (redirect URI add, secret rotation, scope edit, pre-authorization) goes through `IDENTITY-BOOTSTRAP-INT.md` and is run by an admin from a PowerShell script under change control. Do not edit the app reg from this runbook.

## Step 0: Verify prerequisites (daily driver)

Pull the constants you will paste into the Security tab and confirm the identity surface is provisioned.

	$tenantId = "6232c2ec-fa42-4f27-92cd-787913fba489"
	$appId    = az ad app list --display-name "SFDCRead INT MCP" --query "[0].appId" -o tsv
	if (-not $appId) { throw "App registration not found. Run IDENTITY-BOOTSTRAP-INT.md Step 1." }

	"Authorization URL: https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize"
	"Token URL:         https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
	"Refresh URL:       https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
	"Scope:             api://$appId/user_impersonation"
	"Client id:         $appId"

	az ad app show --id $appId --query "{scope:api.oauth2PermissionScopes[?value=='user_impersonation'].isEnabled | [0], role:appRoles[?value=='MCP.Read'].isEnabled | [0], preAuthApim:api.preAuthorizedApplications[?appId=='8602e328-9b72-4f2d-a4ae-1387d013a2b3'] | length(@)}" -o json
	az keyvault secret show --vault-name "amn-wus2-sfdcread-kv-i01" --name "copilot-studio-client-secret-int" --query "{enabled:attributes.enabled,expires:attributes.expires}" -o json

Acceptance:
- `scope` is `true`
- `role` is `true`
- `preAuthApim` is `1`
- Key Vault secret `enabled` is `true` and `expires` is not in the past

If any fail, run the corresponding step in `IDENTITY-BOOTSTRAP-INT.md` before continuing.

Confirm the operator running the onboarding is in the access group (otherwise the test in Step 4 will return 403):

	az ad group member check --group "AZ_AMN_AAD_SfdcReadMcp_Int_User" --member-id (az ad signed-in-user show --query id -o tsv)

Expect `{"value": true}`. If `false`, an admin adds the user to the group before Step 4.

## Step 1: Custom Connector — General tab

1. Open https://make.powerautomate.com → Data → Custom connectors → New custom connector → Create from blank.
2. Connector name: `SFDCRead INT MCP`
3. Scheme: HTTPS
4. Host: `api.int.amnhealthcare.io`
5. Base URL: `/` (leave the entire path — `/sfdcread/int/mcp` — in the operation's URL in Step 3 instead)

Click the right-arrow to advance to Security.

Why not put `/sfdcread/int` in Base URL: Power Automate concatenates `host` + `basePath` + operation `path` when it renders the request URL. If Base URL is `/sfdcread/int` **and** the operation path is `/sfdcread/int/mcp`, the effective request URL is `https://api.int.amnhealthcare.io/sfdcread/int/sfdcread/int/mcp` — a 404. Keeping Base URL at `/` and the full path on the operation avoids the concatenation trap.

## Step 2: Custom Connector — Security tab

1. Authentication type: `OAuth 2.0`
2. Identity Provider: `Generic Oauth 2`
- Do not pick `Azure Active Directory`. That mode forces v1 Entra endpoints (`/oauth2/authorize`, `/oauth2/token`) and uses a `Resource URL` field instead of `Scope`. The APIM auth server publishes v2 endpoints and the APIM policy validates the v2 audience `api://<app-id>`. Generic Oauth 2 keeps the flow on v2.
3. Fill the OAuth 2.0 fields. The values come from Step 0's output:

| Field | Value |
|---|---|
| Client id | App ID from Step 0 |
| Client secret | Output of the Key Vault read below |
| Authorization URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize` |
| Token URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| Refresh URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| Scope | `api://<app-id>/user_impersonation` |

Fetch the client secret value at onboarding time (do not record it in this runbook):

	az keyvault secret show --vault-name "amn-wus2-sfdcread-kv-i01" --name "copilot-studio-client-secret-int" --query value -o tsv

4. Click `Create connector` at the top right. After save, Power Automate populates a `Redirect URL` field at the bottom of the Security tab in the form:

	https://global.consent.azure-apim.net/redirect/<connector-id-power-automate-mints>

5. Compare that Redirect URL against the app registration:

	az ad app show --id <app-id> --query "web.redirectUris" -o json

- If the URL is already in the list: continue to Step 3.
- If it is not in the list: STOP. Do not advance to Test → New connection (AADSTS50011 will follow). Hand the exact URL to an app-registration admin who runs `IDENTITY-BOOTSTRAP-INT.md` Step 4.2 under change control. Resume here after the admin confirms the URI has been added.

## Step 3: Custom Connector — Definition tab

Power Platform recognizes the endpoint as a Model Context Protocol streamable HTTP server and switches the connector to **MCP protocol mode** (annotation `x-ms-agentic-protocol: mcp-streamable-1.0` in the swagger). In this mode the MCP runtime injects its own request body and routes JSON-RPC traffic — the connector definition must NOT include a typed request body or `Content-Type` header. Adding them produces a duplicate body parameter and APIM rejects the swagger with:

	Parsing error(s): Operation can have only one body parameter. Path: paths['/.../mcp'].post.parameters[N]

Define the action as a thin proxy:

1. Click `New action`.
2. General:
- Summary: `Invoke MCP`
- Description: `MCP Streamable HTTP endpoint`
- Operation ID: `invokeMcp`
- Visibility: `important`
3. Request:
- Verb: POST
- URL: `https://api.int.amnhealthcare.io/sfdcread/int/mcp`
- Do NOT add any headers, body sample, or query parameters. Leave the request shape empty.
4. Response:
- Add a `200` response with description `Success`, no schema.
- Add a `202` response with description `Accepted`, no schema.

If `Import from sample` already added typed parameters, toggle `Swagger Editor` on (top right) and replace the operation with:

	paths:
	  /sfdcread/int/mcp:
	    post:
	      summary: Invoke MCP
	      description: MCP Streamable HTTP endpoint
	      operationId: invokeMcp
	      x-ms-agentic-protocol: mcp-streamable-1.0
	      x-ms-visibility: important
	      responses:
	        '200':
	          description: Success
	        '202':
	          description: Accepted

Specifically remove any `parameters:` block (no `Content-Type` header, no `body` parameter) and any typed response schema. The MCP runtime supplies them.

5. Click `Update connector`.

### Watch out: Security tab provider drift

When the Identity Provider in the Security tab is `Azure Active Directory`, Power Automate overwrites the OAuth URLs with v1 / `common`-tenant defaults that look like `https://login.windows.net/common/oauth2/authorize` — regardless of what was typed. The APIM auth server publishes v2 endpoints and the APIM policy validates the v2 audience, so a v1 / common token will not be accepted.

Always confirm the Identity Provider stays at `Generic Oauth 2` (Step 2 item 2). If the swagger shows `login.windows.net` or `/common/` in `securityDefinitions`, return to the Security tab and switch back.

## Step 4: Custom Connector — Test tab (auth-plane only)

**The Test tab is not a valid MCP tool test.** It performs a plain HTTP POST with `Accept: application/json`; the MCP streamable-HTTP transport requires `Accept: application/json, text/event-stream`. Attempting `tools/list` from the Test tab returns HTTP 406 with body `{"error":{"code":406,"message":"Accept header must include both application/json and text/event-stream"}}`. The response headers include `x-ms-apihub-cached-response: true`, indicating the failure is intercepted at Power Automate's API Hub layer or cached from a prior SF response. Adding an `Accept` header parameter to the connector definition to work around this is **not viable** — it trips APIM's swagger validator with "Operation can have only one body parameter" and breaks MCP mode.

Use the Test tab only to prove the **auth plane** works: `New connection` → sign-in completes → connection status = `Connected`. Any concrete MCP tool call (`tools/list`, `getUserInfo`, etc.) must be validated via one of the two paths in the [MCP validation methodology](../TESTING.md).

1. Click `New connection`.
2. Sign in with the daily-driver account verified in Step 0. A consent prompt appears on first connection.
3. Confirm the connection status flips to `Connected`.

### Acceptance (auth plane only)

| Outcome | Interpretation | Action |
|---|---|---|
| Connection status = `Connected` | OAuth flow reached Entra, PA persisted a delegated user token | Auth plane proven. Continue to consumer-plane validation (below). |
| AADSTS50011 on consent | Per-connector redirect URI not on the app reg | Step 2 item 5 — admin adds via bootstrap Step 4.2 |
| AADSTS65001 consent required | Pre-authorization missing on the app reg | Run bootstrap Step 5 |
| AADSTS70011 invalid scope | Scope field wrong format | Must be full `api://<app-id>/user_impersonation`, not just `user_impersonation` |
| Consent popup closes immediately | Managed Chrome extension interfering | Retry in Edge |
| Any 406 from a Test tab tool invocation | Expected — Test tab is not an MCP client | Do not treat as a bug. Move to consumer-plane validation. |

### Consumer-plane validation (mandatory follow-through)

Auth-plane success is not sufficient. To prove the connector works end-to-end through the MCP transport, run one of:

- **PowerShell smoke** — `az login` as daily driver, then `.\test-harness\Invoke-ApimSmokeTest.ps1 -AssertDelegated`. Validates the delegated token path with correct MCP `Accept` headers. Repeatable, CI-friendly.
- **Copilot Studio agent** — install the connector on an agent in the same environment and invoke a concrete tool (e.g., "Get my Salesforce user info"). Validates the MCP runtime host that production consumers use. See `COPILOT-STUDIO-MCP-SERVER-INT.md`.

Both paths use the same delegated OAuth flow the connector's Security tab configures. If Test tab connects but neither consumer-plane path works, the connector's swagger has drifted (usually the OAuth URLs — see the drift warning above); rerun Step 2 and paste the swagger for review.

## Step 5: Share the connector (optional)

1. Connector list → `...` → `Export` → save the swagger JSON to `docs/connectors/` in the repo so the definition is reproducible.
2. Connector list → `...` → `Share` → add specific users or AAD groups (typically `AZ_AMN_AAD_SfdcReadMcp_Int_User`). Do not publish publicly.

## Failure recovery

1. If a single user reports 403 after a previously working connection: their group membership was likely removed, or their token is stale — they sign out and back in.
2. If all users start failing with 401 simultaneously: client secret may have rotated. Re-fetch from Key Vault (Step 2 fetch command) and paste into the connector's Security tab, then `Update connector`. If the secret is also expired in Key Vault, return to `IDENTITY-BOOTSTRAP-INT.md` Step 6.
3. If the connector itself is corrupt or unreachable: export the swagger, delete the connector, re-import from the saved swagger, re-run Step 4.
