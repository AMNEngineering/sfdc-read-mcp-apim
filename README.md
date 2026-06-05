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

1. **APIM Layer**: Entra JWT validation, rate limiting (300 req/min per user), audit logging
2. **MCP Server Layer**: `sobject-reads` server type (no mutation capabilities)
3. **Salesforce Layer**: Read-only user permissions, FLS, sharing rules

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

| Environment | APIM Instance | Backend | Approval Gate |
|-------------|---------------|---------|---------------|
| Dev | amn-wus2-hub-apim-d02 | Mock MCP server (localhost) | None |
| Int | amn-wus2-hub-apim-d02 | Salesforce Sandbox | None |
| Prod | amn-wus2-hub-apim-p02 | Salesforce Production | Manual (GRC + Ops) |

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - Security model and data flow
- [Deployment](docs/DEPLOYMENT.md) - Pipeline usage and troubleshooting
- [Salesforce Setup](docs/SALESFORCE-SETUP.md) - External Client App configuration
- [Power BI Setup](examples/power-bi-setup.md) - Client connection guide

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
