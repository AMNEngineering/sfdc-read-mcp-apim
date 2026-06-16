# Deployment Workflow: Prep → Finalize Model
*For projects requiring AD groups and Entra app registrations*

> **HISTORICAL — do not follow for new setups.**
> The "SFDC Read MCP Reader" naming pattern referenced below is retired.
> - Current canonical setup runbook: [docs/onboarding/IDENTITY-BOOTSTRAP-INT.md](../docs/onboarding/IDENTITY-BOOTSTRAP-INT.md).
> - Current app reg script: [temp/Setup-SingleAppReg-Mcp.ps1](../temp/Setup-SingleAppReg-Mcp.ps1).
> - This file is preserved for archaeology only. Do not run its scripts.

## Overview

This workflow separates identity setup from infrastructure deployment, allowing parallel work and proper sequencing of dependencies with 30-minute AD sync lag.

```
┌─────────────┐
│    PREP     │ ← Day 0: Identity setup (AD groups + sync wait)
└─────┬───────┘
      │
      │ 30 min sync + verification
      │
      ▼
┌─────────────┐
│   DEPLOY    │ ← Day 0+: Infrastructure deployment (can use placeholder)
└─────┬───────┘
      │
      │ Pipeline runs, resources created
      │
      ▼
┌─────────────┐
│  FINALIZE   │ ← Day 0+: Update with real Entra app, production ready
└─────────────┘
```

---

## Phase 1: PREP (Identity Team + Parallel Dev Work)

**Goal:** Set up identity prerequisites while dev team builds infrastructure.

**Timeline:** Day 0, Hours 0-1 (minimum)

### 1.1 Request AD Groups

**Who:** Project lead  
**Action:** Submit AD group request to Identity team

**Template:**
```
Subject: AD Group Request - SFDC Read MCP Reader

Groups needed:
- AZ_AMN_AAD_SfdcReadMcp_DEV_User
- AZ_AMN_AAD_SfdcReadMcp_INT_User
- AZ_AMN_AAD_SfdcReadMcp_PROD_User

Initial members: [list]
Timeline: Needed by [date]
Project: SFDC Read MCP-APIM
Requestor: [name/email]
```

**Deliverable:** Ticket/request number from Identity team

---

### 1.2 Parallel: Create Variable Groups with Placeholder

**Who:** Platform team  
**Action:** Create ADO variable groups using placeholder Entra app ID

**Why:** Allows infrastructure build/test to proceed while waiting for AD sync

```powershell
# Use placeholder app ID
.\.ado\scripts\create-variable-group.ps1 -Environment dev
# Enter: 00000000-0000-0000-0000-000000000000

.\.ado\scripts\create-variable-group.ps1 -Environment int
# Enter: 00000000-0000-0000-0000-000000000000
```

**Deliverable:**
- ✅ `sfdc-read-mcp-apim-dev-vars` created
- ✅ `sfdc-read-mcp-apim-int-vars` created

---

### 1.3 Parallel: Test Mock Server & Local Development

**Who:** Dev team  
**Action:** Validate mock server and local Terraform

```powershell
# Test mock server
.\test-harness\mocks\MockSalesforceMcpServer.ps1

# In another terminal
.\test-harness\Test-MockServer.ps1

# Test Terraform syntax
cd terraform
terraform init -backend=false
terraform validate
```

**Deliverable:** Mock server working, Terraform validated

---

### 1.4 Wait for AD Groups Created + Synced

**Who:** Identity team → automatic sync  
**Action:** 
1. Identity team creates groups in on-premises AD
2. **Wait 30-45 minutes** for AD Connect sync to Entra
3. Verify sync complete

**Verification:**
```bash
az ad group list --display-name "AZ_AMN_AAD_SfdcReadMcp_DEV_User" --query "[].{name:displayName,id:id}" -o table
```

**Gate:** Do NOT proceed to Entra app creation until groups appear in Entra!

**Deliverable:** Groups visible in Entra ID

---

## Phase 2: DEPLOY (Dev/Int Infrastructure)

**Goal:** Deploy infrastructure to dev/int using placeholder or newly created app.

**Timeline:** Day 0, Hours 1-3

### 2.1 Create Entra App Registration (After Sync Complete)

**Who:** Platform team or Security team  
**Action:** Create app, assign AD groups

```bash
# See .ado/ENTRA-APP-SETUP.md for complete steps

# Quick version:
APP_ID=$(az ad app create --display-name "SFDC Read MCP Reader" --identifier-uris "api://sfdc-read-mcp-reader" --query appId -o tsv)
echo $APP_ID
```

**Deliverable:** Entra app ID (GUID)

---

### 2.2 Create ADO Pipeline

**Who:** Platform team  
**Action:** Create pipeline in Cloud Operations project

```powershell
.\.ado\scripts\create-ado-pipeline.ps1
```

**Deliverable:** Pipeline `sfdc-read-mcp-apim-deploy` created

---

### 2.3 Deploy to Dev (with Mock Backend)

**Who:** Dev team  
**Action:** Run pipeline for dev environment

**Option A: With placeholder (immediate deployment)**
```bash
az pipelines run \
  --name "sfdc-read-mcp-apim-deploy" \
  --parameters environment=dev action=apply \
  --org https://dev.azure.com/AMNEngineering \
  --project "Cloud Operations"
```

**Option B: Wait for real app ID (preferred)**
- Update variable group with real app ID first
- Then run pipeline

**Deliverable:** 
- APIM API created
- Named values configured
- Backend + pool created
- Policy applied

---

### 2.4 Test Dev Deployment

**Who:** Dev team  
**Action:** Validate end-to-end flow

```bash
# 1. Start mock server
.\test-harness\mocks\MockSalesforceMcpServer.ps1

# 2. Get Entra token
TOKEN=$(az account get-access-token --resource api://sfdc-read-mcp-reader --query accessToken -o tsv)

# 3. Test MCP protocol via APIM
curl -X POST https://amn-wus2-hub-apim-d02.azure-api.net/mcp/sfdc-read/dev \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
```

**Deliverable:** Successful MCP response from mock server via APIM

---

### 2.5 Deploy to Int (with Salesforce Sandbox)

**Who:** Platform team  
**Action:** Deploy to int with real Salesforce backend

**Prerequisites:**
- Salesforce Sandbox External Client App created
- Credentials added to variable group

```bash
az pipelines run \
  --name "sfdc-read-mcp-apim-deploy" \
  --parameters environment=int action=apply
```

**Deliverable:** Int environment connected to Salesforce sandbox

---

## Phase 3: FINALIZE (Production Ready)

**Goal:** Update placeholders with production values, enable production deployment.

**Timeline:** Day 1+ (after testing complete)

### 3.1 Update Variable Groups with Real Values

**Who:** Platform team  
**Action:** Replace placeholder app ID with real app ID

```bash
APP_ID=$(az ad app list --display-name "SFDC Read MCP Reader" --query "[0].appId" -o tsv)

# Update dev variable group
az pipelines variable-group variable update \
  --group-id <dev-group-id> \
  --name SFDC_READ_MCP_APP_ID \
  --value $APP_ID \
  --org https://dev.azure.com/AMNEngineering \
  --project "Cloud Operations"

# Repeat for int
az pipelines variable-group variable update \
  --group-id <int-group-id> \
  --name SFDC_READ_MCP_APP_ID \
  --value $APP_ID
```

**Deliverable:** Variable groups updated with real app ID

---

### 3.2 Redeploy Dev/Int with Real App (Optional)

**Who:** Dev team  
**Action:** Redeploy to ensure real app ID works

```bash
az pipelines run --name "sfdc-read-mcp-apim-deploy" --parameters environment=dev action=apply
```

**Deliverable:** Dev/int using real Entra authentication

---

### 3.3 Request Salesforce Production External Client App

**Who:** Salesforce admin  
**Action:** Create production Salesforce app with mcp_api scope

**See:** `docs/SALESFORCE-SETUP.md` for complete steps

**Deliverable:** Prod Salesforce client ID + secret

---

### 3.4 Create Prod Variable Group

**Who:** Platform team  
**Action:** Create prod variable group with real values

```powershell
.\.ado\scripts\create-variable-group.ps1 -Environment prod
# Provide real Entra app ID
# Provide real Salesforce prod credentials
```

**Deliverable:** `sfdc-read-mcp-apim-prod-vars` created

---

### 3.5 Create Production Approval Gate

**Who:** GRC + Platform Ops  
**Action:** Configure ADO environment with approvers

```bash
az pipelines environment create \
  --name "sfdc-read-mcp-production" \
  --org https://dev.azure.com/AMNEngineering \
  --project "Cloud Operations"
```

**Manual step:** Add approvers in ADO UI (GRC team, Ops lead)

**Deliverable:** Production approval gate configured

---

### 3.6 Deploy to Production

**Who:** Platform team with GRC approval  
**Action:** Run production deployment

```bash
az pipelines run --name "sfdc-read-mcp-apim-deploy" --parameters environment=prod action=plan

# Review plan, then apply
az pipelines run --name "sfdc-read-mcp-apim-deploy" --parameters environment=prod action=apply
```

**Approval required:** GRC team manually approves in ADO

**Deliverable:** Production deployment complete

---

### 3.7 Coordinate with Power BI and Copilot Studio Teams

**Who:** Project lead  
**Action:** Provide connection details to client teams

**Information to share:**
- APIM endpoint URL
- Entra app ID for token acquisition
- Required AD group membership
- Example connection configurations

**Deliverable:** Client teams testing against production

---

## Timeline Summary

| Phase | Duration | Can Start | Blocking Dependencies |
|-------|----------|-----------|----------------------|
| **PREP** | 1-2 hours | Day 0 | None |
| ↳ Request AD groups | 5 min | Immediate | None |
| ↳ Create variable groups (placeholder) | 10 min | Immediate | None |
| ↳ Test mock server | 15 min | Immediate | None |
| ↳ AD sync wait | 30-45 min | After groups created | AD group creation |
| **DEPLOY** | 1-2 hours | After AD sync | AD groups in Entra |
| ↳ Create Entra app | 15 min | After AD sync | Groups synced |
| ↳ Create pipeline | 10 min | After Entra app | App created |
| ↳ Deploy dev | 20 min | After pipeline | Pipeline + variable groups |
| ↳ Deploy int | 20 min | After dev tested | Salesforce sandbox app |
| **FINALIZE** | 2-4 hours | After int tested | Testing complete |
| ↳ Update variable groups | 10 min | Anytime | Real app ID exists |
| ↳ Salesforce prod app | 30-60 min | By Salesforce admin | Salesforce admin approval |
| ↳ Create prod variables | 10 min | After Salesforce prod app | Prod credentials |
| ↳ Production approval gate | 15 min | Anytime | GRC coordination |
| ↳ Deploy prod | 30 min | After approval gate | Manual GRC approval |

**Minimum end-to-end:** 4-6 hours (with all approvals and no delays)

---

## Parallel Work Opportunities

To minimize total time:

```
Hour 0:00 ────┬─── Request AD groups (Identity)
              │
              ├─── Create variable groups with placeholder (Platform)
              │
              └─── Build/test mock server (Dev)

Hour 0:30 ──────── AD groups created (Identity)
              ↓
Hour 0:45 ──────── Wait for sync...
              ↓
Hour 1:00 ──────── Verify groups synced (Platform)
              ↓
Hour 1:15 ────┬─── Create Entra app + assign groups (Platform/Security)
              │
              ├─── Create ADO pipeline (Platform)
              │
              └─── Deploy dev with placeholder (Dev)

Hour 2:00 ──────── Update variable groups with real app (Platform)
              ↓
Hour 2:15 ────┬─── Redeploy dev/int (Dev)
              │
              └─── Request Salesforce prod app (Salesforce Admin)

Hour 3:00 ──────── Deploy int, start testing (QA)
              ↓
Hour 4:00+ ─────── Finalize prod deployment (Platform + GRC approval)
```

---

## Checklist: Ready for Production

- [ ] AD groups created and synced to Entra
- [ ] Entra app created and groups assigned
- [ ] Dev environment deployed and tested
- [ ] Int environment deployed and tested with Salesforce sandbox
- [ ] Salesforce prod External Client App created
- [ ] Prod variable group created with real credentials
- [ ] Production approval gate configured
- [ ] GRC team briefed and approvals granted
- [ ] Power BI and Copilot Studio teams notified
- [ ] Monitoring and alerting configured
- [ ] Runbook documented for operations team

---

## Rollback Plan

If issues discovered after production deployment:

1. **Immediate:** Pipeline destroy (requires approval)
   ```bash
   az pipelines run --name "sfdc-read-mcp-apim-deploy" --parameters environment=prod action=destroy
   ```

2. **Graceful:** Disable API in APIM (no resource deletion)
   ```bash
   az apim api update --api-id api-sfdc-read-prod --service-name amn-wus2-hub-apim-p02 --resource-group amn-wus2-hub-rg-p01 --subscription-required true
   ```

3. **Emergency:** Remove backend from pool (breaks connections immediately)

---

## Future: Automate Prep Phase

**Long-term improvement:** Create skill in AMN Ops plugin to automate:
- AD group request submission
- Sync wait verification
- Entra app creation with proper roles
- Group assignment automation

**Benefit:** Reduce prep phase from 1-2 hours to 15 minutes active work + sync wait
