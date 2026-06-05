# Variable Group Values - Ready to Create

Based on AMN infrastructure constants, here are the pre-filled values for each variable group.

## Dev Environment

```powershell
.\.ado\scripts\create-variable-group.ps1 -Environment dev
```

**Automated values (script will set):**
- `ARM_SUBSCRIPTION_ID`: `e764d23e-759d-4cd4-8b5f-27e4c703f6a8`
- `TF_STATE_RESOURCE_GROUP`: `co-wus2-tfstate-rg-d01`
- `APIM_NAME`: `amn-wus2-hub-apim-d02`
- `APIM_RESOURCE_GROUP`: `amn-wus2-hub-rg-d01`
- `SFDC_CLIENT_ID`: `mock-client-id`
- `SFDC_CLIENT_SECRET`: `mock-client-secret` (secret)
- `ARM_TENANT_ID`: `6232c2ec-fa42-4f27-92cd-787913fba489`
- `TF_STATE_CONTAINER`: `tfstate`

**You need to provide:**
1. **TF_STATE_STORAGE_ACCOUNT**: Storage account name in `co-wus2-tfstate-rg-d01`
   - Ask ops team or check: `az storage account list --resource-group co-wus2-tfstate-rg-d01 --query "[].name" -o tsv`

2. **SFDC_READ_MCP_APP_ID**: Entra app registration ID for `api://sfdc-read-mcp-reader`
   - Ask security team or check: `az ad app list --display-name "sfdc-read-mcp-reader" --query "[].appId" -o tsv`
   - If doesn't exist yet, use placeholder: `00000000-0000-0000-0000-000000000000`

---

## Int Environment

```powershell
.\.ado\scripts\create-variable-group.ps1 -Environment int
```

**Automated values (script will set):**
- `ARM_SUBSCRIPTION_ID`: `06ab2c80-382c-478f-bcd5-5e1afe984092`
- `TF_STATE_RESOURCE_GROUP`: `co-wus2-tfstate-rg-p01`
- `APIM_NAME`: `amn-wus2-hub-apim-d02` (int uses d02, not i02)
- `APIM_RESOURCE_GROUP`: `amn-wus2-hub-rg-d01`
- `ARM_TENANT_ID`: `6232c2ec-fa42-4f27-92cd-787913fba489`
- `TF_STATE_CONTAINER`: `tfstate`

**You need to provide:**
1. **TF_STATE_STORAGE_ACCOUNT**: Storage account name in `co-wus2-tfstate-rg-p01`
   - Ask ops team or check: `az storage account list --resource-group co-wus2-tfstate-rg-p01 --query "[].name" -o tsv`

2. **SFDC_CLIENT_ID**: Salesforce Sandbox External Client App - Client ID
   - From Salesforce admin team
   - Created in Salesforce sandbox org

3. **SFDC_CLIENT_SECRET**: Salesforce Sandbox External Client App - Client Secret
   - From Salesforce admin team
   - Will be marked as secret in ADO

4. **SFDC_READ_MCP_APP_ID**: Entra app registration ID (same as dev)

---

## Quick Lookup Commands

### Find tfstate storage accounts
```bash
# Dev tfstate storage
az storage account list \
  --resource-group co-wus2-tfstate-rg-d01 \
  --subscription e764d23e-759d-4cd4-8b5f-27e4c703f6a8 \
  --query "[].name" -o tsv

# Prod tfstate storage
az storage account list \
  --resource-group co-wus2-tfstate-rg-p01 \
  --subscription 06ab2c80-382c-478f-bcd5-5e1afe984092 \
  --query "[].name" -o tsv
```

### Check if Entra app exists
```bash
az ad app list \
  --display-name "sfdc-read-mcp-reader" \
  --query "[].{appId:appId,displayName:displayName}" -o table
```

### Verify service connections exist
```bash
az devops service-endpoint list \
  --organization https://dev.azure.com/AMNEngineering \
  --project "Cloud Operations" \
  --query "[?contains(name, 'AMN-IPS')].{name:name,id:id,type:type}" -o table
```

---

## Status Checklist

- [ ] Dev tfstate storage account identified
- [ ] Prod tfstate storage account identified
- [ ] Entra app registration created (or placeholder used)
- [ ] Salesforce Sandbox External Client App configured (int only)
- [ ] Dev variable group created
- [ ] Int variable group created
- [ ] Service connections verified (already exist)
- [ ] Pipeline created in ADO
- [ ] Production environment with approval gate created

---

## Next After Variable Groups Created

1. **Create ADO Pipeline**:
   ```powershell
   .\.ado\scripts\create-ado-pipeline.ps1
   ```

2. **Grant pipeline access to variable groups** (if not auto-granted)

3. **Test dev deployment**:
   ```bash
   az pipelines run \
     --name "sfdc-read-mcp-apim-deploy" \
     --parameters environment=dev action=plan
   ```
