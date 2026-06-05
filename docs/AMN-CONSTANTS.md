# AMN Infrastructure Constants
*Sourced from amn-ops-ai-plugin-marketplace/setup/foundry/scripts/foundry/shared/Foundry.Constants.ps1*

## Azure Subscriptions

| Environment | Name | Subscription ID |
|-------------|------|-----------------|
| Non-prod (Dev/QA/Train) | AMN Enterprise Services Dev | `e764d23e-759d-4cd4-8b5f-27e4c703f6a8` |
| Prod (Int/Prod) | AMN Enterprise Services Prod | `06ab2c80-382c-478f-bcd5-5e1afe984092` |

## APIM Instances

| Environment | APIM Instance | Subscription ID | Resource Group |
|-------------|---------------|-----------------|----------------|
| DEV | `amn-wus2-hub-apim-d02` | `e764d23e-759d-4cd4-8b5f-27e4c703f6a8` | `amn-wus2-hub-rg-d01` |
| QA | `amn-wus2-hub-apim-q02` | `e764d23e-759d-4cd4-8b5f-27e4c703f6a8` | (TBD) |
| INT | `amn-wus2-hub-apim-i02` | `06ab2c80-382c-478f-bcd5-5e1afe984092` | `amn-wus2-hub-rg-i01` |
| TRAIN | `amn-wus2-hub-apim-t02` | `e764d23e-759d-4cd4-8b5f-27e4c703f6a8` | (TBD) |
| PROD | `amn-wus2-hub-apim-p02` | `06ab2c80-382c-478f-bcd5-5e1afe984092` | `amn-wus2-hub-rg-p01` |

## Terraform State Storage

| Environment | Storage Account | Container | Subscription |
|-------------|-----------------|-----------|--------------|
| Dev | `amncowus2tfstatesad01` | `tfstate` | Non-prod (`e764d23e-759d-4cd4-8b5f-27e4c703f6a8`) |
| Int/Prod | `amncowus2tfstatesap01` | `tfstate` | Prod (`06ab2c80-382c-478f-bcd5-5e1afe984092`) |

**Note:** Terraform state storage is managed centrally in Shared Services infrastructure.

## ADO Service Connections

| Environment | Service Connection Name | Subscription |
|-------------|-------------------------|--------------|
| Dev/QA | `ADO-AMNEngineering-CloudOps-lower-AMN-IPS-ServiceConnection` | Non-prod |
| Int/Prod | `ADO-AMNEngineering-CloudOps-Upper-AMN-IPS-AutomaticSC` | Prod |

## Entra ID

| Property | Value |
|----------|-------|
| Tenant ID | `6232c2ec-fa42-4f27-92cd-787913fba489` |
| Tenant Name | `amnhealthcare.onmicrosoft.com` |

## ADO Organization

| Property | Value |
|----------|-------|
| Organization | `AMNEngineering` |
| Project | `Cloud Operations` |
| URL | https://dev.azure.com/AMNEngineering/Cloud%20Operations |

## Naming Conventions

### Resource Naming Pattern
```
[BU]-[region]-[role/app/project]-[res-type]-[env][instance#]
```

### Region Codes
| Azure Location | Code |
|----------------|------|
| eastus2 | eus2 |
| eastus | eus1 |
| westus2 | wus2 |
| westus3 | wus3 |
| northcentralus | ncus |
| southcentralus | scus |

### Environment Suffixes
| Environment | Suffix |
|-------------|--------|
| DEV | d |
| QA | q |
| INT | i |
| TRAIN | tr |
| PROD | p |

### Examples
- Resource Group: `co-wus2-{project}-rg-{env}{instance}`
- Function App: `co-wus2-{project}-func-{env}{instance}`
- Key Vault: `co-wus2-{project}-kv-{env}{instance}`

### Max Name Lengths
| Resource Type | Max Length |
|---------------|------------|
| Resource Group | 90 chars |
| Function App | 60 chars |
| Storage Account | 24 chars |
| Key Vault | 24 chars |
| Default | 63 chars |

## Entra Group Naming

```
AZ_AMN_AAD_{AppNamePascal}_{ENV}_{Role}
```

**Example:** `AZ_AMN_AAD_SfdcReadMcp_DEV_User`

- AppNamePascal: PascalCase, no spaces or hyphens
- ENV: DEV | QA | INT | TRAIN | PROD
- Role: User | Admin | Viewer | etc.
