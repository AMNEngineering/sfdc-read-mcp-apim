# Salesforce MCP Read-Only APIM Contract

Azure API Management gateway for Salesforce Hosted MCP Server (sobject-reads), exposing read-only Salesforce data to Power BI and Copilot Studio agents with Entra ID authentication.

## Architecture

```
Power BI / Copilot Studio
    ↓ (Entra JWT: api://sfdc-read-mcp-reader)
Azure APIM (d02/p02)
    ↓ (Salesforce OAuth: mcp_api scope)
Salesforce Hosted MCP Server (sobject-reads)
    ↓ (user permissions enforced)
Salesforce Org
```

## Layered Security Model

1. **APIM Layer**: Entra JWT validation (caller must hold the `MCP.Read` app role, granted via membership in `AZ_AMN_AAD_SfdcReadMcp_{Env}_User`), rate limiting (300 req/min per user), audit logging
2. **MCP Server Layer**: `sobject-reads` server type (no mutation capabilities)
3. **Salesforce Layer**: Read-only user permissions, FLS, sharing rules

## Design Intent — Limited Exposure is the Product

This gateway exists to **constrain** what Entra-authenticated callers see, not to mirror the full Salesforce org through APIM. Treat scope decisions accordingly:

- **Not every SObject is exposed.** The Run-As user's permission set (`MCP_ReadOnly_Access`) defines the visible surface, and that surface is deliberately narrow.
- **Not every field is exposed.** FLS on the Run-As user further trims columns within an exposed object.
- **Read-only.** No mutation tools, no mutation paths.

### Implication for tests and development

A data-access error from Salesforce (`INVALID_TYPE`, "field not accessible", "sObject not supported", etc.) is **not by default a bug.** It usually means the perm set or FLS is doing its job. The smoke test reflects this — such errors are `WARN`, not `FAIL`, and don't break the CI gate.

Before recommending a perm-set or FLS widening, confirm with the data owner whether the SObject/field is *supposed* to be in scope for this gateway's consumers. Default answer is no.

Symptoms that *are* bugs (and should fail loudly): JWT validation gaps, broken OAuth exchange, body/header mangling in the policy, routing to the wrong backend, protocol-level errors (`tools/list` shape, session-id handling, etc.).

## Repository Structure

```
├── .ado/                  # Azure DevOps pipeline and scripts
├── terraform/             # Infrastructure as Code (modular)
├── policies/              # APIM policy definitions
├── test-harness/          # PowerShell test suite + mock MCP server
├── examples/              # Client configuration samples
└── docs/                  # Architecture and deployment guides
```

## Quick Start

### Prerequisites

- Azure CLI authenticated with APIM contributor role
- Terraform >= 1.6
- PowerShell >= 7.0
- Access to AMN APIM instances (d02/p02)

### Local Development

1. **Start the mock Salesforce MCP server (Dev only)**:
   ```powershell
   .\test-harness\mocks\MockSalesforceMcpServer.ps1
   ```

2. **Deploy to Dev environment**:
   ```bash
   cd terraform
   terraform init
   terraform plan -var-file=environments/dev.tfvars
   terraform apply -var-file=environments/dev.tfvars
   ```

3. **Run test suite**:
   ```powershell
   .\test-harness\Invoke-SfdcReadTest.ps1 -Environment dev -TestSuite all
   ```

### ADO Pipeline Deployment

See [DEPLOYMENT.md](docs/DEPLOYMENT.md) for ADO pipeline setup and usage.

## Environments

| Environment | APIM Instance | Backend | Access Group (Entra) | Approval Gate |
|-------------|---------------|---------|----------------------|----------------|
| Dev | `amn-wus2-hub-apim-d02` | Inline APIM mock | `AZ_AMN_AAD_SfdcReadMcp_Dev_User` | Auto on push to `main` (no approval) |
| Int | `amn-wus2-hub-apim-i02` | Salesforce Sandbox | `AZ_AMN_AAD_SfdcReadMcp_Int_User` | Manual (`int_apply`) |
| Prod | `amn-wus2-hub-apim-p02` | Salesforce Production | `AZ_AMN_AAD_SfdcReadMcp_Prod_User` | Manual (GRC + Ops, out of scope this phase) |

Group membership grants the `MCP.Read` app role on the per-environment Entra app registration, which is what the APIM JWT-validation policy checks. AD Connect syncs the on-prem AD groups into Entra. Optional admin group: `AZ_AMN_AAD_SfdcReadMcp_Dev_Admin` for lead developers.

```bash
# See who currently has access in int:
az ad group member list --group "AZ_AMN_AAD_SfdcReadMcp_Int_User" \
  --query "[].{name:displayName, upn:userPrincipalName}" -o table
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - Security model and data flow
- [Deployment](docs/DEPLOYMENT.md) - Pipeline usage and troubleshooting
- [Salesforce Setup](docs/SALESFORCE-SETUP.md) - External Client App configuration
- [Power BI Setup](examples/power-bi-setup.md) - Client connection guide

## AI Skill (WIP)

- [SFDCRead Auth Architecture Skill](.claude/skills/sfdc-read-auth-architecture/SKILL.md) - Project-local guidance for APIM to Salesforce auth pattern selection
- [Auth Decision Matrix](.claude/skills/sfdc-read-auth-architecture/AUTH-DECISION-MATRIX.md) - Quick flow selection and validation checklist

## Testing

The test harness validates:
- ✅ JWT validation and Entra authentication
- ✅ Rate limiting enforcement
- ✅ Read-only enforcement (mutation rejection)
- ✅ Audit trail (correlation IDs, user identity)
- ✅ Power BI and Copilot Studio client patterns

## Support

For issues or questions, contact the AMN Platform Engineering team.

## Related Projects

- [NewRelic MCP APIM](https://github.com/AMNEngineering/newrelic-mcp-apim)
- [AMN Ops AI Plugin Marketplace](https://github.com/AMNEngineering/amn-ops-ai-plugin-marketplace)
