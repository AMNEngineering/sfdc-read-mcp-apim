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

## Step 1: Create Variable Groups

Run the provided script to create variable groups for each environment:

```powershell
.\create-variable-group.ps1 -Environment dev
.\create-variable-group.ps1 -Environment int
.\create-variable-group.ps1 -Environment prod
```

### Variable Group: `sfdc-read-mcp-apim-dev-vars`

| Variable | Value | Secret | Source |
|----------|-------|--------|--------|
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID (non-prod) | No | Azure |
| `ARM_TENANT_ID` | `6232c2ec-fa42-4f27-92cd-787913fba489` | No | Azure |
| `TF_STATE_RESOURCE_GROUP` | `co-wus2-tfstate-rg-d01` | No | Azure |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account in co-wus2-tfstate-rg-d01 | No | Azure |
| `TF_STATE_CONTAINER` | `tfstate` | No | Azure |
| `APIM_NAME` | `amn-wus2-hub-apim-d02` | No | Azure |
| `APIM_RESOURCE_GROUP` | `amn-wus2-hub-rg-d01` | No | Azure |
| `SFDC_CLIENT_ID` | `mock-client-id` (dev only) | No | Mock |
| `SFDC_CLIENT_SECRET` | `mock-client-secret` (dev only) | **Yes** | Mock |
| `SFDC_READ_MCP_APP_ID` | Entra app registration ID | No | Entra |

**Note:** ARM_CLIENT_ID and ARM_CLIENT_SECRET are managed by the service connection, not in variable groups.

### Variable Group: `sfdc-read-mcp-apim-int-vars`

Same structure as dev, with these changes:
- `ARM_SUBSCRIPTION_ID` → Production subscription ID
- `TF_STATE_RESOURCE_GROUP` → `co-wus2-tfstate-rg-p01`
- `TF_STATE_STORAGE_ACCOUNT` → Storage account in co-wus2-tfstate-rg-p01
- `SFDC_CLIENT_ID` → Salesforce Sandbox External Client App ID
- `SFDC_CLIENT_SECRET` → Salesforce Sandbox secret (from Key Vault)

### Variable Group: `sfdc-read-mcp-apim-prod-vars`

Same structure as dev, with these changes:
- `ARM_SUBSCRIPTION_ID` → Production subscription ID
- `TF_STATE_RESOURCE_GROUP` → `co-wus2-tfstate-rg-p01`
- `TF_STATE_STORAGE_ACCOUNT` → Storage account in co-wus2-tfstate-rg-p01
- `APIM_NAME` → `amn-wus2-hub-apim-p02`
- `APIM_RESOURCE_GROUP` → `amn-wus2-hub-rg-p01`
- `SFDC_CLIENT_ID` → Salesforce Production External Client App ID
- `SFDC_CLIENT_SECRET` → Salesforce Production secret (from Key Vault)

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
  - Int: `amn-wus2-hub-apim-d02`
  - Prod: `amn-wus2-hub-apim-p02`
- Storage Blob Data Contributor on Terraform state storage:
  - Dev: `co-wus2-tfstate-rg-d01`
  - Int/Prod: `co-wus2-tfstate-rg-p01`

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

## Step 5: Terraform State Storage Setup

If not already configured, create Terraform state storage:

```bash
# Variables
RG_NAME="tfstate-rg"
STORAGE_ACCOUNT="tfstatestorage$(date +%s | tail -c 6)"  # Must be globally unique
CONTAINER="tfstate"
LOCATION="westus2"
SUBSCRIPTION_ID="<non-prod-subscription-id>"

# Create resources
az group create --name $RG_NAME --location $LOCATION --subscription $SUBSCRIPTION_ID
az storage account create --name $STORAGE_ACCOUNT --resource-group $RG_NAME --location $LOCATION --sku Standard_LRS --subscription $SUBSCRIPTION_ID
az storage container create --name $CONTAINER --account-name $STORAGE_ACCOUNT --subscription $SUBSCRIPTION_ID
```

Update variable groups with:
- `TF_STATE_RESOURCE_GROUP`: `tfstate-rg`
- `TF_STATE_STORAGE_ACCOUNT`: `<storage-account-name>`
- `TF_STATE_CONTAINER`: `tfstate`

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

- [ ] All three variable groups created and populated
- [ ] All three service connections created and tested
- [ ] Production environment created with approval gate
- [ ] Pipeline created and linked to GitHub repo
- [ ] Terraform state storage created and accessible
- [ ] Service principals have APIM Contributor role
- [ ] Service principals have access to Key Vault (if used)
- [ ] Entra app registration created (`api://sfdc-read-mcp-reader`)
- [ ] Salesforce External Client Apps configured (int/prod)

---

## Testing the Setup

### Test Dev Deployment
```bash
# Trigger pipeline manually
az pipelines run \
  --name "sfdc-read-mcp-apim-deploy" \
  --parameters environment=dev action=plan \
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

### Pipeline fails with "Variable group not found"
- Ensure variable group names match exactly: `sfdc-read-mcp-apim-<env>-vars`
- Grant pipeline access to variable groups

### Terraform init fails
- Verify service connection has Storage Blob Data Contributor role
- Check state storage account and container exist
- Verify subscription ID in variable group is correct

### APIM deployment fails with permission denied
- Verify service principal has APIM Contributor role
- Check APIM instance name and resource group are correct

### Policy deployment fails
- Named values must exist before policy applies
- Check policy XML template interpolation for `${tenant_id}` and `${environment}`

---

## Security Notes

⚠️ **Never commit secrets to git:**
- Use Key Vault references in variable groups
- Mark sensitive variables as "secret"
- Rotate secrets regularly

⚠️ **Service principal least privilege:**
- Scope to specific resource groups when possible
- Use separate service principals per environment
- Enable managed identity for long-term deployments

⚠️ **Approval gates:**
- Production requires manual approval
- Configure timeout (24 hours recommended)
- Add multiple approvers for redundancy
