# JWT Bearer Flow — Wrap-up

**Status:** ABANDONED. `client_credentials` confirmed working end-to-end against the Salesforce MCP endpoint on **2026-06-09**.
**Last activity:** 2026-06-09
**Owner (our side):** Bart Elia / Platform Engineering
**Owner (SF side):** Drew Plastridge, Gene Fudala, Bruce Nicholls, Ramya Krishna Tummala

---

## Outcome

The premise that drove this work — that the Salesforce hosted MCP server rejects `client_credentials` tokens and requires per-user authentication — turned out to be **wrong**, or has since been fixed on the Salesforce side.

On 2026-06-09 the SF org returned a `client_credentials` token with scope `sfap_api mcp_api api` (note the new `mcp_api` scope) and `api_instance_url=https://api.salesforce.com`. Initialize, `tools/list`, and `getUserInfo` against `https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads` all returned 200. See [SALESFORCE-REPRO-2026-06-08.md](SALESFORCE-REPRO-2026-06-08.md) for the working calls.

The APIM policy has been reverted to `client_credentials` (commit pending) and JWT Bearer–specific Terraform wiring removed.

---

## What was abandoned

| Artifact | Disposition |
|----------|-------------|
| `policies/apim-policy-sfdc-read-mcp.xml` (JWT Bearer rewrite) | Reverted to client_credentials, routes to `api.salesforce.com` instead of `instance_url` |
| Terraform: `sfdc_jwt_audience`, `sfdc_run_as_username`, `sfdc_certificate_name` vars + named values | Removed |
| Terraform: `azurerm_api_management_certificate.sfdc_jwt` + KV cert data sources | Removed |
| Key Vault cert `sfdc-jwt-signing` on `amn-wus2-sfdcread-kv-i01` (thumbprint `C09724670843C1CB5F3E09EF2E0778B631058BE5`, expires 2028-06-08) | **Unused.** Can be decommissioned at the team's convenience. No urgency since it costs nothing while idle. |
| `.secrets/sfdc-jwt-signing-int.pfx` / `.cer` (local, gitignored) | Can be deleted from local machine when convenient |
| `infrastructure/scripts/New-SfdcJwtSigningCert.ps1` | Retained (idempotent, harmless; useful if JWT Bearer ever resurfaces as a need) |
| `test-harness/Test-SalesforceMcpJwtBearer.ps1` | Retained — proven JWT generation is reference-quality and may be useful for unrelated SF JWT flows |

---

## Why we tried JWT Bearer

The original failure mode (2026-06-08): MCP endpoint returned 404/401 on all attempts with `client_credentials` tokens. Salesforce's published MCP setup docs at the time called for per-user authentication (Authorization Code + PKCE). PKCE pass-through would have forced every Copilot Studio / Power BI end user to have a Salesforce license and per-user provisioning — incompatible with our identity model (Entra/AD groups at APIM, single integration identity in SF).

The Salesforce team suggested JWT Bearer as a way to preserve our single-integration-identity model while satisfying SF's per-user audit requirement (`sub` claim names the run-as user).

We never got the JWT Bearer token exchange to succeed (every attempt returned `invalid_client`, blocked at the SF token endpoint). On 2026-06-09 the original premise dissolved: `client_credentials` started working, MCP started responding, and JWT Bearer became unnecessary.

---

## If JWT Bearer is ever needed again

The investigation log, working JWT generator, support-case template, and SF-side confirmations from 2026-06-08 are preserved in git history (see commits on this branch prior to the 2026-06-09 revert). The signing cert is still in Key Vault, idle. Re-enabling the path would require: (a) re-uploading vars to int.tfvars, (b) re-introducing the cert data sources in main.tf, (c) restoring the JWT-bearer policy block — all recoverable from the git history of `policies/apim-policy-sfdc-read-mcp.xml` and `infrastructure/`.

---

## Key references

- [SALESFORCE-REPRO-2026-06-08.md](SALESFORCE-REPRO-2026-06-08.md) — working-call reference (formerly a failure repro)
- [STATUS-REPORT-2026-06-07.md](STATUS-REPORT-2026-06-07.md) — broader project status
- [DEPLOYMENT-STATUS.md](DEPLOYMENT-STATUS.md) — what's deployed where
- [CUSTOM-MCP-SERVER-PLAN.md](CUSTOM-MCP-SERVER-PLAN.md) — Plan B (also no longer needed)
- Salesforce JWT Bearer docs: https://help.salesforce.com/s/articleView?id=xcloud.remoteaccess_oauth_jwt_flow.htm
- Salesforce hosted MCP docs: https://developer.salesforce.com/docs/platform/hosted-mcp-servers/guide/
