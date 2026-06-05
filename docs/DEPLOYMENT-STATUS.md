# Deployment Status & Blockers

**Last Updated:** 2026-06-05

## Current State

### ✅ Dev Environment - READY TO TEST
- **Status**: Pipeline running (Build #627885)
- **Backend**: Mock MCP server (localhost:8080) ✅
- **Credentials**: Mock Salesforce credentials ✅
- **Entra App**: Placeholder (00000000-0000-0000-0000-000000000000) ✅
- **Testing**: Can fully validate APIM → Mock server flow

**What works:**
- Mock Salesforce MCP server implements full protocol
- All 6 tools returning synthetic data
- APIM infrastructure deploying

**What's next:**
- Validate APIM resources created
- Test end-to-end: APIM → Mock server
- Verify policy (JWT, rate limiting, OAuth swap)

---

### ⏳ Int Environment - BLOCKED (Waiting for External Dependencies)

**Status**: Variable group created, but cannot deploy/test yet

**Blockers:**

#### 1. Salesforce Sandbox External Client App ❌
**Owner**: Salesforce Admin Team  
**Status**: Not created yet  
**Needed**:
- Salesforce Sandbox org
- External Client App created
- OAuth scopes: `mcp_api`, `refresh_token`
- Client ID + Client Secret

**Current value in variable group**: Placeholder `000` / `***`

**Impact**: Cannot test real Salesforce integration in int

---

#### 2. Entra App Registration ❌
**Owner**: Security Team / Identity Team  
**Status**: Not created (using placeholder)

**Prerequisites:**
1. AD groups must be created first:
   - `AZ_AMN_AAD_SfdcReadMcp_DEV_User`
   - `AZ_AMN_AAD_SfdcReadMcp_INT_User`
   - `AZ_AMN_AAD_SfdcReadMcp_PROD_User`
2. Wait 30 minutes for AD → Entra sync
3. Create Entra app registration
4. Assign AD groups to app roles

**See**: `.ado/ENTRA-APP-SETUP.md` for complete workflow

**Current value**: Placeholder `00000000-0000-0000-0000-000000000000`

**Impact**: JWT validation will fail with real tokens

---

#### 3. Copilot Studio Agent Details ❌
**Owner**: Power Platform Team / Copilot Studio Team  
**Status**: Not configured

**Needed**:
- Copilot Studio service principal / managed identity
- Connection configuration to APIM endpoint
- Test scenarios / use cases

**Impact**: Cannot validate Copilot Studio client integration

---

#### 4. Power BI Connection Details ❌
**Owner**: Power BI Team / BI Platform Team  
**Status**: Not configured

**Needed**:
- Power BI service principal / connection setup
- Data source configuration
- Test datasets / reports

**Impact**: Cannot validate Power BI client integration

---

### 🚫 Prod Environment - BLOCKED (Multiple Dependencies)

**Status**: Not ready for deployment

**Blockers:**
1. ❌ All int blockers must be resolved first
2. ❌ Salesforce Production External Client App (requires change management)
3. ❌ Production Entra app with real AD groups
4. ❌ CAB (Change Advisory Board) approval required
5. ❌ ADO environment `sfdc-read-mcp-production` with manual approval gate
6. ❌ GRC team sign-off on security review

**See**: AMN Ops Skills for CAB approval process

---

## What Can Be Done Now

### ✅ Immediate (No Blockers)
1. **Validate dev deployment**
   - Check APIM resources created
   - Test mock server integration
   - Verify policy enforcement
   - Run test harness

2. **Documentation**
   - Architecture diagrams
   - Security review documentation
   - Runbook for operations

3. **Test harness development**
   - Expand mock server scenarios
   - Add more test cases
   - Performance testing

---

## Dependency Matrix

| Environment | APIM | Terraform | Mock Server | Real SFDC | Entra App | Copilot Studio | Power BI | Can Deploy? | Can Test? |
|-------------|------|-----------|-------------|-----------|-----------|----------------|----------|-------------|-----------|
| **Dev** | ✅ | ✅ | ✅ | N/A | ⏳ | N/A | N/A | ✅ YES | ✅ YES (mock) |
| **Int** | ✅ | ✅ | N/A | ❌ | ⏳ | ❌ | ❌ | ⚠️ YES* | ❌ NO |
| **Prod** | ✅ | ✅ | N/A | ❌ | ❌ | ❌ | ❌ | ❌ NO | ❌ NO |

*Int can deploy infrastructure, but cannot test without real credentials

---

## Critical Path to Production

```
Week 1 (Current):
├─ ✅ Dev infrastructure deployed
├─ ✅ Mock server validated
└─ ✅ APIM policy tested

Week 2-3 (Identity Setup):
├─ Request AD groups → Identity team
├─ Wait 30 min for AD sync
├─ Create Entra app + assign groups
└─ Update variable groups with real app ID

Week 2-3 (Salesforce Setup - Parallel):
├─ Request Salesforce Sandbox External Client App
├─ Salesforce admin creates app
├─ Receive credentials
└─ Update int variable group

Week 3-4 (Int Deployment):
├─ Deploy to int with real credentials
├─ Test Salesforce sandbox integration
├─ Coordinate with Copilot Studio team
├─ Coordinate with Power BI team
└─ End-to-end validation

Week 4-6 (Prod Preparation):
├─ Request Salesforce Prod External Client App
├─ Submit CAB request
├─ Security review
├─ Create prod environment in ADO
├─ Configure approval gates
└─ GRC sign-off

Week 6+ (Prod Deployment):
├─ CAB approval received
├─ Scheduled maintenance window
├─ Deploy to prod
├─ Validation with Copilot Studio
├─ Validation with Power BI
└─ Production monitoring

Earliest prod deployment: 6-8 weeks from now
```

---

## Action Items by Team

### Platform Engineering (This Team)
- [x] Create GitHub repo
- [x] Build Terraform modules
- [x] Create ADO pipeline
- [x] Create variable groups
- [x] Build mock MCP server
- [x] Deploy dev environment
- [ ] Validate dev deployment (in progress)
- [ ] Create test harness
- [ ] Write documentation

### Identity Team
- [ ] Create AD groups (3 groups: DEV, INT, PROD)
- [ ] Wait for AD sync (30 minutes)
- [ ] Notify when groups available in Entra

### Security Team
- [ ] Create Entra app registration
- [ ] Assign AD groups to app roles
- [ ] Provide app ID to platform team

### Salesforce Admin Team
- [ ] Create Sandbox External Client App
- [ ] Configure OAuth scopes (mcp_api, refresh_token)
- [ ] Create read-only permission set
- [ ] Provide credentials to platform team
- [ ] (Later) Create Production External Client App

### Copilot Studio Team
- [ ] Define use cases for Salesforce integration
- [ ] Provide service principal details
- [ ] Test connection to int environment
- [ ] Validate production connection

### Power BI Team
- [ ] Define datasets needed from Salesforce
- [ ] Provide service principal details
- [ ] Test connection to int environment
- [ ] Validate production connection

### GRC / Compliance Team
- [ ] Review security architecture
- [ ] Review APIM policy configuration
- [ ] Sign off on read-only enforcement
- [ ] Approve CAB request for prod

---

## Communication Plan

**Weekly Status Updates:**
- Send to: Platform stakeholders, Security, Salesforce admins
- Include: Current blockers, next steps, ETA changes

**Blocker Escalation:**
- If blocker > 1 week: Escalate to project lead
- If blocker > 2 weeks: Executive escalation

**Key Milestones to Communicate:**
- ✅ Dev deployed (communicate today)
- ⏳ Int deployed (when Salesforce creds received)
- ⏳ Prod deployed (after CAB approval)

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Salesforce admin unavailable | Medium | High | Start request now, escalate if no response in 3 days |
| AD group sync issues | Low | Medium | Test sync with non-prod groups first |
| Entra app creation delayed | Medium | Medium | Use placeholder in dev, parallel track with identity team |
| CAB approval delayed | High | High | Submit request early, emphasize read-only scope |
| Copilot Studio integration issues | Medium | High | Early engagement, provide test environment |

---

## Success Criteria

### Dev Environment ✅
- [x] Mock server implements full MCP protocol
- [ ] APIM resources deployed successfully
- [ ] Policy enforces JWT validation (with mock)
- [ ] Rate limiting works
- [ ] End-to-end test passes

### Int Environment ⏳
- [ ] Connected to Salesforce Sandbox
- [ ] Real OAuth flow works
- [ ] Salesforce queries return data
- [ ] Read-only enforcement validated
- [ ] Copilot Studio can connect
- [ ] Power BI can connect

### Prod Environment 🚫
- [ ] CAB approval received
- [ ] Production credentials configured
- [ ] Manual approval gate works
- [ ] Real-world use cases validated
- [ ] Monitoring and alerting operational
- [ ] Runbook complete

---

## Contact Information

| Team | Contact | Purpose |
|------|---------|---------|
| Platform Engineering | [Lead Developer] | Technical questions |
| Identity Team | [Identity Contact] | AD groups, Entra app |
| Salesforce Admin | [SFDC Contact] | External Client App |
| Security Team | [Security Contact] | Entra app, security review |
| GRC Team | [GRC Contact] | CAB approval, compliance |

---

## Notes

- Dev environment is fully functional with mock backend
- Int environment can be deployed but not tested without real credentials
- Prod environment requires CAB approval (see AMN Ops Skills)
- Timeline is estimates - adjust based on dependency resolution
