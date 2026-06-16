# Entra App Registration Setup Guide
*SFDC Read MCP Reader - Complete Workflow*

> **HISTORICAL — do not follow for new setups.**
> This document describes the original "SFDC Read MCP Reader" app reg pattern, which has been superseded.
> - INT canonical app reg is now `SFDCRead INT MCP` (`42971939-bc78-4c23-963e-c3e0f87e3bd1`), provisioned by [temp/Setup-SingleAppReg-Mcp.ps1](../temp/Setup-SingleAppReg-Mcp.ps1).
> - Canonical setup runbook: [docs/onboarding/IDENTITY-BOOTSTRAP-INT.md](../docs/onboarding/IDENTITY-BOOTSTRAP-INT.md).
> - This file is preserved for archaeology only. Do not run its scripts.

## ⚠️ Important: AD Group Sync Requirement

**Before creating the Entra app registration**, Active Directory user groups must be created and synced to Entra ID.

### Timeline:
1. **Day 0, Hour 0**: Request AD groups from Identity team
2. **Day 0, Hour 0.5**: AD groups created in on-premises AD
3. **Day 0, Hour 0.5-1.0**: ⏳ **Wait 30 minutes** for AD Connect sync to Entra
4. **Day 0, Hour 1+**: Create Entra app registration
5. **Day 0, Hour 1+**: Assign AD groups to app roles

---

## Step 1: Request AD Groups (Identity Team)

**Naming Convention:** `AZ_AMN_AAD_{AppNamePascal}_{ENV}_{Role}`

### Groups Needed:

| Group Name | Purpose | Members |
|------------|---------|---------|
| `AZ_AMN_AAD_SfdcReadMcp_DEV_User` | Dev environment access | Developers, testers |
| `AZ_AMN_AAD_SfdcReadMcp_INT_User` | Int environment access | QA team, integration testers |
| `AZ_AMN_AAD_SfdcReadMcp_PROD_User` | Prod environment access | Power BI, Copilot Studio service accounts |
| `AZ_AMN_AAD_SfdcReadMcp_DEV_Admin` | Dev admin access (optional) | Lead developers |

**Rationale:**
- Power BI and Copilot Studio will authenticate as service principals
- These service principals will be added to the appropriate AD groups
- Human users (for testing) also added to groups

### Request Template:
```
Subject: AD Group Creation Request - SFDC Read MCP Reader

Please create the following AD security groups:

1. AZ_AMN_AAD_SfdcReadMcp_DEV_User
   - Description: Dev access for SFDC Read MCP API
   - Initial members: [list developer accounts]

2. AZ_AMN_AAD_SfdcReadMcp_INT_User
   - Description: Int access for SFDC Read MCP API
   - Initial members: [list QA accounts]

3. AZ_AMN_AAD_SfdcReadMcp_PROD_User
   - Description: Prod access for SFDC Read MCP API
   - Initial members: [list service principal names]

Timeline: Needed for project deployment by [date]
Contact: [your email]
```

---

## Step 2: Wait for AD Connect Sync (30 Minutes)

**Do NOT proceed until groups are synced!**

### Verify Sync Complete:
```bash
# Check if group exists in Entra
az ad group list --display-name "AZ_AMN_AAD_SfdcReadMcp_DEV_User" --query "[].{displayName:displayName,id:id}" -o table

# Should return:
# DisplayName                           Id
# AZ_AMN_AAD_SfdcReadMcp_DEV_User      <guid>
```

If command returns nothing, groups are not synced yet. Wait longer.

---

## Step 3: Create Entra App Registration

**Only after AD groups are synced to Entra!**

### 3.1 Create the App
```bash
az ad app create \
  --display-name "SFDC Read MCP Reader" \
  --identifier-uris "api://sfdc-read-mcp-reader" \
  --sign-in-audience AzureADMyOrg \
  --query "{appId:appId,objectId:id}" -o table
```

**Save the output:**
- `appId`: This goes into variable groups as `SFDC_READ_MCP_APP_ID`
- `objectId`: Needed for next steps

### 3.2 Create App Roles

Create roles that AD groups will be assigned to:

```bash
APP_OBJECT_ID="<object-id-from-above>"

# Create User role
az ad app update --id $APP_OBJECT_ID --app-roles '[
  {
    "allowedMemberTypes": ["User"],
    "description": "Read-only access to Salesforce MCP API",
    "displayName": "MCP.Read",
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "isEnabled": true,
    "value": "MCP.Read"
  }
]'
```

**Note:** Generate a new GUID for the `id` field using:
```bash
uuidgen  # Linux/Mac
# OR
[guid]::NewGuid().ToString()  # PowerShell
```

### 3.3 Create Service Principal
```bash
APP_ID="<app-id-from-step-3.1>"

az ad sp create --id $APP_ID
```

### 3.4 Get Service Principal Object ID
```bash
SP_OBJECT_ID=$(az ad sp list --display-name "SFDC Read MCP Reader" --query "[0].id" -o tsv)
echo "Service Principal Object ID: $SP_OBJECT_ID"
```

---

## Step 4: Assign AD Groups to App Roles

**Now that groups are synced and app exists, assign them:**

### 4.1 Get Group Object IDs
```bash
DEV_GROUP_ID=$(az ad group list --display-name "AZ_AMN_AAD_SfdcReadMcp_DEV_User" --query "[0].id" -o tsv)
INT_GROUP_ID=$(az ad group list --display-name "AZ_AMN_AAD_SfdcReadMcp_INT_User" --query "[0].id" -o tsv)
PROD_GROUP_ID=$(az ad group list --display-name "AZ_AMN_AAD_SfdcReadMcp_PROD_User" --query "[0].id" -o tsv)

echo "DEV Group: $DEV_GROUP_ID"
echo "INT Group: $INT_GROUP_ID"
echo "PROD Group: $PROD_GROUP_ID"
```

### 4.2 Get App Role ID
```bash
APP_ROLE_ID=$(az ad app show --id $APP_ID --query "appRoles[?value=='MCP.Read'].id" -o tsv)
echo "App Role ID: $APP_ROLE_ID"
```

### 4.3 Assign Groups to App Role
```bash
# Assign DEV group
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID/appRoleAssignments" \
  --headers "Content-Type=application/json" \
  --body "{
    \"principalId\": \"$DEV_GROUP_ID\",
    \"resourceId\": \"$SP_OBJECT_ID\",
    \"appRoleId\": \"$APP_ROLE_ID\"
  }"

# Assign INT group
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID/appRoleAssignments" \
  --headers "Content-Type=application/json" \
  --body "{
    \"principalId\": \"$INT_GROUP_ID\",
    \"resourceId\": \"$SP_OBJECT_ID\",
    \"appRoleId\": \"$APP_ROLE_ID\"
  }"

# Assign PROD group
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID/appRoleAssignments" \
  --headers "Content-Type=application/json" \
  --body "{
    \"principalId\": \"$PROD_GROUP_ID\",
    \"resourceId\": \"$SP_OBJECT_ID\",
    \"appRoleId\": \"$APP_ROLE_ID\"
  }"
```

---

## Step 5: Configure API Permissions (Optional)

If the app needs to call other Microsoft APIs:

```bash
# Example: Add Microsoft Graph User.Read permission
az ad app permission add \
  --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope

# Grant admin consent
az ad app permission admin-consent --id $APP_ID
```

---

## Step 6: Update Variable Groups

Now that the app is created, update the placeholder in variable groups:

```bash
# Get the app ID
APP_ID=$(az ad app list --display-name "SFDC Read MCP Reader" --query "[0].appId" -o tsv)
echo "App ID: $APP_ID"

# Update variable groups manually in ADO UI or via script
az pipelines variable-group variable update \
  --group-id <dev-group-id> \
  --name SFDC_READ_MCP_APP_ID \
  --value $APP_ID \
  --org https://dev.azure.com/AMNEngineering \
  --project "Cloud Operations"
```

---

## Step 7: Verify Setup

### 7.1 Verify Groups Assigned
```bash
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OBJECT_ID/appRoleAssignedTo" \
  --query "value[].{principalDisplayName:principalDisplayName,appRoleId:appRoleId}" -o table
```

Should show all three groups.

### 7.2 Test User Access
```bash
# Get token as a test user (member of dev group)
az account get-access-token --resource api://sfdc-read-mcp-reader

# Should succeed with token containing:
# - aud: api://sfdc-read-mcp-reader or <app-id>
# - roles: ["MCP.Read"]
# - groups: [<dev-group-id>]
```

---

## Timeline Summary

| Time | Activity | Owner | Status |
|------|----------|-------|--------|
| Day 0, 00:00 | Request AD groups | Project team | ⏳ Pending |
| Day 0, 00:30 | AD groups created | Identity team | ⏳ Pending |
| Day 0, 01:00 | AD Connect sync complete | Automatic | ⏳ Pending |
| Day 0, 01:15 | Verify groups in Entra | Project team | ⏳ Pending |
| Day 0, 01:30 | Create Entra app | Project team | ⏳ Pending |
| Day 0, 01:45 | Assign groups to app | Project team | ⏳ Pending |
| Day 0, 02:00 | Update variable groups | Project team | ⏳ Pending |
| Day 0, 02:15 | Test access | Project team | ⏳ Pending |

**Minimum timeline: 2 hours from AD group request to ready for deployment**

---

## Troubleshooting

### Groups not appearing in Entra
- Check AD Connect sync status
- Verify groups created in correct AD OU
- Wait full 30 minutes, sometimes up to 45 minutes

### App role assignment fails
- Verify service principal exists: `az ad sp show --id $APP_ID`
- Verify group exists in Entra: `az ad group show --group $DEV_GROUP_ID`
- Check permissions on account running commands

### Token missing roles claim
- Verify group assignment: Step 7.1
- Check user is member of assigned group: `az ad group member check --group $DEV_GROUP_ID --member-id <user-object-id>`
- Token cache issue: logout and login again

---

## Alternative: Use Placeholder First

**For Dev environment only**, you can:
1. Create variable groups with placeholder: `00000000-0000-0000-0000-000000000000`
2. Deploy infrastructure and test with mock server
3. Create real Entra app later
4. Update variable groups and redeploy

**This allows parallel work:**
- Identity team creates AD groups
- Dev team builds and tests infrastructure
- Both converge when ready for Int/Prod

---

## Checklist

- [ ] AD groups requested from Identity team
- [ ] AD groups created in on-premises AD
- [ ] 30-minute sync wait completed
- [ ] Groups verified in Entra ID
- [ ] Entra app registration created
- [ ] App roles defined
- [ ] Service principal created
- [ ] AD groups assigned to app roles
- [ ] Assignment verified
- [ ] Variable groups updated with real app ID
- [ ] Access tested with real user token
