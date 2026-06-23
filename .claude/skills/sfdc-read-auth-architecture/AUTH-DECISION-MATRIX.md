# Auth Decision Matrix (SFDCRead)

## Goal
Support many clients through one APIM identity while keeping Salesforce access read-only and least-privileged.

## Matrix

| Option | Interactive at runtime | Single integration identity | Operational complexity | Notes |
|---|---|---|---|---|
| Client Credentials | No | Yes | Low | Use if explicitly allowed for target endpoint/policy. |
| JWT Bearer | No | Yes | Medium | Certificate lifecycle required. Good app-only fallback if allowed. |
| PKCE + Refresh Broker | No (after bootstrap) | Yes | Medium/High | One-time interactive bootstrap; store refresh token in Key Vault. |

## Selection Rule
1. Try client credentials for the target endpoint.
2. If rejected by policy, test JWT bearer.
3. If app-only grants are blocked, use PKCE bootstrap plus refresh-token broker.

## Minimum Evidence Before Declaring Success
1. Token request returns expected response for chosen flow.
2. Target endpoint call succeeds with that token.
3. APIM end-to-end call from test client succeeds.
4. Failure paths are documented with exact error payloads.
