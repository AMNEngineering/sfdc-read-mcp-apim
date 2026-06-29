# Azure DevOps Setup Guide

## ADO Project Location

**Organization:** `AMNEngineering`  
**Project:** `Cloud Operations`  
**URL:** https://dev.azure.com/AMNEngineering/Cloud%20Operations

## Prerequisites

- Azure CLI installed and authenticated
- ADO CLI extension installed: `az extension add --name azure-devops`
- Permissions: Project Administrator role in Cloud Operations project
- GitHub repository access: https://github.com/AMNEngineering/sfdc-read-mcp-apim

---

## Step 1: Pipeline Configuration

**The pipeline does not use ADO variable groups.** Configuration lives in three places:

1. **Hardcoded `variables:` block** in `.ado/pipelines/deploy.yml` — service connection names, shared-services state storage accounts, vertical name. Edit the YAML to change these.
2. **Service connection SPN credentials** — `ARM_CLIENT_ID` / `ARM_CLIENT_SECRET` / `ARM_TENANT_ID` are auto-exported from the `AzureCLI@2` task (`addSpnToEnvironment: true`). Nothing to configure beyond ensuring the service connection exists (Step 2).
3. **APIM Named Values** (per environment) — Salesforce `client_id` / `client_secret` / token URL / MCP base URL / MCP path are stored as APIM Named Values, with the two secrets backed by Key Vault references. These are managed by Terraform (see `infrastructure/modules/apim_api/`), not by the pipeline.

### Subscription / state storage map (informational)

| Env | Subscription | State storage account | State container | State key |
|-----|-------------|----------------------|-----------------|-----------|
| dev | `e764d23e-759d-4cd4-8b5f-27e4c703f6a8` | `amncowus2tfstatesad01` | `sfdc-read` | `sfdc-read-dev.tfstate` |
| int | `06ab2c80-382c-478f-bcd5-5e1afe984092` | `amncowus2tfstatesap01` | `sfdc-read` | `sfdc-read-int.tfstate` |

The state storage accounts both live in subscription `43c5a646-c00c-4c59-a332-df854c5dd08c`, resource group `co-wus2-tfstate-rg-p01` (shared services). See Step 5.

### Legacy variable-group flow (not consumed by current pipeline)

`.ado/scripts/create-variable-group.ps1` and `.ado/VARIABLE-GROUP-VALUES.md` describe a variable-group approach that was planned but never wired into `deploy.yml`. They are kept for historical context; nothing the pipeline runs reads them today.

---

## Step 2: Service Connections (Pre-existing)

✅ **Already exist** - No creation needed:

### Dev/QA Service Connection
- **Name:** `ADO-AMNEngineering-CloudOps-lower-AMN-IPS-ServiceConnection`
- **Scope:** Non-prod subscription
- **Used by:** dev environment

### Int/Prod Service Connection
- **Name:** `ADO-AMNEngineering-CloudOps-Upper-AMN-IPS-AutomaticSC`
- **Scope:** Production subscription
- **Used by:** int and prod environments

**Required Permissions (verify with Ops team):**
- APIM Contributor on APIM instances:
  - Dev: `amn-wus2-hub-apim-d02`
  - Int: `amn-wus2-hub-apim-i02`
  - Prod: `amn-wus2-hub-apim-p02`
- Storage Blob Data Contributor on Terraform state storage account `amncowus2tfstatesad01` (lower SPN) and `amncowus2tfstatesap01` (upper SPN), both in `co-wus2-tfstate-rg-p01` under the shared-services subscription `43c5a646-c00c-4c59-a332-df854c5dd08c`.

---

## Step 3: Create ADO Environment for Production Approval

```bash
az devops configure --defaults organization=https://dev.azure.com/AMNEngineering project="Cloud Operations"

# Create environment
az pipelines environment create --name "sfdc-read-mcp-production" --description "Production environment for SFDC Read MCP APIM contract"
```

**Manual Approval Setup:**
1. Go to: https://dev.azure.com/AMNEngineering/Cloud%20Operations/_environments
2. Click on `sfdc-read-mcp-production`
3. Click "..." → "Approvals and checks"
4. Add "Approvals" check
5. Add approvers: GRC team, Platform Ops lead
6. Configure: "Require minimum number of reviewers" → 1

---

## Step 4: Create the Pipeline

Run the provided script:

```powershell
.\create-ado-pipeline.ps1
```

Or manually:
1. Go to: https://dev.azure.com/AMNEngineering/Cloud%20Operations/_build
2. Click "New pipeline"
3. Select "GitHub"
4. Select repository: `AMNEngineering/sfdc-read-mcp-apim`
5. Select "Existing Azure Pipelines YAML file"
6. Path: `/.ado/pipelines/deploy.yml`
7. Save (don't run yet)

**Pipeline Name:** `sfdc-read-mcp-apim-deploy`

---

## Step 5: Terraform State Storage (Already Provisioned)

State storage is shared across the AMN tenant — **nothing to bootstrap for this repo**. The pipeline initializes state against the existing shared-services storage accounts (see Step 1 table). The `sfdc-read` container is created automatically on first `terraform init` if it does not already exist.

Verify the SPNs behind the service connections have **Storage Blob Data Contributor** on the storage accounts listed in Step 2. If `terraform init` fails with an auth error, that role is the first thing to check.

---

## Step 6: Grant Service Principal Access to Key Vault

If using Key Vault for secrets:

```bash
# For each service principal
SP_OBJECT_ID="<service-principal-object-id>"
KV_NAME="<key-vault-name>"

az keyvault set-policy \
  --name $KV_NAME \
  --object-id $SP_OBJECT_ID \
  --secret-permissions get list
```

---

## Validation Checklist

- [ ] Both service connections exist and have access to their target subscriptions
- [ ] Production environment created with approval gate (when prod stages are enabled)
- [ ] Pipeline created and linked to GitHub repo
- [ ] SPNs have **Storage Blob Data Contributor** on the shared-services state storage accounts
- [ ] SPNs have **APIM Contributor** on the target APIM instances
- [ ] SPNs have read access to the per-environment Key Vaults (RBAC `Key Vault Secrets User`, or equivalent access policy — see Step 6) so APIM Named Values can dereference Key Vault secrets
- [ ] Per-environment Entra app registrations exist (one app per env; `api://{guid}` identifier URI)
- [ ] Salesforce External Client Apps configured (int/prod)

---

## Testing the Setup

### Triggering the pipeline

The pipeline is **branch-triggered**, not parameterized:

- **Push to `main`** → runs all stages (dev plan → dev apply → dev verify → int plan → int apply → int verify). Both apply stages have a `ManualValidation@0` gate that waits for approval before applying.
- **PR against `main`** → runs the dev plan stage only (validation; no apply).

To kick a run without a code change, use the ADO UI ("Run pipeline" on `sfdc-read-mcp-apim-deploy`) or:

```bash
az pipelines run \
  --name "sfdc-read-mcp-apim-deploy" \
  --branch main \
  --organization https://dev.azure.com/AMNEngineering \
  --project "Cloud Operations"
```

### Test Mock Server Locally
```powershell
# Start mock server
.\test-harness\mocks\MockSalesforceMcpServer.ps1

# In another terminal
.\test-harness\Test-MockServer.ps1
```

---

## Troubleshooting

### Terraform init fails
- Verify service connection has Storage Blob Data Contributor role on the shared-services state storage account
- Check state storage account and container exist
- Verify the subscription ID / storage account names in `.ado/pipelines/deploy.yml` match the table in Step 1

### APIM deployment fails with permission denied
- Verify service principal has APIM Contributor role
- Check APIM instance name and resource group are correct

### Policy deployment fails
- Named values must exist before policy applies
- Check policy XML template interpolation for `${tenant_id}` and `${environment}`

---

## Security Notes

⚠️ **Never commit secrets to git:**
- Salesforce client_id/client_secret are stored as APIM Named Values backed by Key Vault references (managed by Terraform in `infrastructure/modules/apim_api/`)
- Rotate secrets regularly

⚠️ **Service principal least privilege:**
- Scope to specific resource groups when possible
- Use separate service principals per environment
- Enable managed identity for long-term deployments

⚠️ **Approval gates:**
- Production requires manual approval
- Configure timeout (24 hours recommended)
- Add multiple approvers for redundancy
