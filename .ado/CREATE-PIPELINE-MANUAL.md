# Manual Pipeline Creation Guide
*Avoids PowerShell authentication lockup issues*

## Quick Link

**Open this URL in your browser:**

https://dev.azure.com/AMNEngineering/Cloud%20Operations/_apps/hub/ms.vss-build-web.ci-designer-hub?referrer=ms.vss-build-web.pipeline-create-wizard

This takes you directly to the "New Pipeline" wizard.

---

## Step-by-Step Instructions

### 1. Select GitHub
- Click **"GitHub"** (not GitHub YAML or GitHub Enterprise)
- You'll be prompted to authenticate to GitHub (OAuth)
- This is a **one-time connection** between ADO and your GitHub account

### 2. Authorize Azure Pipelines
- Click **"Authorize Azure Pipelines"**
- This allows ADO to read your GitHub repos
- Uses your existing GitHub authentication (no PAT needed)

### 3. Select Repository
- Search for: **AMNEngineering/sfdc-read-mcp-apim**
- Click on it to select

### 4. Configure Pipeline
- Select **"Existing Azure Pipelines YAML file"**
- Branch: **main**
- Path: **/.ado/pipelines/deploy.yml**
- Click **"Continue"**

### 5. Review and Save
- You'll see the YAML content preview
- Click **"Save"** dropdown → **"Save"** (not "Save and run")
- This creates the pipeline without running it

### 6. Rename (Optional)
- Default name will be: `AMNEngineering.sfdc-read-mcp-apim`
- Click on pipeline name to rename to: **sfdc-read-mcp-apim-deploy**

---

## Expected Result

✅ **Pipeline created at:**
https://dev.azure.com/AMNEngineering/Cloud%20Operations/_build?definitionId=<new-id>

✅ **Pipeline status:** Saved, not run yet

---

## Verification

Check pipeline settings:
1. Go to pipeline → Edit → Triggers
2. Verify triggers are configured:
   - ✅ Branch: main
   - ✅ Path filters: terraform/**, policies/**, .ado/pipelines/deploy.yml
3. Go to pipeline → Edit → Variables
4. Verify variable groups are linked (or link them manually)

---

## Grant Pipeline Access to Variable Groups

After creating the pipeline:

```bash
# Get pipeline ID
PIPELINE_ID=$(az pipelines list --name "sfdc-read-mcp-apim-deploy" --query "[0].id" -o tsv)

# Grant access to dev variable group
az pipelines variable-group list --group-name "sfdc-read-mcp-apim-dev-vars" --query "[0].id" -o tsv | \
  xargs -I {} az devops security permission update \
    --id {} --subject-id $PIPELINE_ID --allow 1
```

**Or manually:**
1. Go to: https://dev.azure.com/AMNEngineering/Cloud%20Operations/_library?itemType=VariableGroups
2. Click on each variable group
3. Click "Pipeline permissions"
4. Click "+" and add the pipeline

---

## Common Issues

### "Repository not found"
- Make sure you authorized Azure Pipelines to access AMNEngineering organization
- Go to: https://github.com/organizations/AMNEngineering/settings/installations
- Find "Azure Pipelines" and grant access to sfdc-read-mcp-apim repo

### "YAML file not found"
- Verify path is: `/.ado/pipelines/deploy.yml` (note leading slash)
- Verify file exists in main branch: https://github.com/AMNEngineering/sfdc-read-mcp-apim/blob/main/.ado/pipelines/deploy.yml

### "Service connection not found"
- This error appears when you try to RUN the pipeline
- It's normal - service connections will be configured in next step
- Pipeline creation itself should succeed

---

## Next Steps After Pipeline Created

1. ✅ Create variable groups (if not done yet)
2. ✅ Grant pipeline access to variable groups
3. ✅ Verify service connections exist (they do: ADO-AMNEngineering-CloudOps-lower/Upper)
4. ✅ Create production environment with approval gate
5. ✅ Run pipeline: `az pipelines run --name "sfdc-read-mcp-apim-deploy" --parameters environment=dev action=plan`

---

## Why Manual Instead of Script?

The `az pipelines create` command with GitHub repos requires interactive authentication which:
- Locks up PowerShell on Windows
- Cannot use your existing `gh` CLI authentication
- Requires a GitHub PAT or OAuth flow

**Manual approach:**
- Uses your browser's GitHub authentication
- One-time OAuth setup
- No PAT needed
- More reliable on Windows

---

## Alternative: Use GitHub Actions Instead?

If ADO pipeline creation is problematic, consider:
- GitHub Actions for CI/CD
- Deploy to Azure from GitHub
- Use OIDC for authentication (no secrets)

But for now, manual ADO pipeline creation is fastest path forward.
