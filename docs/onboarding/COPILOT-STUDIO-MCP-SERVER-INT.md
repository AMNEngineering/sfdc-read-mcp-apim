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

## The pattern: Custom Connector auto-discovery, not "MCP Server tool"

Copilot Studio does not require a separately-configured "MCP Server" tool for SFDCRead. The Power Automate Custom Connector (built per `POWER-AUTOMATE-CUSTOM-CONNECTOR-INT.md`) carries the annotation `x-ms-agentic-protocol: mcp-streamable-1.0` in its swagger. Copilot Studio auto-discovers any Custom Connector with that annotation as an MCP-capable tool at the environment level — no re-configuration of OAuth in Copilot Studio, no duplicate client-secret registration. One identity surface, one connector, discovered by both hosts.

Prerequisite for this doc: `POWER-AUTOMATE-CUSTOM-CONNECTOR-INT.md` completed in the target environment. That runbook produces the tool this one consumes.

## Step 1: Verify the tool is discovered

1. Open Copilot Studio in the target environment:

	https://copilotstudio.microsoft.com/environments/<env-id>

2. Left nav → `Tools`.
3. Confirm `SFDCRead INT MCP` appears with:
- Type: `Custom Connector`
- Status: `Ready`

If it does not appear:
- Confirm the Custom Connector was saved (not draft) in Power Automate and shared with the target audience.
- Confirm you opened Copilot Studio in the same environment as the connector (env id in the URL matches).
- If both are true, back to `POWER-AUTOMATE-CUSTOM-CONNECTOR-INT.md` Step 3 — the `x-ms-agentic-protocol` annotation must be present in the operation swagger.

## Step 2: Install the tool on an agent

1. Left nav → `Agents`.
2. Open the target agent, or `Create blank agent` if starting fresh. The agent must be in the same environment as the Custom Connector.
3. In the agent's tools / actions surface (label varies by UI vintage), add `SFDCRead INT MCP` from the tool picker.
4. Confirm the tool now shows `Installed on: <your agent>` when you return to the Tools list.

## Step 3: Establish or refresh the connection

The first time the agent invokes the MCP tool, Copilot Studio requires a delegated user connection. This uses the same Entra flow the PA Custom Connector configured — no OAuth values are re-entered in Copilot Studio.

1. Open the agent and reveal the `Test your agent` pane (right side).
2. Type a prompt that exercises the tool, e.g. `Get my Salesforce user info`.
3. Expected first-run reply:

	Let's get you connected first, and then I can find that info for you. Open connection manager to verify your credentials.

4. Click `Open connection manager`. The connections page opens showing `SFDCRead INT MCP` with a status.
5. Act on the status:
- `Not connected` → click `Connect`, sign in as your daily-driver account (Step 0 identity), complete any consent prompt.
- `Stale` → click `Review`, confirm the sign-in identity, submit. In most cases no browser popup opens — Copilot Studio silently refreshes via the existing session.
- `Connected` → no action.
6. Return to the agent's test pane and re-send the prompt (or click `Retry`).

### Browser caveat — managed Chrome

If Chrome is enterprise-managed on the workstation, an extension policy can close the consent popup before it completes. Symptom: "consent pop-up window has been closed unexpectedly".

1. Cancel the current connection attempt.
2. Reopen Copilot Studio in Edge (regular window, not InPrivate).
3. Confirm Edge allows popups and third-party cookies for `copilotstudio.microsoft.com`, `login.microsoftonline.com`, `global.consent.azure-apim.net`.
4. Retry the connection action.
5. If Chrome is mandated by org policy, escalate the exception to IT.

This is a browser/session issue, not evidence that the OAuth values are wrong.

## Step 4: Test the tool

With the connection `Connected`, re-send the prompt in the test pane. Expected response for `Get my Salesforce user info`:

- The agent renders a formatted table of user details.
- The `identity.email` and `identity.username` values reference the Salesforce-side service account (e.g. `sfdcadmin@amnhealthcare.com` / `copilotstudio@amnhealthcare.com.qa`), not the Entra caller. This is by design: the Entra token proves the user has the MCP.Read role at APIM; APIM then swaps in Salesforce's own credentials via client_credentials for the backend call.
- `userTimeAndLocale.localTimeIso` reflects real time (not a cached value).

### Acceptance

| Outcome | Interpretation | Action |
|---|---|---|
| Formatted response with SF service identity | Delegated OAuth + APIM + Salesforce path works end-to-end via the MCP runtime host | Onboarding done. Capture the transcript as evidence for the story. |
| "Let's get you connected first" repeatedly | Connection did not persist after Review/Connect | Reopen `Open connection manager`; confirm status flipped to `Connected` before retrying |
| 403 `User does not have MCP.Read role` | OAuth succeeded; user lacks the role claim at APIM | Confirm group membership in `AZ_AMN_AAD_SfdcReadMcp_Int_User`; sign out and back in to refresh the token |
| 401 Unauthorized from APIM | Token audience / issuer / signature mismatch | The PA Custom Connector's Security tab OAuth URLs are wrong. Return to `POWER-AUTOMATE-CUSTOM-CONNECTOR-INT.md` Step 2 |
| Response contains SF error `sObject type '<Name>' is not supported` | Data-exposure boundary held (SF-side denial for excluded types). This is a design correctness signal, not a runbook failure | Confirm the user's ask targets a supported object; do not treat as a bug |
| Tool never appears in the test pane's tool-invocation trace | The agent didn't select the tool from its available set | Confirm the tool is `Installed on` the agent (Step 2); adjust the agent's tool-selection instructions if needed |
| 406 with "Accept header must include both" | You invoked from a plain-REST tester (Power Automate Test tab, curl without Accept: text/event-stream). Not a Copilot Studio path | Not a failure of this runbook. See `POWER-AUTOMATE-CUSTOM-CONNECTOR-INT.md` Step 4 |

## Failure recovery

1. Single user reports 403 after a previously working connection: their group membership was likely removed, or their token is stale — they sign out and back in.
2. All users fail with 401 simultaneously: the PA Custom Connector's client secret may have rotated. Re-fetch from Key Vault and update via `POWER-AUTOMATE-CUSTOM-CONNECTOR-INT.md` Step 2 — do not attempt to change OAuth config from Copilot Studio.
3. Tool returns an unexpected JSON-RPC error envelope from the backend: read `error.data`. Treat Salesforce data-access errors as flag-for-review per the project's data constraints, not as runbook failure.
4. Agent-selection issue (tool never invoked): adjust the agent's system instructions to reference `SFDCRead INT MCP` explicitly, or add a topic that routes SFDC-related asks to the tool.
