# Identity Bootstrap — SFDCRead INT MCP

Provisions the Entra ID and APIM identity surface that the SFDCRead INT MCP gateway requires. Run this end-to-end for a new install, a disaster-recovery rebuild, or a region cutover. The Copilot Studio and Power Automate onboarding runbooks both depend on it.

Nothing in this doc is a status assertion. Every constant is an input. Every step is a script intended for review by an app-registration admin, who runs it under change control during an approved maintenance window. Do not execute admin steps interactively from a daily-driver account, and do not execute them ad-hoc from a `.adm` break-glass account.

## What this provisions

1. Entra app registration with an exposed API scope (`user_impersonation`) and an app role (`MCP.Read`)
2. Redirect URIs for the Power Automate / Copilot Studio consent callbacks
3. Pre-authorized Azure API Management client (so end users do not see a consent prompt for the APIM-fronted scope)
4. Client secret stored in Key Vault
5. Entra access group whose members receive the `MCP.Read` role claim
6. APIM OAuth2 authorization server bound to the API (handled by Terraform — referenced, not duplicated here)

## Environment constants — INT

These are the inputs. For a different environment (PROD, second region, DR rebuild in a new tenant) create a sibling doc and replace the values.

| Constant | Value |
|---|---|
| Tenant ID | `6232c2ec-fa42-4f27-92cd-787913fba489` |
| Subscription | `AMN Intelligent Platform Services Prod` |
| App registration display name | `SFDCRead INT MCP` |
| Delegated scope value | `user_impersonation` |
| App role value | `MCP.Read` |
| APIM consent callback host | `global.consent.azure-apim.net` |
| APIM client app ID (built-in Azure first-party) | `8602e328-9b72-4f2d-a4ae-1387d013a2b3` |
| Access group display name | `AZ_AMN_AAD_SfdcReadMcp_Int_User` |
| Key Vault name | `amn-wus2-sfdcread-kv-i01` |
| Client secret name | `copilot-studio-client-secret-int` |
| APIM instance | (see `infrastructure/environments/int.tfvars`) |
| APIM API path | `sfdcread/int` |
| MCP endpoint | `https://api.int.amnhealthcare.io/sfdcread/int/mcp` |

The client secret name is `copilot-studio-client-secret-int` for historical reasons — Copilot Studio was the first consumer. The same secret is used by Power Automate and any other OAuth 2.0 client that targets this app registration.

## Account hygiene

1. Daily-driver accounts (e.g., `bart.elia@amnhealthcare.com`) are used for read verification and for signing in to the OAuth consent flow as an end user.
2. App-registration changes, Key Vault writes, Graph PATCH calls, and group membership changes are admin actions. They run from PowerShell scripts that an app-registration admin reviews and executes from their own `.adm` context inside an isolated `AZURE_CONFIG_DIR` profile during an approved change window. They are never executed interactively from this runbook by the engineer driving onboarding.
3. The `.adm` break-glass account is never used for ad-hoc reads or for running unreviewed scripts. Its credentials rotate, and using it sidesteps the change-approval controls the org relies on.

## Azure CLI safety on shared workstations

When running any script in this doc against the AMN tenant, use an isolated profile so other Azure CLI sessions on the workstation are not disrupted:

	$env:AZURE_CONFIG_DIR = "$HOME/.azure-sfdcread-int"
	az login --tenant 6232c2ec-fa42-4f27-92cd-787913fba489 --use-device-code
	az account set --subscription "AMN Intelligent Platform Services Prod"

Close the terminal (or `Remove-Item Env:AZURE_CONFIG_DIR`) when finished. Do not run `az logout` — it clears shared credential state.

## Step 1: App registration

### 1.1 Verify or create

Daily driver (read only):

	az ad app list --display-name "SFDCRead INT MCP" --query "[].{appId:appId,objectId:id,identifierUris:identifierUris,signInAudience:signInAudience}" -o json

- If a single result returns with a populated `appId`: record the `appId` and `objectId`, skip to Step 2.
- If no result returns: hand the create script in 1.2 to an admin.
- If multiple results return: stop — there is a duplicate, escalate before continuing.

### 1.2 Create script (admin)

	# Admin runs this from their .adm profile in an isolated AZURE_CONFIG_DIR.
	$displayName = "SFDCRead INT MCP"
	$created = az ad app create --display-name $displayName --sign-in-audience AzureADMyOrg --query "{appId:appId,objectId:id}" -o json | ConvertFrom-Json
	$appId    = $created.appId
	$objectId = $created.objectId
	az ad app update --id $appId --identifier-uris "api://$appId"
	az ad app show --id $appId --query "{appId:appId,objectId:id,identifierUris:identifierUris}" -o json

Record `appId` and `objectId` — both are referenced by later steps and by the connector runbooks.

## Step 2: Exposed API scope (`user_impersonation`)

### 2.1 Verify

Daily driver:

	az ad app show --id <app-id> --query "api.oauth2PermissionScopes[].{value:value,isEnabled:isEnabled,id:id}" -o json

- Expected: a single entry with `value = user_impersonation` and `isEnabled = true`. Record the `id` (scope GUID).
- If missing or disabled: hand the script in 2.2 to an admin.

### 2.2 Create script (admin)

	$appId    = "<app-id-from-step-1>"
	$objectId = "<object-id-from-step-1>"
	$scopeId  = [guid]::NewGuid().Guid
	$body = @{
	  api = @{
	    oauth2PermissionScopes = @(
	      @{
	        id = $scopeId
	        adminConsentDescription = "Allow the app to call SFDCRead INT MCP on behalf of the signed-in user"
	        adminConsentDisplayName = "Access SFDCRead INT MCP as user"
	        userConsentDescription  = "Allow the app to access SFDCRead INT MCP on your behalf"
	        userConsentDisplayName  = "Access SFDCRead INT MCP"
	        type  = "User"
	        value = "user_impersonation"
	        isEnabled = $true
	      }
	    )
	  }
	} | ConvertTo-Json -Depth 6 -Compress
	$tmp = Join-Path $env:TEMP ("scope-" + [guid]::NewGuid().Guid + ".json")
	$body | Set-Content -Path $tmp -Encoding utf8
	az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$objectId" --headers "Content-Type=application/json" --body "@$tmp"
	az ad app show --id $appId --query "api.oauth2PermissionScopes" -o json
	Remove-Item $tmp -ErrorAction SilentlyContinue

## Step 3: App role (`MCP.Read`)

### 3.1 Verify

Daily driver:

	az ad app show --id <app-id> --query "appRoles[?value=='MCP.Read'].{value:value,isEnabled:isEnabled,id:id}" -o json

- Expected: a single entry with `value = MCP.Read`, `isEnabled = true`.
- If missing or disabled: hand the script in 3.2 to an admin.

### 3.2 Create script (admin)

	$objectId = "<object-id-from-step-1>"
	$roleId   = [guid]::NewGuid().Guid
	$body = @{
	  appRoles = @(
	    @{
	      id = $roleId
	      allowedMemberTypes = @("User")
	      description = "Read access to SFDCRead INT MCP"
	      displayName = "MCP Read"
	      isEnabled = $true
	      value = "MCP.Read"
	    }
	  )
	} | ConvertTo-Json -Depth 6 -Compress
	$tmp = Join-Path $env:TEMP ("role-" + [guid]::NewGuid().Guid + ".json")
	$body | Set-Content -Path $tmp -Encoding utf8
	az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$objectId" --headers "Content-Type=application/json" --body "@$tmp"
	Remove-Item $tmp -ErrorAction SilentlyContinue

If the app role already exists with a different `id`, do not regenerate — keep the existing one. Patching `appRoles` overwrites the array; merge before sending or scope to the missing entries only.

## Step 4: Redirect URIs

Each Power Automate Custom Connector and each Copilot Studio MCP Server tool generates its own redirect URI at the host `global.consent.azure-apim.net`. There is no single shared URI — the runbooks instruct the engineer to capture the per-connector URI from the client UI and hand it back here.

### 4.1 Verify

Daily driver:

	az ad app show --id <app-id> --query "web.redirectUris" -o json

- The list should include `https://localhost` (for local testing harnesses) and one `https://global.consent.azure-apim.net/redirect/<id>` entry per registered client connector.

### 4.2 Add script (admin)

Reviewer fills in the exact URI captured from the connector's Security tab. The script appends rather than overwriting.

	$appId  = "<app-id-from-step-1>"
	$newUri = "<exact-redirect-uri-from-connector-ui>"

	$current = az ad app show --id $appId --query "web.redirectUris" -o tsv
	$uris    = @($current -split "`n") + $newUri | Where-Object { $_ -and $_.Trim() } | Sort-Object -Unique
	az ad app update --id $appId --web-redirect-uris @uris
	az ad app show --id $appId --query "web.redirectUris" -o json

## Step 5: Pre-authorize APIM as a client

APIM exchanges the user's token for the user_impersonation scope on the API. Pre-authorizing the APIM client app ID suppresses an end-user consent prompt for that scope.

### 5.1 Verify

Daily driver:

	az ad app show --id <app-id> --query "api.preAuthorizedApplications[?appId=='8602e328-9b72-4f2d-a4ae-1387d013a2b3']" -o json

- Expected: a single entry with the APIM `appId` and `delegatedPermissionIds` containing the scope `id` recorded in Step 2.

### 5.2 Add script (admin)

	$objectId    = "<object-id-from-step-1>"
	$clientAppId = "8602e328-9b72-4f2d-a4ae-1387d013a2b3"
	$scopeId     = "<scope-id-from-step-2>"
	$body = @{
	  api = @{
	    preAuthorizedApplications = @(
	      @{
	        appId = $clientAppId
	        delegatedPermissionIds = @($scopeId)
	      }
	    )
	  }
	} | ConvertTo-Json -Depth 6 -Compress
	$tmp = Join-Path $env:TEMP ("preauth-" + [guid]::NewGuid().Guid + ".json")
	$body | Set-Content -Path $tmp -Encoding utf8
	az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$objectId" --headers "Content-Type=application/json" --body "@$tmp"
	Remove-Item $tmp -ErrorAction SilentlyContinue

Patching `api` replaces the `preAuthorizedApplications` array. If other clients already exist there, merge them into the body before sending.

## Step 6: Client secret in Key Vault

### 6.1 Verify

Daily driver:

	az keyvault secret show --vault-name "amn-wus2-sfdcread-kv-i01" --name "copilot-studio-client-secret-int" --query "{id:id,enabled:attributes.enabled,updated:attributes.updated,expires:attributes.expires}" -o json

- If the secret exists and `enabled = true` and `expires` is not near term: proceed.
- If missing or expired: hand the create/rotate script in 6.2 to an admin.

### 6.2 Create or rotate script (admin)

The script creates a new credential on the app registration and stores the resulting password in Key Vault. The previous secret (if any) is retained on the app reg until separately deleted — coordinate the cutover when clients are using the old value.

	$appId      = "<app-id-from-step-1>"
	$vaultName  = "amn-wus2-sfdcread-kv-i01"
	$secretName = "copilot-studio-client-secret-int"
	$displayName = "sfdcread-int-mcp-" + (Get-Date -Format "yyyyMMdd")
	$cred = az ad app credential reset --id $appId --append --display-name $displayName --years 1 --query "{password:password,endDate:endDate}" -o json | ConvertFrom-Json
	az keyvault secret set --vault-name $vaultName --name $secretName --value $cred.password --content-type "OAuth client secret for SFDCRead INT MCP (Copilot Studio + Power Automate)" --expires $cred.endDate --tags app="SFDCRead INT MCP" purpose="oauth-client" managedBy="manual"

Engineers driving onboarding retrieve the current value with a daily-driver read at runtime:

	az keyvault secret show --vault-name "amn-wus2-sfdcread-kv-i01" --name "copilot-studio-client-secret-int" --query value -o tsv

## Step 7: Access group

### 7.1 Verify

Daily driver:

	az ad group show --group "AZ_AMN_AAD_SfdcReadMcp_Int_User" --query "{id:id,displayName:displayName}" -o json

- If a group returns: record the `id`.
- If 404: hand the create script in 7.2 to an admin.

### 7.2 Create script (admin)

	$name = "AZ_AMN_AAD_SfdcReadMcp_Int_User"
	az ad group create --display-name $name --mail-nickname $name --description "Users authorized to read SFDCRead INT MCP via the MCP.Read role"

### 7.3 Assign the group to the `MCP.Read` app role

Granting the role through group assignment causes the role claim to flow into the user's token on sign-in. Without this, a user can authenticate against the app reg but the APIM policy will return 403 because the `roles` claim is missing.

	$groupObjectId   = "<group-object-id-from-7.1>"
	$appServicePrincipalObjectId = az ad sp list --filter "appId eq '<app-id-from-step-1>'" --query "[0].id" -o tsv
	$appRoleId       = "<MCP.Read role id from Step 3>"
	$body = @{
	  principalId = $groupObjectId
	  resourceId  = $appServicePrincipalObjectId
	  appRoleId   = $appRoleId
	} | ConvertTo-Json -Compress
	$tmp = Join-Path $env:TEMP ("assign-" + [guid]::NewGuid().Guid + ".json")
	$body | Set-Content -Path $tmp -Encoding utf8
	az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$appServicePrincipalObjectId/appRoleAssignedTo" --headers "Content-Type=application/json" --body "@$tmp"
	Remove-Item $tmp -ErrorAction SilentlyContinue

### 7.4 Verify a user's membership

Daily driver:

	az ad group member check --group "AZ_AMN_AAD_SfdcReadMcp_Int_User" --member-id <user-object-id>

Returns `{"value": true}` if the user is a member. Membership changes can take minutes to propagate into freshly issued tokens — instruct end users to sign out and back in if their first connection attempt returns 403.

## Step 8: APIM OAuth2 authorization server

APIM publishes the OAuth2 metadata that Power Automate and Copilot Studio consume when fetching connector swagger / MCP descriptors. This is provisioned by Terraform, not by hand.

1. Module: `infrastructure/modules/oauth2-auth-server/`
2. Wiring: `infrastructure/main.tf` calls the module conditionally on `var.sfdc_read_mcp_copilot_app_id != ""`.
3. Per-env input: `infrastructure/environments/int.tfvars` sets `sfdc_read_mcp_copilot_app_id` to the app ID from Step 1.
4. The APIM API policy template (`policies/apim-policy-sfdc-read-mcp.xml`) accepts that app ID as a second valid audience alongside the original reader app.

To apply:

	# From infrastructure/
	terraform init
	terraform plan  -var-file=environments/int.tfvars
	terraform apply -var-file=environments/int.tfvars

The pipeline (`.ado/pipelines/deploy.yml`) runs `terraform plan` automatically on PR and gates `terraform apply` behind a `ManualValidation@0` approval. Apply through the pipeline rather than locally for any change that is not a DR rebuild.

### Verify the deployed auth server (daily driver)

	az rest --method GET --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<apim-rg>/providers/Microsoft.ApiManagement/service/<apim-name>/authorizationServers/sfdc-read-mcp-int-entra?api-version=2022-08-01" --query "{name:name,authorize:properties.authorizationEndpoint,token:properties.tokenEndpoint,clientId:properties.clientId,scope:properties.defaultScope,grantTypes:properties.grantTypes}" -o json

Expected fields:
- `authorize` ends in `/oauth2/v2.0/authorize` and contains the tenant ID from the constants table
- `token` ends in `/oauth2/v2.0/token` and contains the tenant ID
- `clientId` matches the app ID from Step 1
- `scope` is `api://<app-id>/user_impersonation`
- `grantTypes` contains `authorizationCode`

## Disaster recovery quick path

If the entire INT identity surface has been lost and needs rebuilding:

1. Run Steps 1–7 in order. Each Step's `.1 Verify` block will report missing and the `.2 Create/Add` script is what an admin runs.
2. Update `infrastructure/environments/int.tfvars` with the new `sfdc_read_mcp_copilot_app_id` from Step 1.
3. Run Step 8's `terraform apply` (through the pipeline if available, locally if not).
4. Update both connector runbooks' Step 0 constants tables with the new App ID and any new scope/role GUIDs.
5. Re-run the verification reads at the top of the Copilot Studio and Power Automate runbooks.
6. Ask onboarded end users to recreate their connections — the per-connector redirect URIs change.

## What the runbooks downstream of this assume

The Copilot Studio and Power Automate runbooks assume Steps 1–8 here are complete. They verify (read-only) but do not provision. If their verification fails, the operator returns here, runs the missing step, then resumes the connector flow.
