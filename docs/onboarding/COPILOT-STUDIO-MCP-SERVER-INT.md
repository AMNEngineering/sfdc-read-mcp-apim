# Copilot Studio MCP Server — SFDCRead INT MCP

Onboards a Copilot Studio MCP Server tool that calls the SFDCRead INT MCP gateway over OAuth 2.0. Follow this for a first-time install, a per-copilot rollout, or a DR rebuild after the identity surface has been re-provisioned.

For Power Automate, see `POWER-AUTOMATE-CUSTOM-CONNECTOR-INT.md` in this folder. Same identity surface, different UI — do not transcribe field-by-field across runbooks.

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
| Refresh Token URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| MCP endpoint | `https://api.int.amnhealthcare.io/sfdcread/int/mcp` |
| Access group | `AZ_AMN_AAD_SfdcReadMcp_Int_User` |
| Key Vault | `amn-wus2-sfdcread-kv-i01` |
| Client secret name | `copilot-studio-client-secret-int` |

## Account hygiene

1. Use the daily-driver account (`<your-name>@amnhealthcare.com`) to run the verification reads below and to sign in to the OAuth consent flow.
2. Any change to the app registration (redirect URI add, secret rotation, scope edit, pre-authorization) goes through `IDENTITY-BOOTSTRAP-INT.md` and is run by an admin from a PowerShell script under change control. Do not edit the app reg from this runbook.

## Step 0: Verify prerequisites (daily driver)

Pull the constants you will paste into the Copilot Studio OAuth form and confirm the identity surface is provisioned.

	$tenantId = "6232c2ec-fa42-4f27-92cd-787913fba489"
	$appId    = az ad app list --display-name "SFDCRead INT MCP" --query "[0].appId" -o tsv
	if (-not $appId) { throw "App registration not found. Run IDENTITY-BOOTSTRAP-INT.md Step 1." }

	"Client ID:         $appId"
	"Authorization URL: https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize"
	"Token URL:         https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
	"Refresh URL:       https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
	"Scope:             api://$appId/user_impersonation"

	az ad app show --id $appId --query "{scope:api.oauth2PermissionScopes[?value=='user_impersonation'].isEnabled | [0], role:appRoles[?value=='MCP.Read'].isEnabled | [0], preAuthApim:api.preAuthorizedApplications[?appId=='8602e328-9b72-4f2d-a4ae-1387d013a2b3'] | length(@)}" -o json
	az keyvault secret show --vault-name "amn-wus2-sfdcread-kv-i01" --name "copilot-studio-client-secret-int" --query "{enabled:attributes.enabled,expires:attributes.expires}" -o json

Acceptance:
- `scope` is `true`
- `role` is `true`
- `preAuthApim` is `1`
- Key Vault secret `enabled` is `true` and `expires` is not in the past

If any fail, run the corresponding step in `IDENTITY-BOOTSTRAP-INT.md` before continuing.

Confirm the operator is in the access group:

	az ad group member check --group "AZ_AMN_AAD_SfdcReadMcp_Int_User" --member-id (az ad signed-in-user show --query id -o tsv)

Expect `{"value": true}`. If `false`, an admin adds the user to the group before Step 3.

## Step 1: Add an MCP Server tool in Copilot Studio

1. Open Copilot Studio and select the copilot that should consume SFDCRead.
2. Go to `Tools` → `Add tool`.
3. Choose `MCP Server (Model Context Protocol server)`.
4. Enter:
- Name: `SFDCRead INT MCP`
- Server URL: `https://api.int.amnhealthcare.io/sfdcread/int/mcp`
- Transport: `Streamable HTTP` (or the default MCP HTTP option if Streamable is not shown)

## Step 2: Configure OAuth 2.0

1. Authentication: `OAuth 2.0`
2. Choose `Manual config` (recommended). The Copilot Studio MCP form is a flat list of OAuth fields; there is no `Identity Provider` dropdown.
3. Paste the values from Step 0's output into the form:

| Field | Value |
|---|---|
| Client ID | App ID from Step 0 |
| Client Secret | output of the Key Vault read below |
| Authorization URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize` |
| Token URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| Refresh Token URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| Scopes | `api://<app-id>/user_impersonation` |

Fetch the client secret value at onboarding time (do not record it in this runbook):

	az keyvault secret show --vault-name "amn-wus2-sfdcread-kv-i01" --name "copilot-studio-client-secret-int" --query value -o tsv

4. Save the tool.

## Step 3: Create the connection

1. In the connection modal, click `Create`.
- The modal itself is not editable. The OAuth values it uses come from Step 2 — if anything is wrong, cancel out, fix Step 2, and try Create again.
2. A consent popup opens in the browser. Sign in with the daily-driver account verified in Step 0.

### Browser caveat — managed Chrome

If Chrome is enterprise-managed on the workstation, an extension policy can close the consent popup before it completes. The symptom is a generic "consent pop-up window has been closed unexpectedly" message.

1. Cancel the current connection attempt.
2. Reopen Copilot Studio in Edge (regular window, not InPrivate).
3. Confirm Edge allows popups and third-party cookies for `copilotstudio.microsoft.com`, `login.microsoftonline.com`, `global.consent.azure-apim.net`.
4. Retry `Create` on the same tool.
5. If Chrome is mandated by org policy, escalate the policy exception to IT — that is a separate workstream, not a runbook blocker.

This is a browser/session issue, not evidence that the OAuth values are wrong.

## Step 4: Test the tool

1. In the copilot's authoring canvas, invoke the tool with `tools/list`.
2. Expect a tool catalog response with the SFDCRead tool definitions.

### Acceptance

| Outcome | Interpretation | Action |
|---|---|---|
| Tool catalog returned | OAuth + APIM + Salesforce path works | Onboarding done |
| 403 `User does not have MCP.Read role` | OAuth succeeded; user lacks the role claim | Confirm group membership; sign out and back in to refresh the token |
| 401 Unauthorized | Token audience / issuer / signature mismatch | Re-verify Step 2 fields against Step 0 output exactly |
| AADSTS50011 redirect URI mismatch | Per-connector redirect URI not on the app reg | Capture the exact URI from the consent error page; hand to admin for bootstrap Step 4.2 |
| AADSTS65001 consent required | Pre-authorization missing on the app reg | Run bootstrap Step 5 |
| AADSTS70011 invalid scope | Scope field wrong format | Must be full `api://<app-id>/user_impersonation`, not just `user_impersonation` |
| "Unable to sign in" (generic) with no redirect mismatch | Tenant consent policy blocking delegated scope consent | Verify bootstrap Step 5 pre-authorization is in place; retry |

## Failure recovery

1. Single user reports 403 after a previously working connection: their group membership was likely removed, or their token is stale — they sign out and back in.
2. All users fail with 401 simultaneously: client secret may have rotated. Re-fetch from Key Vault (Step 2 fetch command) and paste into the tool's OAuth form, then save. If the secret is also expired in Key Vault, return to `IDENTITY-BOOTSTRAP-INT.md` Step 6.
3. Tool returns an unexpected JSON-RPC error envelope from the backend: read `error.data`. Treat Salesforce data-access errors as flag-for-review per the project's data constraints, not as runbook failure.
