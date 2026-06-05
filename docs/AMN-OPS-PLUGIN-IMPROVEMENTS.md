# AMN Ops Plugin Improvement Recommendations
*Based on SFDCRead MCP-APIM Contract Development Experience*

## High Priority

### 1. Infrastructure Constants Documentation

**Gap:** Infrastructure constants are buried in `setup/foundry/scripts/foundry/shared/Foundry.Constants.ps1` and not easily discoverable or referenced in skills.

**Impact:** Developers waste time searching for:
- Subscription IDs
- APIM instance names
- Service connection names
- Terraform state storage locations

**Recommendation:**
- Create `docs/INFRASTRUCTURE-CONSTANTS.md` at repo root
- Include table of contents with quick links
- Add examples of how to use in skills
- Link from all relevant skills

**Content should include:**
- ✅ Azure subscriptions by environment
- ✅ APIM instances mapping
- ✅ Terraform state storage locations
- ✅ Service connection names
- ✅ Naming conventions with examples
- ❌ **Missing**: Storage account names within tfstate RGs
- ❌ **Missing**: Key Vault names by environment
- ❌ **Missing**: Container Registry locations

---

### 2. Service Connection Documentation

**Gap:** Service connection names (`ADO-AMNEngineering-CloudOps-lower/Upper-AMN-IPS-ServiceConnection`) are not documented anywhere in skills or docs.

**Impact:** 
- Pipelines fail with "service connection not found"
- Developers create duplicate connections
- Inconsistent naming across projects

**Recommendation:**
- Add `docs/SERVICE-CONNECTIONS.md`
- Document all standard service connections by purpose
- Include verification commands
- Add to `mcp-apim-onboarding` and `apim-foundry-backend-onboarding` skills

**Content:**
```markdown
## Standard Service Connections

| Name | Purpose | Subscription | Scope |
|------|---------|--------------|-------|
| ADO-AMNEngineering-CloudOps-lower-AMN-IPS-ServiceConnection | Dev/QA deployments | e764d23e... | APIM, Storage, KV |
| ADO-AMNEngineering-CloudOps-Upper-AMN-IPS-AutomaticSC | Int/Prod deployments | 06ab2c80... | APIM, Storage, KV |

## Verification
\`\`\`bash
az devops service-endpoint list --org https://dev.azure.com/AMNEngineering --project "Cloud Operations"
\`\`\`
```

---

### 3. Terraform State Storage Inventory

**Gap:** `co-wus2-tfstate-rg-d01` and `co-wus2-tfstate-rg-p01` are mentioned but storage account names are unknown.

**Impact:**
- Pipeline failures during `terraform init`
- Manual discovery required for every new project
- No way to verify state storage before running pipelines

**Recommendation:**
- Add storage account inventory to constants
- Create helper script: `Get-TerraformStateStorage.ps1`
- Include in ADO pipeline setup guides

**Example helper script:**
```powershell
# Get-TerraformStateStorage.ps1
param([ValidateSet('dev','prod')][string]$Environment)

$rg = $Environment -eq 'dev' ? 'co-wus2-tfstate-rg-d01' : 'co-wus2-tfstate-rg-p01'
$sub = $Environment -eq 'dev' ? 'e764d23e-759d-4cd4-8b5f-27e4c703f6a8' : '06ab2c80-382c-478f-bcd5-5e1afe984092'

az storage account list --resource-group $rg --subscription $sub --query "[].{name:name,location:location}" -o table
```

---

### 4. MCP-APIM Contract Scaffolding Skill (Planned)

**Gap:** No automated way to create new MCP-APIM contract projects. Each project starts from scratch or copy-paste.

**Impact:**
- Inconsistent project structures
- Missing documentation or pipeline configs
- Reinventing patterns (NewRelic, SFDCRead, future projects)

**Status:** Planned in original SFDCRead design (Track B), not yet implemented.

**Recommendation:**
- Extend `mcp-apim-onboarding` skill with new capability: "Contract Project Scaffolding"
- Create `New-McpApimContract.ps1` script in `setup/foundry/scripts/apim/shared/`
- Generate complete repo structure with Terraform modules, ADO pipeline, test harness

**Example invocation:**
```powershell
.\New-McpApimContract.ps1 `
  -ProjectName "NewRelicMcp" `
  -BackendUrl "https://mcp.newrelic.com" `
  -AuthType "ApiKey" `
  -Environments "dev","int","prod" `
  -RequiresMock $false
```

**Generated structure should match:**
- Modular Terraform (reusable across contracts)
- APIM policy with security best practices
- ADO pipeline with approval gates
- Test harness structure
- Documentation templates

---

### 5. ADO Project Location Standardization

**Gap:** ADO project "Cloud Operations" is mentioned in one skill (`ado-work-item-cli`) but not consistently referenced across all ADO-related skills.

**Impact:**
- Confusion about where pipelines should be created
- Pipelines created in wrong projects
- Broken links in documentation

**Recommendation:**
- Add ADO project constant to `Foundry.Constants.ps1`:
  ```powershell
  AdoDefaults = @{
    Organization = "AMNEngineering"
    Project = "Cloud Operations"
    Url = "https://dev.azure.com/AMNEngineering/Cloud%20Operations"
  }
  ```
- Update all skills that reference ADO to use this constant
- Add to infrastructure docs

**Skills to update:**
- `mcp-apim-onboarding`
- `apim-foundry-backend-onboarding`
- `ado-work-item-cli`
- Any skill with ADO pipeline creation

---

### 6. Variable Group Naming Pattern

**Gap:** No documented standard for variable group naming across projects.

**Observation:**
- SFDCRead uses: `sfdc-read-mcp-apim-{env}-vars`
- Pattern inconsistent with other projects

**Recommendation:**
- Add to naming conventions:
  ```
  ADO Variable Group: {project-slug}-{env}-vars
  Example: sfdc-read-mcp-apim-dev-vars
  ```
- Document required variables by project type (MCP contracts, Foundry projects)
- Create template for common variables:
  - ARM subscription and tenant
  - Terraform state storage
  - APIM instance details

---

### 7. Pipeline Template for MCP Contracts

**Gap:** No reusable ADO pipeline template for MCP-APIM contracts.

**Impact:**
- Each project creates custom pipeline YAML
- Inconsistent stages, approval gates, testing patterns
- Hard to enforce security/compliance requirements

**Recommendation:**
- Create `templates/mcp-apim-pipeline.yml` in AMN Ops plugin
- Include standard stages:
  1. Terraform plan/apply
  2. Test harness execution (dev/int only)
  3. Production approval gate
  4. Deployment notifications

**Usage:**
```yaml
# In project's .ado/pipelines/deploy.yml
resources:
  repositories:
    - repository: amn-ops-templates
      type: github
      name: AMNEngineering/amn-ops-ai-plugin-marketplace

extends:
  template: templates/mcp-apim-pipeline.yml@amn-ops-templates
  parameters:
    projectName: sfdc-read-mcp-apim
    environments: [dev, int, prod]
```

---

## Medium Priority

### 8. Entra App Registration Helpers

**Gap:** No helper scripts to check if required Entra apps exist or to create them with correct scopes.

**Recommendation:**
- Create `Get-EntraAppForProject.ps1`
- Create `New-EntraAppForMcpContract.ps1`
- Add to `entra-app-registration-provisioning` skill

**Example:**
```powershell
Get-EntraAppForProject -DisplayName "sfdc-read-mcp-reader"
# Returns: App ID if exists, or instructions to create
```

---

### 9. Mock MCP Server Template

**Gap:** SFDCRead needed a full MCP protocol mock server for dev environment. This will be common for future MCP contracts.

**Recommendation:**
- Extract `MockSalesforceMcpServer.ps1` into generic template
- Add to AMN Ops plugin: `setup/mcp/templates/MockMcpServer.ps1`
- Parameterize:
  - Tool definitions
  - Response data
  - Error simulation

**Reuse for:**
- NewRelic MCP mock
- Custom MCP server development
- Integration testing

---

### 10. APIM Policy Validation Tool

**Gap:** No way to validate APIM policy XML before deployment. Errors caught at runtime.

**Recommendation:**
- Create `Test-ApimPolicy.ps1`
- Validate:
  - XML syntax
  - Required sections (inbound, outbound, on-error)
  - Named value references exist
  - Rate limit configuration
  - JWT validation settings

**Integration:**
- Add as pre-deployment step in pipelines
- Run in PR validation

---

### 11. Cost Estimation for MCP Contracts

**Gap:** No visibility into projected costs before deploying new MCP contracts.

**Recommendation:**
- Document typical costs for MCP-APIM patterns
- Create cost calculator:
  - APIM API calls per month
  - Backend compute (Functions vs external)
  - Storage (tfstate, logs)
  - Estimated monthly cost

**Add to:**
- `mcp-apim-onboarding` skill prerequisites
- Project brief template

---

### 12. Security Review Checklist

**Gap:** No standardized security checklist for MCP contracts.

**Recommendation:**
- Create `docs/MCP-APIM-SECURITY-CHECKLIST.md`
- Include:
  - ✅ JWT validation configured
  - ✅ Rate limiting per user
  - ✅ Correlation IDs in all requests
  - ✅ Secrets in Key Vault (not inline)
  - ✅ TLS certificate validation
  - ✅ Read-only enforcement (where applicable)
  - ✅ Audit logging enabled

**Integration:**
- Add to PR template
- Required for production approval

---

## Low Priority (Nice to Have)

### 13. Visual Architecture Diagrams

**Gap:** No diagram templates for MCP-APIM architecture.

**Recommendation:**
- Add Mermaid diagram templates to docs
- Include in project scaffolding
- Examples:
  - Data flow diagrams
  - Security layers
  - Deployment topology

---

### 14. Troubleshooting Runbook

**Gap:** Common issues not documented centrally.

**Recommendation:**
- Create `docs/TROUBLESHOOTING.md`
- Include:
  - "Pipeline fails with 'service connection not found'"
  - "Terraform init fails: storage account not found"
  - "APIM policy deployment fails: named value missing"
  - "JWT validation fails: wrong tenant ID"

---

### 15. Metrics and Observability

**Gap:** No standard dashboards or alerts for MCP contracts.

**Recommendation:**
- Document Application Insights queries for:
  - Request volume by API
  - Rate limit hits
  - JWT validation failures
  - Backend errors
- Create dashboard template

---

## Implementation Priority

### Phase 1 (Immediate - Blockers)
1. Infrastructure Constants Documentation
2. Service Connection Documentation
3. Terraform State Storage Inventory

### Phase 2 (Short-term - Efficiency)
4. MCP-APIM Contract Scaffolding Skill
5. ADO Project Location Standardization
6. Variable Group Naming Pattern

### Phase 3 (Medium-term - Scale)
7. Pipeline Template for MCP Contracts
8. Entra App Registration Helpers
9. Mock MCP Server Template

### Phase 4 (Long-term - Quality)
10. APIM Policy Validation Tool
11. Cost Estimation
12. Security Review Checklist
13-15. Documentation improvements

---

## Success Metrics

- **Time to create new MCP contract**: Reduce from 2-3 days to <4 hours
- **Pipeline setup time**: Reduce from 2 hours to <15 minutes
- **Documentation discovery**: 90%+ of infrastructure constants findable in <2 minutes
- **Failed deployments due to config errors**: Reduce by 80%

---

## Proposed Ownership

| Area | Owner Team | Priority |
|------|------------|----------|
| Infrastructure docs | Platform Ops | Phase 1 |
| Service connections | Platform Ops | Phase 1 |
| Scaffolding skill | Cloud Engineering (AI team) | Phase 2 |
| Pipeline templates | DevOps/SRE | Phase 3 |
| Security checklist | Security/GRC | Phase 4 |

---

## Related Projects

This list was generated during the development of:
- **Project**: SFDCRead MCP-APIM Contract
- **Repo**: https://github.com/AMNEngineering/sfdc-read-mcp-apim
- **Date**: 2026-06-05
- **Related**: NewRelic MCP-APIM, AMN Ops AI Plugin Marketplace
