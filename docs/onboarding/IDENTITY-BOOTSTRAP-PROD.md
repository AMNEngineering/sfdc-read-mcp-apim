# Identity Bootstrap — SFDCRead PROD MCP

Provisions the Entra ID and APIM identity surface that the SFDCRead PROD MCP gateway requires. Run this end-to-end for the first production install, a disaster-recovery rebuild, or a region cutover. The Copilot Studio and Power Automate PROD onboarding runbooks both depend on it.

Same shape as `IDENTITY-BOOTSTRAP-INT.md` — different constants. If you find yourself diverging structurally from the INT runbook, stop and revisit the design: PROD should be a values-only fork, not a redesign.

Nothing in this doc is a status assertion. Every constant is an input. Every step is a script intended for review by an app-registration admin, who runs it under change control during an approved maintenance window. Do not execute admin steps interactively from a daily-driver account, and do not execute them ad-hoc from a `.adm` break-glass account.

## What this provisions

1. Entra app registration with an exposed API scope (`user_impersonation`) and an app role (`MCP.Read`)
2. Redirect URIs for the Power Automate / Copilot Studio consent callbacks
3. Pre-authorized Azure API Management client (so end users do not see a consent prompt for the APIM-fronted scope)
4. Client secret stored in PROD Key Vault
5. Entra access group whose members receive the `MCP.Read` role claim
6. APIM OAuth2 authorization server bound to the API (handled by Terraform — referenced, not duplicated here)

## Environment constants — PROD

Fill values during the prod build. Until every constant is real (no `TBD`), do not `terraform apply` PROD. Match this table against `infrastructure/environments/prod.tfvars`.

| Constant | Value |
|---|---|
| Tenant ID | `6232c2ec-fa42-4f27-92cd-787913fba489` |
| Subscription | `TBD — confirm with platform-eng` |
| App registration display name | `SFDCRead PROD MCP` |
| Delegated scope value | `user_impersonation` |
| App role value | `MCP.Read` |
| APIM consent callback host | `global.consent.azure-apim.net` |
| APIM client app ID (built-in Azure first-party) | `8602e328-9b72-4f2d-a4ae-1387d013a2b3` |
| Access group display name | `AZ_AMN_AAD_SfdcReadMcp_Prod_User` |
| Key Vault name | `TBD — e.g. amn-wus2-sfdcread-kv-p01` |
| Client secret name | `copilot-studio-client-secret-prod` |
| APIM instance | (see `infrastructure/environments/prod.tfvars`) |
| APIM API path | `sfdcread/prod` |
| MCP endpoint | `https://api.amnhealthcare.io/sfdcread/prod/mcp` |
| Salesforce token URL | TBD — production org's My Domain URL `https://amnhealthcare.my.salesforce.com/services/oauth2/token` |

The client secret name is `copilot-studio-client-secret-prod` (parallel to INT's `copilot-studio-client-secret-int`). The same secret is used by Power Automate and any other OAuth 2.0 client that targets this app registration.

## Account hygiene

1. Daily-driver accounts (e.g., `<your-name>@amnhealthcare.com`) are used for read verification and for signing in to the OAuth consent flow as an end user.
2. App-registration changes, Key Vault writes, Graph PATCH calls, and group membership changes are admin actions. They run from PowerShell scripts that an app-registration admin reviews and executes from their own `.adm` context inside an isolated `AZURE_CONFIG_DIR` profile during an approved change window. They are never executed interactively from this runbook by the engineer driving onboarding.
3. The `.adm` break-glass account is never used for ad-hoc reads or for running unreviewed scripts. Its credentials rotate, and using it sidesteps the change-approval controls the org relies on.

## Azure CLI safety on shared workstations

When running any script in this doc against the AMN tenant, use an isolated profile so other Azure CLI sessions on the workstation are not disrupted:

	$env:AZURE_CONFIG_DIR = "$HOME/.azure-sfdcread-prod"
	az login --tenant 6232c2ec-fa42-4f27-92cd-787913fba489 --use-device-code
	az account set --subscription "<prod-subscription-name>"

Close the terminal (or `Remove-Item Env:AZURE_CONFIG_DIR`) when finished. Do not run `az logout` — it clears shared credential state. Use a **separate** `AZURE_CONFIG_DIR` from the INT profile so a stale prod token never leaks into an int session.

## Step 1: App registration

### 1.1 Verify or create

Daily driver (read only):

	az ad app list --display-name "SFDCRead PROD MCP" --query "[].{appId:appId,objectId:id,identifierUris:identifierUris,signInAudience:signInAudience}" -o json

- If a single result returns with a populated `appId`: record the `appId` and `objectId`, skip to Step 2.
- If no result returns: hand the create script in 1.2 to an admin.
- If multiple results return: stop — there is a duplicate, escalate before continuing.

### 1.2 Create script (admin)

Run [temp/Setup-SingleAppReg-Mcp.ps1](../../temp/Setup-SingleAppReg-Mcp.ps1) with prod values. This is the same script that provisioned the INT canonical app reg — pass `-AppDisplayName "SFDCRead PROD MCP"` and `-GroupDisplayName "AZ_AMN_AAD_SfdcReadMcp_Prod_User"`. Use `-UsePlaceholderRedirect` for the first run; replace the redirect URI in Step 4 once the connector UI emits the real callback.

	$env:AZURE_CONFIG_DIR = "$HOME/.azure-sfdcread-prod"
	az login --tenant 6232c2ec-fa42-4f27-92cd-787913fba489 --use-device-code

	.\temp\Setup-SingleAppReg-Mcp.ps1 `
	  -AppDisplayName    "SFDCRead PROD MCP" `
	  -GroupDisplayName  "AZ_AMN_AAD_SfdcReadMcp_Prod_User" `
	  -AdminUpn          "<admin-upn>" `
	  -UsePlaceholderRedirect `
	  -CreateClientSecret

Record the emitted `appId`, `objectId`, app role `id`, and the client secret value. Hand the secret to Step 6 (Key Vault store) immediately — do not record it in this runbook.

## Step 2: Exposed API scope (`user_impersonation`)

### 2.1 Verify

Daily driver:

	az ad app show --id <app-id> --query "api.oauth2PermissionScopes[].{value:value,isEnabled:isEnabled,id:id}" -o json

- Expected: a single entry with `value = user_impersonation` and `isEnabled = true`. Record the `id` (scope GUID).
- If missing or disabled: the Setup script in 1.2 should have created it. Re-run, or hand the script in IDENTITY-BOOTSTRAP-INT.md Step 2.2 to an admin (same script, prod app id).

## Step 3: App role (`MCP.Read`)

### 3.1 Verify

Daily driver:

	az ad app show --id <app-id> --query "appRoles[?value=='MCP.Read'].{value:value,isEnabled:isEnabled,id:id}" -o json

- Expected: a single entry with `value = MCP.Read`, `isEnabled = true`. Record the `id`.
- If missing or disabled: the Setup script in 1.2 should have created it. If it shows up with a different `value` (e.g. `User`) or a placeholder GUID, that's the same defect that affected INT — run [temp/Repair-SfdcReadMcpAppRole-Int.ps1](../../temp/Repair-SfdcReadMcpAppRole-Int.ps1) with prod parameters (or hand the IDENTITY-BOOTSTRAP-INT.md Step 3.2 script to an admin).

## Step 4: Redirect URIs

Each Power Automate Custom Connector and each Copilot Studio MCP Server tool generates its own redirect URI at the host `global.consent.azure-apim.net`. There is no single shared URI — the runbooks instruct the engineer to capture the per-connector URI from the client UI and hand it back here.

### 4.1 Verify

Daily driver:

	az ad app show --id <app-id> --query "web.redirectUris" -o json

- The list should include `https://localhost` (for local testing harnesses) and one `https://global.consent.azure-apim.net/redirect/<id>` entry per registered client connector.

### 4.2 Add script (admin)

Same as IDENTITY-BOOTSTRAP-INT.md Step 4.2 — substitute the prod app id.

## Step 5: Pre-authorize APIM as a client

APIM exchanges the user's token for the user_impersonation scope on the API. Pre-authorizing the APIM client app ID suppresses an end-user consent prompt for that scope.

### 5.1 Verify

Daily driver:

	az ad app show --id <app-id> --query "api.preAuthorizedApplications[?appId=='8602e328-9b72-4f2d-a4ae-1387d013a2b3']" -o json

- Expected: a single entry with the APIM `appId` and `delegatedPermissionIds` containing the scope `id` recorded in Step 2.

### 5.2 Add script (admin)

Same as IDENTITY-BOOTSTRAP-INT.md Step 5.2 — substitute the prod object id and scope id.

## Step 6: Client secret in PROD Key Vault

### 6.1 Verify

Daily driver:

	az keyvault secret show --vault-name "<prod-kv-name>" --name "copilot-studio-client-secret-prod" --query "{id:id,enabled:attributes.enabled,updated:attributes.updated,expires:attributes.expires}" -o json

- If the secret exists and `enabled = true` and `expires` is not near term: proceed.
- If missing or expired: hand the create/rotate script in 6.2 to an admin.

### 6.2 Create or rotate script (admin)

Same shape as IDENTITY-BOOTSTRAP-INT.md Step 6.2. Substitute the prod app id, prod vault name, and `copilot-studio-client-secret-prod`.

## Step 7: Access group

### 7.1 Verify

Daily driver:

	az ad group show --group "AZ_AMN_AAD_SfdcReadMcp_Prod_User" --query "{id:id,displayName:displayName}" -o json

- If a group returns: record the `id`.
- If 404: hand the create script in IDENTITY-BOOTSTRAP-INT.md Step 7.2 to an admin, with the prod group name.

### 7.2 Assign the group to the `MCP.Read` app role

The Setup script in Step 1.2 already assigns the group if the group exists at the time of run. If you created the app reg first and the group later, run the assignment script from IDENTITY-BOOTSTRAP-INT.md Step 7.3 with prod values.

### 7.3 Membership management

Production access is gated. Group adds require an approved access request, not a developer's daily-driver. Coordinate with whoever owns prod access reviews. Membership changes can take minutes to propagate into freshly issued tokens — instruct end users to sign out and back in if their first connection attempt returns 403.

## Step 8: APIM OAuth2 authorization server

APIM publishes the OAuth2 metadata that Power Automate and Copilot Studio consume when fetching connector swagger / MCP descriptors. This is provisioned by Terraform, not by hand.

1. Module: `infrastructure/modules/oauth2-auth-server/`
2. Wiring: `infrastructure/main.tf` calls the module with `var.sfdc_read_mcp_app_id` as the client_app_id.
3. Per-env input: `infrastructure/environments/prod.tfvars` sets `sfdc_read_mcp_app_id` to the app ID from Step 1.
4. The APIM API policy template (`policies/apim-policy-sfdc-read-mcp.xml`) validates that audience.

To apply:

	# From infrastructure/
	terraform init
	terraform plan  -var-file=environments/prod.tfvars
	# Do NOT terraform apply locally for PROD. Push the plan through the pipeline.

The pipeline (`.ado/pipelines/deploy.yml`) runs `terraform plan` automatically on PR and gates `terraform apply` behind a `ManualValidation@0` approval. Use the pipeline for PROD — there is no scenario where a local prod apply is appropriate.

### Verify the deployed auth server (daily driver)

	az rest --method GET --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<apim-rg>/providers/Microsoft.ApiManagement/service/<apim-name>/authorizationServers/sfdc-read-mcp-prod-entra?api-version=2022-08-01" --query "{name:name,authorize:properties.authorizationEndpoint,token:properties.tokenEndpoint,clientId:properties.clientId,scope:properties.defaultScope,grantTypes:properties.grantTypes}" -o json

Expected fields:
- `authorize` ends in `/oauth2/v2.0/authorize` and contains the tenant ID from the constants table
- `token` ends in `/oauth2/v2.0/token` and contains the tenant ID
- `clientId` matches the app ID from Step 1
- `scope` is `api://<app-id>/user_impersonation`
- `grantTypes` contains `authorizationCode`

## Disaster recovery quick path

If the entire PROD identity surface has been lost and needs rebuilding:

1. Run Steps 1–7 in order. Each Step's `.1 Verify` block will report missing and the `.2 Create/Add` script is what an admin runs.
2. Update `infrastructure/environments/prod.tfvars` with the new app ID and any new key vault name.
3. Run Step 8's `terraform plan` and push through the pipeline for the apply.
4. Update the prod connector runbooks' Step 0 constants tables with the new App ID and any new scope/role GUIDs.
5. Re-run the verification reads at the top of the prod Copilot Studio and Power Automate runbooks once those are written.
6. Ask onboarded end users to recreate their connections — the per-connector redirect URIs change.

## What the runbooks downstream of this assume

The (forthcoming) prod Copilot Studio and Power Automate runbooks assume Steps 1–8 here are complete. They verify (read-only) but do not provision. If their verification fails, the operator returns here, runs the missing step, then resumes the connector flow.

When those connector runbooks are written, they should be values-only forks of the INT versions, not redesigns. If the INT runbook is wrong, fix it in INT first and re-fork.
